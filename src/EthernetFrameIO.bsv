import RegFile :: * ;
import FIFOF :: *;
import ClientServer :: *;
import PAClib :: *;
import PrimUtils :: *;
import Vector :: *;
import GetPut :: *;
import Printf:: *;

import EthernetTypes :: *;
import NapWrapper :: *;

import Settings :: *;
import DataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;

import ConnectableF :: *;

interface InputPacketClassifier;
    interface PipeIn#(EthernetNapBeatEntry) ethRawPacketPipeIn;
    interface PipeOut#(DataStream) rdmaRawPacketPipeOut;
    interface PipeOut#(ThinMacIpUdpMetaDataForRecv) rdmaMacIpUdpMetaPipeOut;
    interface PipeOut#(DataStream) otherRawPacketPipeOut;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings);
endinterface


typedef 14 IP_HEADER_OFFSET_IN_FIRST_BEAT;

typedef 2 UDP_HEADER_OFFSET_IN_SECOND_BEAT;


typedef enum {
    InputPacketClassifierStateHandleFirstBeat = 0,
    InputPacketClassifierStateHandleSecondBeat = 1,
    InputPacketClassifierStateHandleMoreBeat = 2
} InputPacketClassifierState deriving(Bits, FShow, Eq);

typedef struct {
    Bool mustNotBeRdmaPacket;
    ThinMacIpUdpMetaDataForRecv macIpUdpMeta;
    Bool isAddrMatch;
} EthernetPacketMetaExtractPipelineEntry deriving(Bits, FShow, Eq);

typedef struct {
    Bool isRdmaPacket;
    Bool isError;
    Bool isAddrMatch;
} EthernetPacketMeta deriving(Bits, FShow, Eq);

