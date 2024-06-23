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
    method Action setMacAndIp(LocalNetworkSettings networkSettings);
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
        IpHeader  partialIpHeader   = unpack(truncateLSB(pack(ds.data) << valueOf(IP_HEADER_OFFSET_IN_FIRST_BEAT)));

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
            Bool broadcastMatch = netSettings.macAddr == -1;
            macAddrMatch = unicastMatch || broadcastMatch;
        end

        ethPacketMetaExtractPipelineEntry <= EthernetPacketMetaExtractPipelineEntry{
            mustNotBeRdmaPacket: mustNotBeRdmaPacket,
            macIpUdpMeta: macIpUdpMeta,
            isAddrMatch: macAddrMatch
        };

        partialDstIpAddrHigher16BitsReg <= truncateLSB(partialIpHeader.dstIpAddr);
        
        stateReg <= InputPacketClassifierStateHandleSecondBeat;
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
        end

        let isAddrMatch = ethPacketMetaExtractPipelineEntry.isAddrMatch && ipAddrMatch;

        UdpHeader udpHeader = unpack(truncateLSB(pack(ds.data) << valueOf(UDP_HEADER_OFFSET_IN_SECOND_BEAT)));

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
            isFirst: beat.sop,
            isLast: beat.eop
        };

        waitingForRouteQ.enq(ds);
        if (beat.eop) begin
            stateReg <= InputPacketClassifierStateHandleFirstBeat;
        end
    endrule

    rule dispatchStream;
        let ds = reverseStream(waitingForRouteQ.first);
        waitingForRouteQ.deq;
        let ethPktMeta = ethPacketMetaQ.first;

        // discard error packet.
        if (!ethPktMeta.isError && ethPktMeta.isAddrMatch) begin
            if (ethPktMeta.isRdmaPacket) begin
                rdmaRawPacketOutQ.enq(ds);
            end
            else begin
                otherRawPacketOutQ.enq(ds);
            end
        end

        if (ds.isLast) begin
            ethPacketMetaQ.deq;
        end
    endrule


    method Action setMacAndIp(LocalNetworkSettings networkSettings);
        networkSettingsReg <= tagged Valid networkSettings;
    endmethod

    interface ethRawPacketPipeIn        = toPipeIn(ethRawPacketInQ);
    interface rdmaRawPacketPipeOut      = toPipeOut(rdmaRawPacketOutQ);
    interface rdmaMacIpUdpMetaPipeOut   = toPipeOut(rdmaMacIpUdpMetaOutQ);
    interface otherRawPacketPipeOut     = toPipeOut(otherRawPacketOutQ);
endmodule



typedef TMul#(2, DATA_BUS_BYTE_WIDTH) BYTE_NUM_OF_TWO_BEATS;
typedef TSub#(BYTE_NUM_OF_TWO_BEATS, MAC_IP_UDP_TOTAL_HDR_BYTE_WIDTH) MAX_BYTE_NUM_FOR_BTH_AND_ETH_IN_SECOND_BEAT;
typedef MAX_BYTE_NUM_FOR_BTH_AND_ETH_IN_SECOND_BEAT BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT;
typedef TMul#(BYTE_WIDTH, BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT) BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT;