(*synthesize*)
module mkInputPacketClassifier(InputPacketClassifier);
    Reg#(InputPacketClassifierState) stateReg <- mkReg(InputPacketClassifierStateHandleFirstBeat);

    FIFOF#(EthernetNapBeatEntry) ethRawPacketInQ <- mkFIFOF;
    FIFOF#(DataStream) rdmaRawPacketOutQ <- mkFIFOF;
    FIFOF#(ThinMacIpUdpMetaDataForRecv) rdmaMacIpUdpMetaOutQ <- mkFIFOF;
    FIFOF#(DataStream) otherRawPacketOutQ <- mkFIFOF;

    FIFOF#(DataStream) waitingForRouteQ <- mkFIFOF;
    FIFOF#(EthernetPacketMeta) ethPacketMetaQ <- mkFIFOF;

    Reg#(EthernetPacketMetaExtractPipelineEntry) ethPacketMetaExtractPipelineEntry <- mkRegU;

    Reg#(Maybe#(LocalNetworkSettings)) networkSettingsReg <- mkReg(tagged Invalid);

    // the dst IP filed begins at #30 byte of first beat, so the first beat only has the higher 16 bits
    Reg#(Bit#(16)) partialDstIpAddrHigher16BitsReg <- mkRegU;

    rule handleFirstBeatStage if (stateReg == InputPacketClassifierStateHandleFirstBeat);
        let beat = ethRawPacketInQ.first;
        ethRawPacketInQ.deq;

        EthernetNapRecvFirstBeat beatPayload = unpack(beat.data);

        let ds = DataStream{
            data: swapEndianByte(beatPayload.data),
            byteNum: fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH)),
            startByteIdx: 0,
            isFirst: beat.sop,
            isLast: beat.eop
        };

        waitingForRouteQ.enq(ds);

        // Achronix Ethernet NAP make sure that each ethernet frame is at least two beat.
        immAssert(
            beat.sop && !beat.eop,
            "mkInputPacketClassifier first beat error",
            $format("sop should be True and eop should be False in handleFirstBeatStage, beat=", fshow(beat))
        );

        EthHeader ethHeader         = unpack(truncateLSB(pack(ds.data)));

        // Important! For a 32B beat, the first beat only have the first (32-14=18) Byte of IP header
        // i.e., the dest IP field in this ip header is broken.
        IpHeader  partialIpHeader   = unpack(truncateLSB(pack(ds.data) << valueOf(IP_HEADER_OFFSET_IN_FIRST_BEAT) * valueOf(BYTE_WIDTH)));

        Bool mustNotBeRdmaPacket = False;
        if (ethHeader.ethType != fromInteger(valueOf(ETH_TYPE_IP))) begin
            mustNotBeRdmaPacket = True;
        end
        if (partialIpHeader.ipProtocol != fromInteger(valueOf(IP_PROTOCOL_UDP))) begin
            mustNotBeRdmaPacket = True;
        end

        let macIpUdpMeta = ThinMacIpUdpMetaDataForRecv{
            srcMacAddr: ethHeader.srcMacAddr,
            ipDscp: partialIpHeader.ipDscp,
            ipEcn: partialIpHeader.ipEcn,
            srcIpAddr:partialIpHeader.srcIpAddr,
            srcPort: ?
        };

        let macAddrMatch = False;
        if (networkSettingsReg matches tagged Valid .netSettings) begin
            Bool unicastMatch = netSettings.macAddr == ethHeader.dstMacAddr;
            Bool broadcastMatch = ethHeader.dstMacAddr == -1;
            macAddrMatch = unicastMatch || broadcastMatch;
            if (!macAddrMatch) begin
                $display(
                    "time=%0t:", $time, toRed(" mkInputPacketClassifier mac address check failed"),
                    toBlue(", netSettings="), fshow(netSettings),
                    toBlue(", ethHeader="), fshow(ethHeader)
                );
            end
        end

        let outPipelineEntry =  EthernetPacketMetaExtractPipelineEntry{
            mustNotBeRdmaPacket: mustNotBeRdmaPacket,
            macIpUdpMeta: macIpUdpMeta,
            isAddrMatch: macAddrMatch
        };
        ethPacketMetaExtractPipelineEntry <= outPipelineEntry;

        partialDstIpAddrHigher16BitsReg <= truncateLSB(partialIpHeader.dstIpAddr);
        
        stateReg <= InputPacketClassifierStateHandleSecondBeat;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkInputPacketClassifier handleFirstBeatStage"),
        //     toBlue(", partialIpHeader="), fshow(partialIpHeader),
        //     toBlue(", ds="), fshow(ds),
        //     toBlue(", outPipelineEntry="), fshow(outPipelineEntry)
        // );
    endrule

    rule handleSecondBeatStage if (stateReg == InputPacketClassifierStateHandleSecondBeat);
        let beat = ethRawPacketInQ.first;
        ethRawPacketInQ.deq;

        EthernetNapRecvOtherBeat beatPayload = unpack(beat.data);


        ByteEnBitNum byteNum =  beat.eop ? (
                beatPayload.mod == 0 ? fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH)) : zeroExtend(beatPayload.mod)
            ) : fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH));

        let ds = DataStream{
            data: swapEndianByte(beatPayload.data),
            byteNum: unpack(zeroExtend(byteNum)),
            startByteIdx: 0,
            isFirst: beat.sop,
            isLast: beat.eop
        };

        waitingForRouteQ.enq(ds);

        immAssert(
            !beat.sop,
            "mkInputPacketClassifier second beat error",
            $format("sop should be False handleSecondBeatStage, beat=", fshow(beat))
        );

        IpAddr dstIpAddr = truncateLSB({partialDstIpAddrHigher16BitsReg, pack(ds.data)});
        Bool ipAddrMatch = False;
        if (networkSettingsReg matches tagged Valid .netSettings) begin
            Bool unicastMatch = netSettings.ipAddr == dstIpAddr;
            ipAddrMatch = unicastMatch;

            if (!ipAddrMatch) begin
                $display(
                    "time=%0t:", $time, toRed(" mkInputPacketClassifier IP address check failed"),
                    toBlue(", netSettings="), fshow(netSettings),
                    toBlue(", dstIpAddr="), fshow(dstIpAddr)
                );
            end
        end

        let isAddrMatch = ethPacketMetaExtractPipelineEntry.isAddrMatch && ipAddrMatch;

        UdpHeader udpHeader = unpack(truncateLSB(pack(ds.data) << valueOf(UDP_HEADER_OFFSET_IN_SECOND_BEAT) * valueOf(BYTE_WIDTH)));

        Bool mustNotBeRdmaPacket = False;
        if (udpHeader.dstPort != fromInteger(valueOf(UDP_PORT_RDMA))) begin
            mustNotBeRdmaPacket = True;
        end
        mustNotBeRdmaPacket = mustNotBeRdmaPacket || ethPacketMetaExtractPipelineEntry.mustNotBeRdmaPacket;

        // This is the final check condition. so if it is not "mustn't be RDMA", then it is RDMA
        Bool isRDMA = !mustNotBeRdmaPacket;
        ethPacketMetaQ.enq(EthernetPacketMeta{
            isRdmaPacket: isRDMA,
            isError: beatPayload.flags.error,
            isAddrMatch: isAddrMatch
        });

        let macIpUdpMeta = ethPacketMetaExtractPipelineEntry.macIpUdpMeta;
        macIpUdpMeta.srcPort = udpHeader.srcPort;

        if (isAddrMatch && isRDMA && !beatPayload.flags.error) begin
            rdmaMacIpUdpMetaOutQ.enq(macIpUdpMeta);
        end
        
        stateReg <= beat.eop ? InputPacketClassifierStateHandleFirstBeat : InputPacketClassifierStateHandleMoreBeat;
        
        // $display(
        //     "time=%0t:", $time, toGreen(" mkInputPacketClassifier handleSecondBeatStage"),
        //     toBlue(", ds="), fshow(ds),
        //     toBlue(", macIpUdpMeta="), fshow(macIpUdpMeta)
        // );
    endrule

    rule handleMoreBeatStage if (stateReg == InputPacketClassifierStateHandleMoreBeat);
        let beat = ethRawPacketInQ.first;
        ethRawPacketInQ.deq;

        immAssert(
            !beat.sop,
            "mkInputPacketClassifier second beat error",
            $format("sop should be False handleMoreBeatStage, beat=", fshow(beat))
        );

        EthernetNapRecvOtherBeat beatPayload = unpack(beat.data);
        ByteEnBitNum byteNum =  beat.eop ? (
                beatPayload.mod == 0 ? fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH)) : zeroExtend(beatPayload.mod)
            ) : fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH));

        let ds = DataStream{
            data: swapEndianByte(beatPayload.data),
            byteNum: unpack(zeroExtend(byteNum)),
            startByteIdx: 0,
            isFirst: beat.sop,
            isLast: beat.eop
        };

        waitingForRouteQ.enq(ds);
        if (beat.eop) begin
            stateReg <= InputPacketClassifierStateHandleFirstBeat;
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" mkInputPacketClassifier handleMoreBeatStage"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    rule dispatchStream;
        let ds = waitingForRouteQ.first;
        waitingForRouteQ.deq;
        let ethPktMeta = ethPacketMetaQ.first;

        // discard error packet.
        if (!ethPktMeta.isError && ethPktMeta.isAddrMatch) begin
            if (ethPktMeta.isRdmaPacket) begin
                rdmaRawPacketOutQ.enq(ds);
            end
            else begin
                otherRawPacketOutQ.enq(reverseStream(ds));
            end
        end
        else begin
            $display(
                "time=%0t:", $time, toRed(" mkInputPacketClassifier dispatchStream >>>>> DISCARD PACKET <<<<<"),
                toBlue(", ethPktMeta.isError="), fshow(ethPktMeta.isError),
                toBlue(", ethPktMeta.isAddrMatch="), fshow(ethPktMeta.isAddrMatch),
                toBlue(", ds="), fshow(ds)
            );
        end

        if (ds.isLast) begin
            ethPacketMetaQ.deq;
        end
    endrule


    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings);
        networkSettingsReg <= tagged Valid networkSettings;
    endmethod

    interface ethRawPacketPipeIn        = toPipeIn(ethRawPacketInQ);
    interface rdmaRawPacketPipeOut      = toPipeOut(rdmaRawPacketOutQ);
    interface rdmaMacIpUdpMetaPipeOut   = toPipeOut(rdmaMacIpUdpMetaOutQ);
    interface otherRawPacketPipeOut     = toPipeOut(otherRawPacketOutQ);
endmodule

typedef TSub#(BYTE_NUM_OF_TWO_BEATS, MAC_IP_UDP_TOTAL_HDR_BYTE_WIDTH) MAX_BYTE_NUM_FOR_BTH_AND_ETH_IN_SECOND_BEAT;  // 22
typedef MAX_BYTE_NUM_FOR_BTH_AND_ETH_IN_SECOND_BEAT BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT;    // 22
typedef TMul#(BYTE_WIDTH, BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT) BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT;
typedef TSub#(MAC_IP_UDP_TOTAL_HDR_BYTE_WIDTH, DATA_BUS_BYTE_WIDTH) MAC_IP_UDP_HEADER_REMAINDER_BYTE_COUNT_IN_SECOND_BEAT;  // 10

typedef TSub#(BYTE_NUM_OF_THREE_BEATS, MAC_IP_UDP_TOTAL_HDR_BYTE_WIDTH) MAX_BYTE_NUM_FOR_ETH_IN_THIRD_BEAT; 

typedef TSub#(BYTE_NUM_OF_THREE_BEATS, MAC_IP_UDP_TOTAL_HDR_BYTE_WIDTH) RDMA_FIXED_HEADER_BYTE_NUM; // 54
typedef Bit#(TMul#(BYTE_WIDTH, RDMA_FIXED_HEADER_BYTE_NUM)) RdmaFixedHeaderBuffer;

// The above BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT and BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT can also be defined and calculated by
// the following method:
// ETH + IP + UDP = 14 + 20 + 8 = 42, each beat has 32 byte
// So, in the second beat, the BTH offset should be at 32 - (42 - 32) = 22
// typedef 176 BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT;  // 22 byte * 8 bit
// typedef TDiv#(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT, BYTE_WIDTH) BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT;


typedef Bit#(TSub#(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT, SizeOf#(BTH))) RdmaExtendHeaderFragmentInSecondBeat;

interface RdmaHeaderExtractor;
    interface PipeIn#(DataStream) ethPipeIn;
    interface PipeOut#(RdmaRecvPacketMeta) rdmaPacketMetaPipeOut;
    interface PipeOut#(DataStream) rdmaPayloadPipeOut;
endinterface

typedef enum {
    RdmaHeaderExtractorStateHandleFirstBeat = 0,
    RdmaHeaderExtractorStateHandleSecondBeat = 1,
    RdmaHeaderExtractorStateHandleThirdBeat = 2,
    RdmaHeaderExtractorStateHandleMoreBeat = 3
} RdmaHeaderExtractorState deriving(Bits, FShow, Eq);