typedef TMul#(3, DATA_BUS_BYTE_WIDTH) BYTE_NUM_OF_THREE_BEATS;
typedef TSub#(BYTE_NUM_OF_THREE_BEATS, MAC_IP_UDP_TOTAL_HDR_BYTE_WIDTH) MAX_BYTE_NUM_FOR_ETH_IN_THIRD_BEAT;


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

    Integer bthEndPosInSecondBeat = valueOf(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT) - valueOf(SizeOf#(BTH));

    rule handleFirstBeat if (stateReg == RdmaHeaderExtractorStateHandleFirstBeat);
        // first beat is totally ETH and IP header, skip them
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;
        stateReg <= RdmaHeaderExtractorStateHandleSecondBeat;
    endrule

    rule handleSecondBeat if (stateReg == RdmaHeaderExtractorStateHandleSecondBeat);
        // second beat has some part of IP header, total UDP header, total BTH header, and maybe some RDMA extended header or payload
        // we only interested in the BTH and following part.

        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;

        BTH bth = unpack(ds.data[valueOf(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT) - 1 : bthEndPosInSecondBeat]);
        let hasPayload = rdmaOpCodeHasPayload(bth.opcode);
        let rdmaTotalHeaderLen = calcHeaderLenByTransTypeAndRdmaOpCode(bth.trans, bth.opcode);
        DataBusOneBasedByteIndex firstPayloadByteOffsetInFirstPayloadBeat = fromInteger(valueOf(BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT) - rdmaTotalHeaderLen);

        RdmaExtendHeaderFragmentInSecondBeat extendHeaderFragment = ds.data[bthEndPosInSecondBeat-1 : 0];
        RdmaExtendHeaderBuffer rdmaExtendHeaderBuf = zeroExtendLSB(extendHeaderFragment);

        if (rdmaTotalHeaderLen < valueOf(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT) && hasPayload) begin
            rdmaPayloadPipeOutQ.enq(ds);
        end

        let outPacketMeta = RdmaRecvPacketMeta{
            header: RdmaBthAndExtendHeader {
                bth: bth,
                rdmaExtendHeaderBuf: rdmaExtendHeaderBuf
            },
            hasPayload: hasPayload,
            firstPayloadByteOffsetInFirstPayloadBeat: firstPayloadByteOffsetInFirstPayloadBeat
        };

        partialRdmaMetaReg <= outPacketMeta;

        let rdmaHeaderIsComplete = rdmaTotalHeaderLen <= valueOf(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT);
        if (ds.isLast) begin 
            stateReg <= RdmaHeaderExtractorStateHandleFirstBeat;
        end
        else begin
            stateReg <= rdmaHeaderIsComplete ? RdmaHeaderExtractorStateHandleMoreBeat : RdmaHeaderExtractorStateHandleThirdBeat;
        end

        if (rdmaHeaderIsComplete) begin
            // if the whole RDMA header fit in the second beat, then output packet meta now.
            rdmaPacketMetaPipeOutQ.enq(outPacketMeta);
        end
        
    endrule

    rule handleThirdBeat if (stateReg == RdmaHeaderExtractorStateHandleThirdBeat);
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;

        let rdmaMeta = partialRdmaMetaReg;
        RdmaExtendHeaderFragmentInSecondBeat rdmaExtendHeaderSecondBeatFragment = truncateLSB(rdmaMeta.header.rdmaExtendHeaderBuf);
        rdmaMeta.header.rdmaExtendHeaderBuf = truncateLSB({rdmaExtendHeaderSecondBeatFragment, ds.data});

        // The third must contain the whole rdma header.
        rdmaPacketMetaPipeOutQ.enq(rdmaMeta);
    
        // For now, the largest RDMA extend header is 32 bytes, which means if the packet has payload, then some payload must exit in this beat
        if (rdmaMeta.hasPayload) begin
            rdmaPayloadPipeOutQ.enq(ds);
        end

        stateReg <= ds.isLast ? RdmaHeaderExtractorStateHandleFirstBeat : RdmaHeaderExtractorStateHandleMoreBeat;
    endrule

    rule handleMoreBeat if (stateReg == RdmaHeaderExtractorStateHandleMoreBeat);
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;
        rdmaPayloadPipeOutQ.enq(ds);
        if (ds.isLast) begin
            stateReg <= RdmaHeaderExtractorStateHandleFirstBeat;
        end
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

    method Action setMacAndIp(LocalNetworkSettings networkSettings);
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
    TotalHeader                 totalHeader;
    RdmaEthernetFrameByteLen    totalEthernetFrameLen;
} IpHeaderChecksumCalcPipelineEntry deriving(Bits, FShow);

typedef struct {
    TotalHeader                 totalHeader;
} PacketGeneratorFirstBeatToSecondBeatPipelineEntry deriving(Bits, FShow);