(*synthesize*)
module mkRdmaHeaderExtractor(RdmaHeaderExtractor);

    Reg#(RdmaHeaderExtractorState) stateReg <- mkReg(RdmaHeaderExtractorStateHandleFirstBeat);

    FIFOF#(DataStream) ethPipeInQ                   <- mkFIFOF;
    FIFOF#(RdmaRecvPacketMeta) rdmaPacketMetaPipeOutQ   <- mkFIFOF;
    FIFOF#(DataStream) rdmaPayloadPipeOutQ          <- mkFIFOF;

    Reg#(RdmaRecvPacketMeta) partialRdmaMetaReg <- mkRegU;
    Reg#(Bool) payloadStreamOutputIsFirstReg <- mkReg(True);

    Integer bthEndBitOneBasedPosInSecondBeat = valueOf(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT) - valueOf(SizeOf#(BTH));

    rule handleFirstBeat if (stateReg == RdmaHeaderExtractorStateHandleFirstBeat);
        // first beat is totally ETH and IP header, skip them
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;
        stateReg <= RdmaHeaderExtractorStateHandleSecondBeat;
        // $display(
        //     "time=%0t:", $time, toGreen(" mkRdmaHeaderExtractor handleFirstBeat"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    rule handleSecondBeat if (stateReg == RdmaHeaderExtractorStateHandleSecondBeat);
        // second beat has some part of IP header, total UDP header, total BTH header, and maybe some RDMA extended header or payload
        // we only interested in the BTH and following part.

        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;

        BTH bth = unpack(ds.data[valueOf(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT) - 1 : bthEndBitOneBasedPosInSecondBeat]);
        let hasPayload = rdmaOpCodeHasPayload(bth.opcode);

        RdmaExtendHeaderFragmentInSecondBeat extendHeaderFragment = ds.data[bthEndBitOneBasedPosInSecondBeat-1 : 0];
        RdmaExtendHeaderBuffer rdmaExtendHeaderBuf = zeroExtendLSB(extendHeaderFragment);


        let outPacketMeta = RdmaRecvPacketMeta{
            header: RdmaBthAndExtendHeader {
                bth: bth,
                rdmaExtendHeaderBuf: rdmaExtendHeaderBuf
            },
            hasPayload: hasPayload
        };

        partialRdmaMetaReg <= outPacketMeta;

        if (ds.isLast) begin
            // this is defensive code, shoud not enter this branch. but if it does, goto handle first packet state.
            immFail(
                "The second beat must not be last beat.",
                $format("ds=", fshow(ds))
            );
            stateReg <= RdmaHeaderExtractorStateHandleFirstBeat;
        end
        else begin
            stateReg <= RdmaHeaderExtractorStateHandleThirdBeat;
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRdmaHeaderExtractor handleSecondBeat"),
        //     toBlue(", ds="), fshow(ds),
        //     toBlue(", rdmaTotalHeaderLen=0x%x"), rdmaTotalHeaderLen,
        //     toBlue(", rdmaHeaderIsComplete="), fshow(rdmaHeaderIsComplete),
        //     toBlue(", outPacketMeta="), fshow(outPacketMeta),
        //     toBlue(", payloadDs="), outputPayloadInThisBeat ? fshow(payloadDs) : $format("No Payload In This beat")
        // );
    endrule

    rule handleThirdBeat if (stateReg == RdmaHeaderExtractorStateHandleThirdBeat);
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;

        let rdmaMeta = partialRdmaMetaReg;
        RdmaExtendHeaderFragmentInSecondBeat rdmaExtendHeaderSecondBeatFragment = truncateLSB(rdmaMeta.header.rdmaExtendHeaderBuf);
        rdmaMeta.header.rdmaExtendHeaderBuf = truncateLSB({rdmaExtendHeaderSecondBeatFragment, ds.data});

        rdmaPacketMetaPipeOutQ.enq(rdmaMeta);
    

        stateReg <= ds.isLast ? RdmaHeaderExtractorStateHandleFirstBeat : RdmaHeaderExtractorStateHandleMoreBeat;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRdmaHeaderExtractor handleThirdBeat"),
        //     toBlue(", ds="), fshow(ds),
        //     toBlue(", payloadDs="), rdmaMeta.hasPayload ? fshow(payloadDs) : $format("No Payload"),
        //     toBlue(", rdmaMeta="), fshow(rdmaMeta)
        // );
    endrule

    rule handleMoreBeat if (stateReg == RdmaHeaderExtractorStateHandleMoreBeat);
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;
        ds.isFirst = payloadStreamOutputIsFirstReg;
        rdmaPayloadPipeOutQ.enq(ds);
        if (ds.isLast) begin
            stateReg <= RdmaHeaderExtractorStateHandleFirstBeat;
            payloadStreamOutputIsFirstReg <= True;
        end
        else begin
            payloadStreamOutputIsFirstReg <= False;
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkRdmaHeaderExtractor handleMoreBeat"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    interface ethPipeIn             = toPipeIn(ethPipeInQ);
    interface rdmaPacketMetaPipeOut = toPipeOut(rdmaPacketMetaPipeOutQ);
    interface rdmaPayloadPipeOut    = toPipeOut(rdmaPayloadPipeOutQ);
endmodule




module mkIpHdrCheckSumStream#(
    PipeOut#(IpHeader) ipHeaderStream
)(PipeOut#(IpCheckSum)) 
    provisos(
        NumAlias#(TDiv#(IP_HDR_WORD_WIDTH, 2), firstStageOutNum),
        NumAlias#(TAdd#(IP_CHECKSUM_WIDTH, 1), firstStageOutWidth),
        NumAlias#(TDiv#(firstStageOutNum, 4), secondStageOutNum),
        NumAlias#(TAdd#(firstStageOutWidth, 2), secondStageOutWidth)
    );

    function Bit#(TAdd#(width, 1)) add(Bit#(width) a, Bit#(width) b) = zeroExtend(a) + zeroExtend(b);
    function Bit#(TAdd#(width, 1)) pass(Bit#(width) a) = zeroExtend(a);

    FIFOF#(Vector#(firstStageOutNum, Bit#(firstStageOutWidth))) firstStageOutBuf <- mkFIFOF;
    FIFOF#(Vector#(secondStageOutNum, Bit#(secondStageOutWidth))) secondStageOutBuf <- mkFIFOF;
    FIFOF#(IpCheckSum) ipCheckSumOutBuf <- mkFIFOF;

    rule firstStageAdder;
        let ipHeader = ipHeaderStream.first;
        ipHeaderStream.deq;
        Vector#(IP_HDR_WORD_WIDTH, Word) ipHdrVec = unpack(pack(ipHeader));
        let ipHdrVecReducedBy2 = mapPairs(add, pass, ipHdrVec);
        firstStageOutBuf.enq(ipHdrVecReducedBy2);
    endrule

    rule secondStageAdder;
        let firstStageOutVec = firstStageOutBuf.first;
        firstStageOutBuf.deq;
        let firstStageOutReducedBy2 = mapPairs(add, pass, firstStageOutVec);
        let firstStageOutReducedBy4 = mapPairs(add, pass, firstStageOutReducedBy2);
        secondStageOutBuf.enq(firstStageOutReducedBy4);
    endrule

    rule lastStageAdder;
        let secondStageOutVec = secondStageOutBuf.first;
        secondStageOutBuf.deq;

        let secondStageOutReducedBy2 = mapPairs(add, pass, secondStageOutVec);

        let sum = secondStageOutReducedBy2[0];
        Bit#(TLog#(IP_HDR_WORD_WIDTH)) overFlow = truncateLSB(sum);
        IpCheckSum remainder = truncate(sum);
        IpCheckSum checkSum = ~(remainder + zeroExtend(overFlow));
        ipCheckSumOutBuf.enq(checkSum);
    endrule

    return toPipeOut(ipCheckSumOutBuf);
endmodule



interface EthernetPacketGenerator;
    interface PipeIn#(ThinMacIpUdpMetaDataForSend) macIpUdpMetaPipeIn;
    interface PipeIn#(RdmaSendPacketMeta) rdmaPacketMetaPipeIn;
    interface PipeIn#(DataStream) rdmaPayloadPipeIn;
    interface PipeOut#(EthernetNapBeatEntry) ethernetPacketPipeOut;

    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings);
endinterface

typedef enum {
    EthernetPacketGeneratorStateGenFirstBeat = 0,
    EthernetPacketGeneratorStateGenSecondBeat = 1,
    EthernetPacketGeneratorStateGenThirdBeat = 2,
    EthernetPacketGeneratorStateGenMoreBeat = 3
} EthernetPacketGeneratorState deriving(Bits, FShow, Eq);


function UdpIpHeader genUdpIpHeader(ThinMacIpUdpMetaDataForSend ethIpUdpMeta, LocalNetworkSettings localNetSettings, IpID ipId);
    // Calculate packet length
    UdpLength udpLen = ethIpUdpMeta.udpPayloadLen + fromInteger(valueOf(UDP_HDR_BYTE_WIDTH));
    IpTL ipLen = udpLen + fromInteger(valueOf(IP_HDR_BYTE_WIDTH));
    // generate ipHeader
    IpHeader ipHeader = IpHeader {
        ipVersion : fromInteger(valueOf(IP_VERSION_VAL)),
        ipIHL     : fromInteger(valueOf(IP_IHL_VAL)),
        ipDscp    : ethIpUdpMeta.ipDscp,
        ipEcn     : ethIpUdpMeta.ipEcn,
        ipTL      : ipLen,
        ipID      : ipId,
        ipFlag    : fromInteger(valueOf(IP_FLAGS_VAL)),
        ipOffset  : fromInteger(valueOf(IP_OFFSET_VAL)),
        ipTTL     : fromInteger(valueOf(IP_TTL_VAL)),
        ipProtocol: fromInteger(valueOf(IP_PROTOCOL_UDP)),
        ipChecksum: 0,
        srcIpAddr : localNetSettings.ipAddr,
        dstIpAddr : ethIpUdpMeta.dstIpAddr
    };
    // generate udpHeader
    UdpHeader udpHeader = UdpHeader {
        srcPort : ethIpUdpMeta.srcPort,
        dstPort : ethIpUdpMeta.dstPort,
        length  : udpLen,
        checksum: 0
    };
    // generate udpIpHeader
    UdpIpHeader udpIpHeader = UdpIpHeader {
        ipHeader: ipHeader,
        udpHeader: udpHeader
    };
    return udpIpHeader;
endfunction