typedef struct {
    TotalHeader                 totalHeader;
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
        ipHeaderChecksumCalcPipelineQ.enq(IpHeaderChecksumCalcPipelineEntry{
            totalHeader: TotalHeader{
                ethHeader: ethHeader,
                ipHeader: udpIpHeader.ipHeader,
                udpHeader: udpIpHeader.udpHeader
            },
            totalEthernetFrameLen: ethFrameLen
        });

    endrule

    rule genFirstBeat if (statusReg == EthernetPacketGeneratorStateGenFirstBeat);
        let checksum = ipHdrCheckSumStreamPipeOut.first;
        ipHdrCheckSumStreamPipeOut.deq;

        let pipelineEntry = ipHeaderChecksumCalcPipelineQ.first;
        ipHeaderChecksumCalcPipelineQ.deq;

        pipelineEntry.totalHeader.ipHeader.ipChecksum = checksum;
        ethernetFrameLeftByteCounterReg <= pipelineEntry.totalEthernetFrameLen - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));

        let beatData = EthernetNapSendFirstBeat{
            data: swapEndianByte(truncateLSB(pack(pipelineEntry.totalHeader))),
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

        firstBeatToSecondBeatPipelineReg <= PacketGeneratorFirstBeatToSecondBeatPipelineEntry {
            totalHeader: pipelineEntry.totalHeader
        };
        statusReg <= EthernetPacketGeneratorStateGenSecondBeat;
    endrule



    rule genSecondBeat if (statusReg == EthernetPacketGeneratorStateGenSecondBeat);

        let rdmaMeta = rdmaPacketMetaPipeInQ.first;
        rdmaPacketMetaPipeInQ.deq;

        ethernetFrameLeftByteCounterReg <= ethernetFrameLeftByteCounterReg - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let isEop = ethernetFrameLeftByteCounterReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let mod = truncate(ethernetFrameLeftByteCounterReg);

        let flags = unpack(0);
        flags.crcInsert = True;

        let totalHeader = firstBeatToSecondBeatPipelineReg.totalHeader;
        let ethIpUdpBthEth = {pack(totalHeader), pack(rdmaMeta.header)};
        NocData data = truncateLSB(ethIpUdpBthEth << valueOf(DATA_BUS_WIDTH));

        let wholeBthAndEthContainedInThisBeat = rdmaMeta.bthAndEthTotalLength <= fromInteger(valueOf(MAX_BYTE_NUM_FOR_BTH_AND_ETH_IN_SECOND_BEAT));
        let hasExtraSpaceForPayloadInThisBeat = rdmaMeta.bthAndEthTotalLength < fromInteger(valueOf(MAX_BYTE_NUM_FOR_BTH_AND_ETH_IN_SECOND_BEAT));
        if (hasExtraSpaceForPayloadInThisBeat && rdmaMeta.hasPayload) begin
            let payload = rdmaPayloadPipeInQ.first;
            rdmaPayloadPipeInQ.deq;

            // To use the bit OR operation to merge two part of data, the lower part of data and the higher part of payload in this beat should be 0
            RdmaBthAndEthTotalLength tmpMinusResult = fromInteger(valueOf(BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT)) - rdmaMeta.bthAndEthTotalLength;
            DataBusOneBasedByteIndex firstPayloadByteOneBasedIndexInThisBeat = truncate(tmpMinusResult);


            immAssert(
                (data << fromInteger(fromInteger(valueOf(DATA_BUS_BYTE_WIDTH))) - firstPayloadByteOneBasedIndexInThisBeat) == 0,
                "The lower part of data should be zero",
                $format("Got data = ", fshow(data), "firstPayloadByteOneBasedIndexInThisBeat = ", fshow(firstPayloadByteOneBasedIndexInThisBeat))
            );

            immAssert(
                (payload.data >> (firstPayloadByteOneBasedIndexInThisBeat-1)) == 0,
                "The higher part of payload should be zero",
                $format("Got payload = ", fshow(payload), "firstPayloadByteOneBasedIndexInThisBeat = ", fshow(firstPayloadByteOneBasedIndexInThisBeat))
            );

            immAssert(
                payload.byteNum <= truncate(fromInteger(valueOf(MAX_BYTE_NUM_FOR_BTH_AND_ETH_IN_SECOND_BEAT)) - rdmaMeta.bthAndEthTotalLength),
                "payload has too many valid byte in this beat",
                $format("Got payload = ", fshow(payload), "firstPayloadByteOneBasedIndexInThisBeat = ", fshow(firstPayloadByteOneBasedIndexInThisBeat))
            );


            data = data | payload.data;
        end

        let outBeat = genEthernetPacket(swapEndianByte(data), mod, flags, False, isEop);

        ethernetPacketPipeOutQ.enq(outBeat);

        secondBeatToThirdBeatPipelineReg <= PacketGeneratorSecondBeatToThirdBeatPipelineEntry{
            totalHeader : firstBeatToSecondBeatPipelineReg.totalHeader,
            rdmaMeta    : rdmaMeta
        };

        if (isEop) begin
            statusReg <= EthernetPacketGeneratorStateGenFirstBeat;
        end
        else if (wholeBthAndEthContainedInThisBeat) begin
            statusReg <= EthernetPacketGeneratorStateGenMoreBeat;
        end
        else begin
            statusReg <= EthernetPacketGeneratorStateGenThirdBeat;
        end
    endrule



    rule genThirdBeat if (statusReg == EthernetPacketGeneratorStateGenThirdBeat);

        let rdmaMeta = secondBeatToThirdBeatPipelineReg.rdmaMeta;

        ethernetFrameLeftByteCounterReg <= ethernetFrameLeftByteCounterReg - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let isEop = ethernetFrameLeftByteCounterReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let mod = truncate(ethernetFrameLeftByteCounterReg);

        let flags = unpack(0);
        flags.crcInsert = True;

        let totalHeader = secondBeatToThirdBeatPipelineReg.totalHeader;
        let ethIpUdpBthEth = {pack(totalHeader), pack(rdmaMeta.header)};
        NocData data = truncateLSB(ethIpUdpBthEth << valueOf(BYTE_NUM_OF_TWO_BEATS));

        let hasExtraSpaceForPayloadInThisBeat = rdmaMeta.bthAndEthTotalLength < fromInteger(valueOf(MAX_BYTE_NUM_FOR_BTH_AND_ETH_IN_SECOND_BEAT) + valueOf(DATA_BUS_BYTE_WIDTH));
        if (hasExtraSpaceForPayloadInThisBeat && rdmaMeta.hasPayload) begin
            let payload = rdmaPayloadPipeInQ.first;
            rdmaPayloadPipeInQ.deq;

            // To use the bit OR operation to merge two part of data, the lower part of data and the higher part of payload in this beat should be 0
            RdmaBthAndEthTotalLength tmpMinusResult = fromInteger(valueOf(BTH_FIRST_BYTE_ONE_BASED_INDEX_IN_SECOND_BEAT)) - rdmaMeta.bthAndEthTotalLength;
            DataBusOneBasedByteIndex firstPayloadByteOneBasedIndexInThisBeat = truncate(tmpMinusResult);

            immAssert(
                (data << fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - firstPayloadByteOneBasedIndexInThisBeat) == 0,
                "The lower part of data should be zero",
                $format("Got data = ", fshow(data), "firstPayloadByteOneBasedIndexInThisBeat = ", fshow(firstPayloadByteOneBasedIndexInThisBeat))
            );

            immAssert(
                (payload.data >> (firstPayloadByteOneBasedIndexInThisBeat-1)) == 0,
                "The higher part of payload should be zero",
                $format("Got payload = ", fshow(payload), "firstPayloadByteOneBasedIndexInThisBeat = ", fshow(firstPayloadByteOneBasedIndexInThisBeat))
            );

            immAssert(
                payload.byteNum <= truncate(fromInteger(valueOf(MAX_BYTE_NUM_FOR_BTH_AND_ETH_IN_SECOND_BEAT)) - rdmaMeta.bthAndEthTotalLength),
                "payload has too many valid byte in this beat",
                $format("Got payload = ", fshow(payload), "firstPayloadByteOneBasedIndexInThisBeat = ", fshow(firstPayloadByteOneBasedIndexInThisBeat))
            );


            data = data | payload.data;
        end

        let outBeat = genEthernetPacket(swapEndianByte(data), mod, flags, False, isEop);

        ethernetPacketPipeOutQ.enq(outBeat);

        if (isEop) begin
            statusReg <= EthernetPacketGeneratorStateGenFirstBeat;
        end
        else begin
            statusReg <= EthernetPacketGeneratorStateGenMoreBeat;
        end
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

        if (isEop) begin
            immAssert(
                payload.isLast,
                "payload should be last packet when isEop is true. mismatch between two calculate method",
                $format("Got payload = ", fshow(payload), "ethernetFrameLeftByteCounterReg=", fshow(ethernetFrameLeftByteCounterReg))
            );

            statusReg <= EthernetPacketGeneratorStateGenFirstBeat;
        end
    endrule

    method Action setMacAndIp(LocalNetworkSettings networkSettings);
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

        $display(
            "time=%0t:", $time, " RingbufStorage new output entry",
            ", name=", fshow(name),
            ", reqIdx=", fshow(addr),
            ", lastConsumeIdxReg=", fshow(lastConsumeIdxReg),
            ", isOnlyUpadteLastConsumeIndex=", fshow(isOnlyUpadteLastConsumeIndex)
        );

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
    
            $display(
                "time=%0t:", $time, "RingbufStorage new input entry",
                ", name=", fshow(name),
                ", idx=", fshow(idx),
                " lastConsumeIdxReg=", fshow(lastConsumeIdxReg) 
            );
        endmethod
    endinterface

    interface allocSlotIdx = toGet(allocedIdxQ);
    interface readFragSrv = readFragSrvInst.srv;
endmodule