typedef struct {
    MacIpUdpHeader                 macIpUdpHeader;
    RdmaEthernetFrameByteLen    totalEthernetFrameLen;
} IpHeaderChecksumCalcPipelineEntry deriving(Bits, FShow);

typedef struct {
    MacIpUdpHeader                 macIpUdpHeader;
} PacketGeneratorFirstBeatToSecondBeatPipelineEntry deriving(Bits, FShow);

typedef struct {
    MacIpUdpHeader                 macIpUdpHeader;
    RdmaSendPacketMeta          rdmaMeta;
} PacketGeneratorSecondBeatToThirdBeatPipelineEntry deriving(Bits, FShow);

(*synthesize*)
module mkEthernetPacketGenerator(EthernetPacketGenerator);
    FIFOF#(ThinMacIpUdpMetaDataForSend) macIpUdpMetaPipeInQ <- mkFIFOF;
    FIFOF#(RdmaSendPacketMeta) rdmaPacketMetaPipeInQ <- mkFIFOF;
    FIFOF#(DataStream) rdmaPayloadPipeInQ <- mkFIFOF;
    FIFOF#(EthernetNapBeatEntry) ethernetPacketPipeOutQ <- mkFIFOF;

    FIFOF#(IpHeader) ipHeaderForChecksumCalcQ <- mkFIFOF;

    // Pipeline FIFOs and Regs
    FIFOF#(IpHeaderChecksumCalcPipelineEntry) ipHeaderChecksumCalcPipelineQ <- mkSizedFIFOF(3);
    Reg#(PacketGeneratorFirstBeatToSecondBeatPipelineEntry) firstBeatToSecondBeatPipelineReg <- mkRegU;
    Reg#(PacketGeneratorSecondBeatToThirdBeatPipelineEntry) secondBeatToThirdBeatPipelineReg <- mkRegU;

    Reg#(Maybe#(LocalNetworkSettings)) networkSettingsReg <- mkReg(tagged Invalid);

    Reg#(RdmaEthernetFrameByteLen) ethernetFrameLeftByteCounterReg <- mkRegU;


    Reg#(EthernetPacketGeneratorState) statusReg <- mkReg(EthernetPacketGeneratorStateGenFirstBeat);

    let ipHdrCheckSumStreamPipeOut <- mkIpHdrCheckSumStream(toPipeOut(ipHeaderForChecksumCalcQ));

    IpID defaultIpId = 1;

    function EthernetNapBeatEntry genEthernetPacket(NocData data, EthernetNapMod mod, EthernetNapSendFlags flags, Bool isSop, Bool isEop);
        let beatData = EthernetNapSendOtherBeat{
            data: data,
            mod: mod,
            flags: flags,
            rsvd1: unpack(0)
        };

        let outBeat = EthernetNapBeatEntry{
            srcOrDstNodeId: ?,    // For Eth nap, the id is hardcoded, so don't care for now.
            data: pack(beatData),
            sop: isSop,
            eop: isEop
        };

        return outBeat;
    endfunction

    rule prepareIpHeader;
        let macIpUdpMeta = macIpUdpMetaPipeInQ.first;
        macIpUdpMetaPipeInQ.deq;

        // TODO: should we remove the Maybe wrapper in this type?
        LocalNetworkSettings localNetSettings = fromMaybe(?, networkSettingsReg);

        let udpIpHeader = genUdpIpHeader(macIpUdpMeta, localNetSettings, defaultIpId);
        let ethHeader = EthHeader{
            dstMacAddr: macIpUdpMeta.dstMacAddr,
            srcMacAddr: localNetSettings.macAddr,
            ethType: macIpUdpMeta.ethType
        };

        RdmaEthernetFrameByteLen ethFrameLen = truncate(macIpUdpMeta.udpPayloadLen) + fromInteger(valueOf(MAC_IP_UDP_TOTAL_HDR_BYTE_WIDTH));

        ipHeaderForChecksumCalcQ.enq(udpIpHeader.ipHeader);
        let outPipelineEntry = IpHeaderChecksumCalcPipelineEntry{
            macIpUdpHeader: MacIpUdpHeader{
                ethHeader: ethHeader,
                ipHeader: udpIpHeader.ipHeader,
                udpHeader: udpIpHeader.udpHeader
            },
            totalEthernetFrameLen: ethFrameLen
        };

        ipHeaderChecksumCalcPipelineQ.enq(outPipelineEntry);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator prepareIpHeader"),
        //     toBlue(", udpPayloadLen="), fshow(macIpUdpMeta.udpPayloadLen),
        //     toBlue(", outPipelineEntry="), fshow(outPipelineEntry)
        // );
    endrule

    rule genFirstBeat if (statusReg == EthernetPacketGeneratorStateGenFirstBeat);
        let checksum = ipHdrCheckSumStreamPipeOut.first;
        ipHdrCheckSumStreamPipeOut.deq;

        let pipelineEntry = ipHeaderChecksumCalcPipelineQ.first;
        ipHeaderChecksumCalcPipelineQ.deq;

        pipelineEntry.macIpUdpHeader.ipHeader.ipChecksum = checksum;
        ethernetFrameLeftByteCounterReg <= pipelineEntry.totalEthernetFrameLen - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));

        let beatData = EthernetNapSendFirstBeat{
            data: swapEndianByte(truncateLSB(pack(pipelineEntry.macIpUdpHeader))),
            rsvd1: unpack(0),
            timestamp: 0,
            rsvd2: unpack(0)
        };

        let outBeat = EthernetNapBeatEntry{
            srcOrDstNodeId: ?,    // For Eth nap, the id is hardcoded, so don't care for now.
            data: pack(beatData),
            sop: True,
            eop: False
        };

        ethernetPacketPipeOutQ.enq(outBeat);

        let outPipelineEntry = PacketGeneratorFirstBeatToSecondBeatPipelineEntry {
            macIpUdpHeader: pipelineEntry.macIpUdpHeader
        };
        firstBeatToSecondBeatPipelineReg <= outPipelineEntry;
        statusReg <= EthernetPacketGeneratorStateGenSecondBeat;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator genFirstBeat"),
        //     toBlue(", outBeat="), fshow(outBeat),
        //     toBlue(", ethernetFrameLeftByteCounterReg="), fshow(ethernetFrameLeftByteCounterReg),
        //     toBlue(", outPipelineEntry="), fshow(outPipelineEntry)
        // );

    endrule



    rule genSecondBeat if (statusReg == EthernetPacketGeneratorStateGenSecondBeat);
        let rdmaMeta = rdmaPacketMetaPipeInQ.first;
        rdmaPacketMetaPipeInQ.deq;

        ethernetFrameLeftByteCounterReg <= ethernetFrameLeftByteCounterReg - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let isEop = ethernetFrameLeftByteCounterReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));

        immAssert(
            !isEop,
            "The second beat should not be eop",
            $format("ethernetFrameLeftByteCounterReg=", fshow(ethernetFrameLeftByteCounterReg))
        );

        let mod = 0;
        let flags = unpack(0);
        flags.crcInsert = True;

        let macIpUdpHeader = firstBeatToSecondBeatPipelineReg.macIpUdpHeader;
        let macIpUdpBthEth = {pack(macIpUdpHeader), pack(rdmaMeta.header)};
        NocData data = truncateLSB(macIpUdpBthEth << valueOf(DATA_BUS_WIDTH));

        let outBeat = genEthernetPacket(swapEndianByte(data), mod, flags, False, isEop);

        ethernetPacketPipeOutQ.enq(outBeat);

        let outPipelineEntry = PacketGeneratorSecondBeatToThirdBeatPipelineEntry{
            macIpUdpHeader : firstBeatToSecondBeatPipelineReg.macIpUdpHeader,
            rdmaMeta    : rdmaMeta
        };
        secondBeatToThirdBeatPipelineReg <= outPipelineEntry;

        if (isEop) begin
            // this is defensive code, shoud not enter this branch. but if it does, goto handle first packet state.
            immFail(
                "The second beat must not be last beat.",
                $format("rdmaMeta=", fshow(rdmaMeta))
            );
            statusReg <= EthernetPacketGeneratorStateGenFirstBeat;
        end
        else begin
            statusReg <= EthernetPacketGeneratorStateGenThirdBeat;
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator genSecondBeat"),
        //     toBlue(", outBeat="), fshow(outBeat),
        //     toBlue(", ethernetFrameLeftByteCounterReg="), fshow(ethernetFrameLeftByteCounterReg),
        //     toBlue(", outPipelineEntry="), fshow(outPipelineEntry)
        // );
    endrule

    rule genThirdBeat if (statusReg == EthernetPacketGeneratorStateGenThirdBeat);

        let rdmaMeta = secondBeatToThirdBeatPipelineReg.rdmaMeta;

        ethernetFrameLeftByteCounterReg <= ethernetFrameLeftByteCounterReg - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let isEop = ethernetFrameLeftByteCounterReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let mod = truncate(ethernetFrameLeftByteCounterReg);

        let flags = unpack(0);
        flags.crcInsert = True;

        let macIpUdpHeader = secondBeatToThirdBeatPipelineReg.macIpUdpHeader;
        let macIpUdpBthEth = {pack(macIpUdpHeader), pack(rdmaMeta.header)};
        NocData data = truncateLSB(macIpUdpBthEth << valueOf(BYTE_NUM_OF_TWO_BEATS) * valueOf(BYTE_WIDTH));

        let outBeat = genEthernetPacket(swapEndianByte(data), mod, flags, False, isEop);

        ethernetPacketPipeOutQ.enq(outBeat);

        if (isEop) begin
            statusReg <= EthernetPacketGeneratorStateGenFirstBeat;
        end
        else begin
            statusReg <= EthernetPacketGeneratorStateGenMoreBeat;
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator genThirdBeat"),
        //     toBlue(", outBeat="), fshow(outBeat),
        //     toBlue(", ethernetFrameLeftByteCounterReg="), fshow(ethernetFrameLeftByteCounterReg),
        //     toBlue(", rdmaMeta="), fshow(rdmaMeta)
        // );
    endrule

    

    rule genMoreBeat if (statusReg == EthernetPacketGeneratorStateGenMoreBeat);

        ethernetFrameLeftByteCounterReg <= ethernetFrameLeftByteCounterReg - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let isEop = ethernetFrameLeftByteCounterReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let mod = truncate(ethernetFrameLeftByteCounterReg);

        let flags = unpack(0);
        flags.crcInsert = True;

        let payload = rdmaPayloadPipeInQ.first;
        rdmaPayloadPipeInQ.deq;
        NocData data = payload.data;

        let outBeat = genEthernetPacket(swapEndianByte(data), mod, flags, False, isEop);

        ethernetPacketPipeOutQ.enq(outBeat);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator genMoreBeat"),
        //     toBlue(", outBeat="), fshow(outBeat),
        //     toBlue(", ethernetFrameLeftByteCounterReg="), fshow(ethernetFrameLeftByteCounterReg)
        // );

        if (isEop) begin
            immAssert(
                payload.isLast,
                "payload should be last packet when isEop is true. mismatch between two calculate method",
                $format("Got payload = ", fshow(payload), "ethernetFrameLeftByteCounterReg=", fshow(ethernetFrameLeftByteCounterReg))
            );

            statusReg <= EthernetPacketGeneratorStateGenFirstBeat;
        end

        
    endrule

    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings);
        networkSettingsReg <= tagged Valid networkSettings;
    endmethod

    interface macIpUdpMetaPipeIn    = toPipeIn(macIpUdpMetaPipeInQ);
    interface rdmaPacketMetaPipeIn  = toPipeIn(rdmaPacketMetaPipeInQ);
    interface rdmaPayloadPipeIn     = toPipeIn(rdmaPayloadPipeInQ);
    interface ethernetPacketPipeOut = toPipeOut(ethernetPacketPipeOutQ);
endmodule



interface RingbufStorage#(type t_data, type t_idx);
    interface Get#(t_idx) allocSlotIdx;
    interface Put#(Tuple2#(t_idx, t_data)) saveData;
    interface Server#(Tuple2#(t_idx, Bool), t_data) readFragSrv;
endinterface


module mkRingbufStorage#(String name, Bool checkOverflow)(RingbufStorage#(t_data, t_idx)) provisos (
    Bits#(t_data, sz_data),
    Bits#(t_idx, sz_idx),
    Alias#(Bit#(sz_idxNoGuard), t_idxNoGuard),
    Add#(sz_idxNoGuard, 1, sz_idx),
    FShow#(t_idx),
    Bitwise#(t_idx),
    Eq#(t_idx),
    Arith#(t_idx)
);
    QueuedServer#(Tuple2#(t_idx, Bool), t_data) readFragSrvInst <- mkQueuedServer(sprintf("%s readFragSrvInst", name));


    RegFile#(t_idxNoGuard, t_data) buffer <- mkRegFileWCF(0, -1);
    Reg#(t_idx) idxGeneratorReg <- mkReg(unpack(0));
    Reg#(t_idx) lastConsumeIdxReg <- mkReg(unpack(0));

    FIFOF#(t_idx) allocedIdxQ <- mkFIFOF;


    rule handleAllocIdx;
        allocedIdxQ.enq(idxGeneratorReg);
        idxGeneratorReg <= idxGeneratorReg + 1;
    endrule

    rule handleReadReq;
        let {addr, isOnlyUpadteLastConsumeIndex} <- readFragSrvInst.getReq;
        lastConsumeIdxReg <= addr;
        if (!isOnlyUpadteLastConsumeIndex) begin
            let resp = buffer.sub(truncate(pack(addr)));
            readFragSrvInst.putResp(resp);
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" RingbufStorage new output entry"),
        //     toBlue(", name="), fshow(name),
        //     toBlue(", reqIdx="), fshow(addr),
        //     toBlue(", lastConsumeIdxReg="), fshow(lastConsumeIdxReg),
        //     toBlue(", isOnlyUpadteLastConsumeIndex="), fshow(isOnlyUpadteLastConsumeIndex)
        // );

    endrule

    // rule outputReadResp;
    //     let resp <- buffer.portB.response.get;
    //     readFragSrvInst.putResp(resp);
    // endrule

    interface Put saveData;
        method Action put(Tuple2#(t_idx, t_data) storeReq);
            let {idx, data} = storeReq;
            buffer.upd(truncate(pack(idx)), data);
    
            // if the substruct result's highest bit is one, the overflow
            if (checkOverflow) begin
                immAssert(
                    ((idx - lastConsumeIdxReg) >> valueOf(sz_idxNoGuard)) == 0,
                    "buf overfllow @ RingbufStorage",
                    $format(
                        "ringbufName=", fshow(name), "idx=", fshow(idx), " lastConsumeIdxReg=", fshow(lastConsumeIdxReg)
                    )
                );
            end
    
            // $display(
            //     "time=%0t: ", $time, toGreen("RingbufStorage new input entry"),
            //     toBlue(", name="), fshow(name),
            //     toBlue(", idx="), fshow(idx),
            //     toBlue(" lastConsumeIdxReg="), fshow(lastConsumeIdxReg) 
            // );
        endmethod
    endinterface

    interface allocSlotIdx = toGet(allocedIdxQ);
    interface readFragSrv = readFragSrvInst.srv;
endmodule