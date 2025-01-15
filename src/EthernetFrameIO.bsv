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
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;

import CsrRootConnector :: *;
import CsrAddress :: *;
import CsrFramework :: *;

import ConnectableF :: *;

import IoChannels :: *;

interface InputPacketClassifier;
    interface BlueRdmaCsrUpStreamPort                   csrUpStreamPort;
    interface PipeIn#(IoChannelEthDataStream)           ethRawPacketPipeIn;
    interface PipeOut#(DataStream)                      rdmaRawPacketPipeOut;
    interface PipeOut#(ThinMacIpUdpMetaDataForRecv)     rdmaMacIpUdpMetaPipeOut;
    interface PipeOut#(DataStream)                      otherRawPacketPipeOut;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings);
endinterface


typedef 14 IP_HEADER_OFFSET_IN_FIRST_BEAT;
typedef 2 UDP_HEADER_OFFSET_IN_SECOND_BEAT;
typedef 16 MAC_ADDR_PARTIAL_COMPARE_BIT_WIDTH;

typedef 16 IP_ADDR_COMPARE_PARTIAL_POINT;



typedef enum {
    InputPacketClassifierStateHandleFirstBeat = 0,
    InputPacketClassifierStateHandleSecondBeat = 1,
    InputPacketClassifierStateHandleMoreBeat = 2
} InputPacketClassifierState deriving(Bits, FShow, Eq);

typedef struct {
    Bool mustNotBeRdmaPacket;
    ThinMacIpUdpMetaDataForRecv macIpUdpMeta;
    Bool macUnicastMatch;
    Bool macAddrBroadcastMatch;
    EthHeader ethHeader;
} EthernetPacketMetaExtractPipelineEntry deriving(Bits, FShow, Eq);

typedef struct {
    Bool isRdmaPacket;
    Bool isError;
    Bool isAddrMatch;
} EthernetPacketMeta deriving(Bits, FShow, Eq);

(*synthesize*)
module mkInputPacketClassifier(InputPacketClassifier);
    Reg#(InputPacketClassifierState) stateReg <- mkReg(InputPacketClassifierStateHandleFirstBeat);

    FIFOF#(IoChannelEthDataStream) ethRawPacketInQ <- mkFIFOF;
    FIFOF#(DataStream) rdmaRawPacketOutQ <- mkFIFOF;
    FIFOF#(ThinMacIpUdpMetaDataForRecv) rdmaMacIpUdpMetaOutQ <- mkFIFOF;
    FIFOF#(DataStream) otherRawPacketOutQ <- mkFIFOF;

    FIFOF#(DataStream) waitingForRouteQ <- mkSizedFIFOF(valueOf(NUMERIC_TYPE_FOUR));
    FIFOF#(EthernetPacketMeta) ethPacketMetaQ <- mkFIFOF;

    Reg#(EthernetPacketMetaExtractPipelineEntry) ethPacketMetaExtractPipelineEntryReg <- mkRegU;

    Reg#(Bool) networkSettingsIsSetReg <- mkReg(False);
    Reg#(LocalNetworkSettings) networkSettingsReg <- mkRegU;
    Reg#(Bool) canAcceptRawInputPacketReg <- mkReg(False);

    // the dst IP filed begins at #30 byte of first beat, so the first beat only has the higher 16 bits
    Reg#(Bool) partialDstIpAddrHigher16BitsMatchReg <- mkRegU;

    FIFOF#(Tuple2#(DataStream, Bool)) ethRawPacketForHandleQ <- mkFIFOF;


    // Metrics Regs
    Reg#(Dword) metricsDiscardPacketCntReg      <- mkReg(0);
    Reg#(Dword) metricsSimpleNicPacketCntReg    <- mkReg(0);
    Reg#(Dword) metricsRdmaPacketCntReg         <- mkReg(0);


    function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
        actionvalue
            let regIdx = req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM);
            let leafMask = fromInteger(valueOf(CSR_ADDR_LEAF_MASK_FOR_METRICS_ETHERNET_FRAME_IO));

            if (req.isWrite) begin
                return tagged CsrNodeResultNotMatched;
            end
            else begin
                case (regIdx & leafMask)
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_ETHERNET_FRAME_IO_DISCARD_PACKET_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsDiscardPacketCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_ETHERNET_FRAME_IO_SIMPLE_NIC_PACKET_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsSimpleNicPacketCntReg};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_METRICS_ETHERNET_FRAME_IO_RDMA_PACKET_CNT)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: metricsRdmaPacketCntReg};
                    end
                    default: begin
                        return tagged CsrNodeResultNotMatched;
                    end
                endcase
            end
        endactionvalue
    endfunction
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_ONE), "mkInputPacketClassifier");

    rule discardPacketWhenNetworkSettingsNotReady;
        let ds = ethRawPacketInQ.first;
        ethRawPacketInQ.deq;

        EthHeader ethHeader         = unpack(truncateLSB(swapEndianByte(pack(ds.data))));
        Bool macUnicastMatch = ethHeader.dstMacAddr == networkSettingsReg.macAddr;

        if (networkSettingsIsSetReg && ds.isFirst) begin
            canAcceptRawInputPacketReg <= True;

            ethRawPacketForHandleQ.enq(tuple2(ds, macUnicastMatch));
            waitingForRouteQ.enq(ds);
        end
        else if (canAcceptRawInputPacketReg) begin
            ethRawPacketForHandleQ.enq(tuple2(ds, macUnicastMatch));
            waitingForRouteQ.enq(ds);
        end
        else begin
            $display(
                "time=%0t:", $time, toRed(" mkInputPacketClassifier discardPacketWhenNetworkSettingsNotReady >>>>> DISCARD PACKET <<<<< since network settings not set"),
                toBlue(", ds="), fshow(ds)
            );
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkInputPacketClassifier discardPacketWhenNetworkSettingsNotReady"),
        //     toBlue(", ethHeader="), fshow(ethHeader),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    rule handleFirstBeatStage if (stateReg == InputPacketClassifierStateHandleFirstBeat);
        let {ds, macUnicastMatch} = ethRawPacketForHandleQ.first;
        ethRawPacketForHandleQ.deq;
        ds.data = swapEndianByte(ds.data);

        // Ethernet packet is atleast 64 byte, smaller packet should already be filtered by ETH IP.
        immAssert(
            ds.isFirst && !ds.isLast,
            "mkInputPacketClassifier first beat error",
            $format("isFirst should be True and isLast should be False in handleFirstBeatStage, ds=", fshow(ds))
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

        Bool macAddrBroadcastMatch = ethHeader.dstMacAddr == -1;

        let outPipelineEntry =  EthernetPacketMetaExtractPipelineEntry{
            mustNotBeRdmaPacket: mustNotBeRdmaPacket,
            macIpUdpMeta: macIpUdpMeta,
            macUnicastMatch: macUnicastMatch,
            macAddrBroadcastMatch:macAddrBroadcastMatch,
            ethHeader: ethHeader
        };
        ethPacketMetaExtractPipelineEntryReg <= outPipelineEntry;

        Bit#(IP_ADDR_COMPARE_PARTIAL_POINT) partialDstIpAddrHigher16Bits = truncateLSB(partialIpHeader.dstIpAddr);
        let partialDstIpAddrHigher16BitsMatch = partialDstIpAddrHigher16Bits == truncateLSB(networkSettingsReg.ipAddr);
        partialDstIpAddrHigher16BitsMatchReg <= partialDstIpAddrHigher16BitsMatch;
        
        if (!partialDstIpAddrHigher16BitsMatch) begin
            $display(
                "time=%0t:", $time, toRed(" mkInputPacketClassifier IP address check failed"),
                toBlue(", networkSettingsReg="), fshow(networkSettingsReg),
                toBlue(", partialDstIpAddrHigher16BitsMatch="), fshow(partialDstIpAddrHigher16BitsMatch)
            );
        end


        if (ds.isLast) begin
            // defensive coding. each if packet corrupted, oly have one beat, then stay in current state, and discard packet.
            ethPacketMetaQ.enq(EthernetPacketMeta{
                isRdmaPacket: False,
                isError: True,
                isAddrMatch: False
            });
        end
        else begin
            stateReg <= InputPacketClassifierStateHandleSecondBeat;
        end

        
        // $display(
        //     "time=%0t:", $time, toGreen(" mkInputPacketClassifier handleFirstBeatStage"),
        //     toBlue(", partialIpHeader="), fshow(partialIpHeader),
        //     toBlue(", ds="), fshow(ds),
        //     toBlue(", outPipelineEntry="), fshow(outPipelineEntry)
        // );
    endrule

    rule handleSecondBeatStage if (stateReg == InputPacketClassifierStateHandleSecondBeat);
        let {ds, _dontCareMacUnicastMatch} = ethRawPacketForHandleQ.first;
        ethRawPacketForHandleQ.deq;
        ds.data = swapEndianByte(ds.data);

        immAssert(
            !ds.isFirst,
            "mkInputPacketClassifier second beat error",
            $format("isFirst should be False handleSecondBeatStage, ds=", fshow(ds))
        );

        Bit#(IP_ADDR_COMPARE_PARTIAL_POINT) partialDstIpAddrLower16Bits = truncateLSB({pack(ds.data)});

        Bool ipUnicastMatch = partialDstIpAddrHigher16BitsMatchReg && (truncate(networkSettingsReg.ipAddr) == partialDstIpAddrLower16Bits);
        Bool ipAddrMatch = ipUnicastMatch;

        if (!ipAddrMatch) begin
            $display(
                "time=%0t:", $time, toRed(" mkInputPacketClassifier IP address check failed"),
                toBlue(", networkSettingsReg="), fshow(networkSettingsReg),
                toBlue(", partialDstIpAddrLower16Bits="), fshow(partialDstIpAddrLower16Bits)
            );
        end

        let macUnicastMatch         = ethPacketMetaExtractPipelineEntryReg.macUnicastMatch;
        let macAddrBroadcastMatch   = ethPacketMetaExtractPipelineEntryReg.macAddrBroadcastMatch;
        let macAddrMatch = macUnicastMatch || macAddrBroadcastMatch;

        if (!macAddrMatch) begin
            $display(
                "time=%0t:", $time, toRed(" mkInputPacketClassifier mac address check failed"),
                toBlue(", networkSettingsReg="), fshow(networkSettingsReg),
                toBlue(", ethHeader="), fshow(ethPacketMetaExtractPipelineEntryReg.ethHeader)
            );
        end

        let isAddrMatch = macAddrMatch && ipAddrMatch;

        UdpHeader udpHeader = unpack(truncateLSB(pack(ds.data) << valueOf(UDP_HEADER_OFFSET_IN_SECOND_BEAT) * valueOf(BYTE_WIDTH)));

        Bool mustNotBeRdmaPacket = False;
        if (udpHeader.dstPort != fromInteger(valueOf(UDP_PORT_RDMA))) begin
            mustNotBeRdmaPacket = True;
        end
        mustNotBeRdmaPacket = mustNotBeRdmaPacket || ethPacketMetaExtractPipelineEntryReg.mustNotBeRdmaPacket;

        // error packet should already be filtered by Eth Mac
        let isError = False;

        // This is the final check condition. so if it is not "mustn't be RDMA", then it is RDMA
        Bool isRDMA = !mustNotBeRdmaPacket;
        ethPacketMetaQ.enq(EthernetPacketMeta{
            isRdmaPacket: isRDMA,
            isError: isError,
            isAddrMatch: isAddrMatch
        });

        let macIpUdpMeta = ethPacketMetaExtractPipelineEntryReg.macIpUdpMeta;
        macIpUdpMeta.srcPort = udpHeader.srcPort;

        if (isAddrMatch && isRDMA && !isError) begin
            rdmaMacIpUdpMetaOutQ.enq(macIpUdpMeta);
        end
        
        stateReg <= ds.isLast ? InputPacketClassifierStateHandleFirstBeat : InputPacketClassifierStateHandleMoreBeat;
        
        // $display(
        //     "time=%0t:", $time, toGreen(" mkInputPacketClassifier handleSecondBeatStage"),
        //     toBlue(", ds="), fshow(ds),
        //     toBlue(", macIpUdpMeta="), fshow(macIpUdpMeta)
        // );
    endrule

    rule handleMoreBeatStage if (stateReg == InputPacketClassifierStateHandleMoreBeat);
        let {ds, macUnicastMatch} = ethRawPacketForHandleQ.first;
        ethRawPacketForHandleQ.deq;

        immAssert(
            !ds.isFirst,
            "mkInputPacketClassifier second beat error",
            $format("isFirst should be False handleMoreBeatStage, ds=", fshow(ds))
        );


        
        if (ds.isLast) begin
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
                metricsRdmaPacketCntReg <= metricsRdmaPacketCntReg + 1;
            end
            else begin
                otherRawPacketOutQ.enq(ds);
                metricsSimpleNicPacketCntReg <= metricsSimpleNicPacketCntReg + 1;
            end
        end
        else begin
            $display(
                "time=%0t:", $time, toRed(" mkInputPacketClassifier dispatchStream >>>>> DISCARD PACKET <<<<<"),
                toBlue(", ethPktMeta.isError="), fshow(ethPktMeta.isError),
                toBlue(", ethPktMeta.isAddrMatch="), fshow(ethPktMeta.isAddrMatch),
                toBlue(", ds="), fshow(ds)
            );
            metricsDiscardPacketCntReg <= metricsDiscardPacketCntReg + 1;
        end

        if (ds.isLast) begin
            ethPacketMetaQ.deq;
        end
    endrule


    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings);
        networkSettingsReg <= networkSettings;
        networkSettingsIsSetReg <= True;
    endmethod

    interface csrUpStreamPort           = csrNode.upStreamPort;
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

interface RdmaMetaAndPayloadExtractor;
    interface PipeIn#(DataStream) ethPipeIn;
    interface PipeOut#(RdmaRecvPacketMeta) rdmaPacketMetaPipeOut;
    interface PipeOut#(RdmaRecvPacketTailMeta) rdmaPacketTailMetaPipeOut;
    interface PipeOut#(DataStream) rdmaPayloadPipeOut;
endinterface

typedef enum {
    RdmaMetaAndPayloadExtractorStateHandleFirstBeat = 0,
    RdmaMetaAndPayloadExtractorStateHandleSecondBeat = 1,
    RdmaMetaAndPayloadExtractorStateHandleThirdBeat = 2,
    RdmaMetaAndPayloadExtractorStateHandleMoreBeat = 3
} RdmaMetaAndPayloadExtractorState deriving(Bits, FShow, Eq);

(*synthesize*)
module mkRdmaMetaAndPayloadExtractor(RdmaMetaAndPayloadExtractor);

    Reg#(RdmaMetaAndPayloadExtractorState) stateReg <- mkReg(RdmaMetaAndPayloadExtractorStateHandleFirstBeat);

    FIFOF#(DataStream) ethPipeInQ                   <- mkFIFOF;
    FIFOF#(RdmaRecvPacketMeta) rdmaPacketMetaPipeOutQ   <- mkFIFOF;
    FIFOF#(RdmaRecvPacketTailMeta) rdmaPacketTailMetaPipeOutQ   <- mkFIFOF;
    FIFOF#(DataStream) rdmaPayloadPipeOutQ          <- mkFIFOF;

    Reg#(RdmaRecvPacketMeta) partialRdmaMetaReg <- mkRegU;
    Reg#(Bool) payloadStreamOutputIsFirstReg <- mkReg(True);

    Reg#(PktFragNum) beatCntReg <- mkReg(1);
    Reg#(Bool) ecnFlagReg <- mkRegU;
    Integer bthEndBitOneBasedPosInSecondBeat = valueOf(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT) - valueOf(SizeOf#(BTH));

    rule handleFirstBeat if (stateReg == RdmaMetaAndPayloadExtractorStateHandleFirstBeat);
        // first beat is totally ETH and IP header, skip them
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;

        IpHeader  partialIpHeader   = unpack(truncateLSB(pack(ds.data) << valueOf(IP_HEADER_OFFSET_IN_FIRST_BEAT) * valueOf(BYTE_WIDTH)));
        ecnFlagReg <= (pack(partialIpHeader.ipEcn) == pack(IpHeaderEcnFlagMarked));

        if (ds.isLast) begin
            // this is defensive code, shoud not enter this branch. but if it does, stay in handle first packet state.
            immFail(
                "The first beat must not be last beat.",
                $format("ds=", fshow(ds))
            );
        end
        else begin
            stateReg <= RdmaMetaAndPayloadExtractorStateHandleSecondBeat;
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkRdmaMetaAndPayloadExtractor handleFirstBeat"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    rule handleSecondBeat if (stateReg == RdmaMetaAndPayloadExtractorStateHandleSecondBeat);
        // second beat has some part of IP header, total UDP header, total BTH header, and maybe some RDMA extended header or payload
        // we only interested in the BTH and following part.

        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;
        ds.data = swapEndianByte(ds.data);

        BTH bth = unpack(ds.data[valueOf(BTH_FIRST_BIT_ONE_BASED_INDEX_IN_SECOND_BEAT) - 1 : bthEndBitOneBasedPosInSecondBeat]);
        let hasPayload = rdmaOpCodeHasPayload(bth.opcode);

        RdmaExtendHeaderFragmentInSecondBeat extendHeaderFragment = ds.data[bthEndBitOneBasedPosInSecondBeat-1 : 0];
        RdmaExtendHeaderBuffer rdmaExtendHeaderBuf = zeroExtendLSB(extendHeaderFragment);


        let outPacketMeta = RdmaRecvPacketMeta{
            header: RdmaBthAndExtendHeader {
                bth: bth,
                rdmaExtendHeaderBuf: rdmaExtendHeaderBuf
            },
            hasPayload: hasPayload,
            isEcnMarked: ecnFlagReg
        };

        partialRdmaMetaReg <= outPacketMeta;

        if (ds.isLast) begin
            // this is defensive code, shoud not enter this branch. but if it does, goto handle first packet state.
            immFail(
                "The second beat must not be last beat.",
                $format("ds=", fshow(ds))
            );
            stateReg <= RdmaMetaAndPayloadExtractorStateHandleFirstBeat;
        end
        else begin
            stateReg <= RdmaMetaAndPayloadExtractorStateHandleThirdBeat;
        end

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRdmaMetaAndPayloadExtractor handleSecondBeat"),
        //     toBlue(", ds="), fshow(ds),
        //     toBlue(", rdmaTotalHeaderLen=0x%x"), rdmaTotalHeaderLen,
        //     toBlue(", rdmaHeaderIsComplete="), fshow(rdmaHeaderIsComplete),
        //     toBlue(", outPacketMeta="), fshow(outPacketMeta),
        //     toBlue(", payloadDs="), outputPayloadInThisBeat ? fshow(payloadDs) : $format("No Payload In This beat")
        // );
    endrule

    rule handleThirdBeat if (stateReg == RdmaMetaAndPayloadExtractorStateHandleThirdBeat);
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;
        ds.data = swapEndianByte(ds.data);

        let rdmaMeta = partialRdmaMetaReg;
        RdmaExtendHeaderFragmentInSecondBeat rdmaExtendHeaderSecondBeatFragment = truncateLSB(rdmaMeta.header.rdmaExtendHeaderBuf);
        rdmaMeta.header.rdmaExtendHeaderBuf = truncateLSB({rdmaExtendHeaderSecondBeatFragment, ds.data});

        rdmaPacketMetaPipeOutQ.enq(rdmaMeta);
    

        stateReg <= ds.isLast ? RdmaMetaAndPayloadExtractorStateHandleFirstBeat : RdmaMetaAndPayloadExtractorStateHandleMoreBeat;

        // $display(
        //     "time=%0t:", $time, toGreen(" mkRdmaMetaAndPayloadExtractor handleThirdBeat"),
        //     toBlue(", ds="), fshow(ds),
        //     toBlue(", payloadDs="), rdmaMeta.hasPayload ? fshow(payloadDs) : $format("No Payload"),
        //     toBlue(", rdmaMeta="), fshow(rdmaMeta)
        // );
    endrule

    rule handleMoreBeat if (stateReg == RdmaMetaAndPayloadExtractorStateHandleMoreBeat);
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;
        ds.isFirst = payloadStreamOutputIsFirstReg;
        rdmaPayloadPipeOutQ.enq(ds);

        if (ds.isLast) begin
            stateReg <= RdmaMetaAndPayloadExtractorStateHandleFirstBeat;
            payloadStreamOutputIsFirstReg <= True;
            beatCntReg <= 1;
            rdmaPacketTailMetaPipeOutQ.enq(RdmaRecvPacketTailMeta{
                beatCnt: beatCntReg
            });
        end
        else begin
            payloadStreamOutputIsFirstReg <= False;
            beatCntReg <= beatCntReg + 1;
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkRdmaMetaAndPayloadExtractor handleMoreBeat"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    interface ethPipeIn                     = toPipeIn(ethPipeInQ);
    interface rdmaPacketMetaPipeOut         = toPipeOut(rdmaPacketMetaPipeOutQ);
    interface rdmaPacketTailMetaPipeOut     = toPipeOut(rdmaPacketTailMetaPipeOutQ);
    interface rdmaPayloadPipeOut            = toPipeOut(rdmaPayloadPipeOutQ);
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
    interface PipeOut#(IoChannelEthDataStream) ethernetPacketPipeOut;

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
    FIFOF#(IoChannelEthDataStream) ethernetPacketPipeOutQ <- mkFIFOF;

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


    function IoChannelEthDataStream genEthernetPacket(NocData data, ByteIndexInBeat startByteIdx, EthernetNapMod mod, Bool isFirst, Bool isLast);
        
        let byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        if (isLast) begin
            byteNum = mod == 0 ? fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) : zeroExtend(mod);
        end

        // Note: the ethernet packet is a pure stream, so startByteIdx must always be zero.
        // when handling the first beat of payload, since the input payload from PCIe is aligned to DWord, the input beat's
        // startByteIdx may not be 0, but we can force it to 0. so, at the same time, we need to add the bytes skiped by
        // startByteIdx to byteNum (only the first beat of payload may have startByteIdx != 0)

        let outBeat = IoChannelEthDataStream{
            data: data,
            byteNum: byteNum + zeroExtend(startByteIdx),
            startByteIdx: 0,
            isFirst: isFirst,
            isLast: isLast
        };

        return outBeat;
    endfunction

    rule prepareIpHeader;
        let macIpUdpMeta = macIpUdpMetaPipeInQ.first;
        macIpUdpMetaPipeInQ.deq;

        // TODO: should we remove the Maybe wrapper in this type?
        LocalNetworkSettings localNetSettings = fromMaybe(?, networkSettingsReg);

        let udpIpHeader = genUdpIpHeader(macIpUdpMeta, localNetSettings, defaultIpId);
        let ethHeader = EthHeader {
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

        $display(
            "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator prepareIpHeader"),
            toBlue(", udpPayloadLen="), fshow(macIpUdpMeta.udpPayloadLen),
            toBlue(", outPipelineEntry="), fshow(outPipelineEntry)
        );
    endrule

    rule genFirstBeat if (statusReg == EthernetPacketGeneratorStateGenFirstBeat);
        let checksum = ipHdrCheckSumStreamPipeOut.first;
        ipHdrCheckSumStreamPipeOut.deq;

        let pipelineEntry = ipHeaderChecksumCalcPipelineQ.first;
        ipHeaderChecksumCalcPipelineQ.deq;

        pipelineEntry.macIpUdpHeader.ipHeader.ipChecksum = checksum;
        ethernetFrameLeftByteCounterReg <= pipelineEntry.totalEthernetFrameLen - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));

        IoChannelEthDataStream outBeat = IoChannelEthDataStream{
            data: swapEndianByte(truncateLSB(pack(pipelineEntry.macIpUdpHeader))),
            byteNum: fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)),
            startByteIdx: 0,
            isFirst: True,
            isLast: False
        };

        ethernetPacketPipeOutQ.enq(outBeat);

        let outPipelineEntry = PacketGeneratorFirstBeatToSecondBeatPipelineEntry {
            macIpUdpHeader: pipelineEntry.macIpUdpHeader
        };
        firstBeatToSecondBeatPipelineReg <= outPipelineEntry;
        statusReg <= EthernetPacketGeneratorStateGenSecondBeat;

        $display(
            "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator genFirstBeat"),
            toBlue(", outBeat="), fshow(outBeat),
            toBlue(", ethernetFrameLeftByteCounterReg="), fshow(ethernetFrameLeftByteCounterReg),
            toBlue(", outPipelineEntry="), fshow(outPipelineEntry)
        );

    endrule



    rule genSecondBeat if (statusReg == EthernetPacketGeneratorStateGenSecondBeat);
        let rdmaMeta = rdmaPacketMetaPipeInQ.first;
        rdmaPacketMetaPipeInQ.deq;

        ethernetFrameLeftByteCounterReg <= ethernetFrameLeftByteCounterReg - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let isLast = ethernetFrameLeftByteCounterReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));

        immAssert(
            !isLast,
            "The second beat should not be isLast",
            $format("ethernetFrameLeftByteCounterReg=", fshow(ethernetFrameLeftByteCounterReg))
        );

        let mod = 0;


        let macIpUdpHeader = firstBeatToSecondBeatPipelineReg.macIpUdpHeader;
        let macIpUdpBthEth = {pack(macIpUdpHeader), pack(rdmaMeta.header)};
        NocData data = truncateLSB(macIpUdpBthEth << valueOf(DATA_BUS_WIDTH));

        let outBeat = genEthernetPacket(swapEndianByte(data), 0, mod, False, isLast);

        ethernetPacketPipeOutQ.enq(outBeat);

        let outPipelineEntry = PacketGeneratorSecondBeatToThirdBeatPipelineEntry{
            macIpUdpHeader : firstBeatToSecondBeatPipelineReg.macIpUdpHeader,
            rdmaMeta    : rdmaMeta
        };
        secondBeatToThirdBeatPipelineReg <= outPipelineEntry;

        if (isLast) begin
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

        immAssert(
            !outBeat.isFirst,
            "The second beat's isFirst should be false",
            $format("outBeat=", fshow(outBeat))
        );

        $display(
            "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator genSecondBeat"),
            toBlue(", outBeat="), fshow(outBeat),
            toBlue(", ethernetFrameLeftByteCounterReg="), fshow(ethernetFrameLeftByteCounterReg),
            toBlue(", outPipelineEntry="), fshow(outPipelineEntry)
        );
    endrule

    rule genThirdBeat if (statusReg == EthernetPacketGeneratorStateGenThirdBeat);

        let rdmaMeta = secondBeatToThirdBeatPipelineReg.rdmaMeta;

        ethernetFrameLeftByteCounterReg <= ethernetFrameLeftByteCounterReg - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let isLast = ethernetFrameLeftByteCounterReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let mod = truncate(ethernetFrameLeftByteCounterReg);

        let macIpUdpHeader = secondBeatToThirdBeatPipelineReg.macIpUdpHeader;
        let macIpUdpBthEth = {pack(macIpUdpHeader), pack(rdmaMeta.header)};
        NocData data = truncateLSB(macIpUdpBthEth << valueOf(BYTE_NUM_OF_TWO_BEATS) * valueOf(BYTE_WIDTH));

        let outBeat = genEthernetPacket(swapEndianByte(data), 0, mod, False, isLast);

        ethernetPacketPipeOutQ.enq(outBeat);

        if (isLast) begin
            statusReg <= EthernetPacketGeneratorStateGenFirstBeat;
        end
        else begin
            statusReg <= EthernetPacketGeneratorStateGenMoreBeat;
        end

        immAssert(
            !outBeat.isFirst,
            "The third beat's isFirst should be false",
            $format("outBeat=", fshow(outBeat))
        );

        $display(
            "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator genThirdBeat"),
            toBlue(", outBeat="), fshow(outBeat),
            toBlue(", ethernetFrameLeftByteCounterReg="), fshow(ethernetFrameLeftByteCounterReg),
            toBlue(", rdmaMeta="), fshow(rdmaMeta)
        );
    endrule

    

    rule genMoreBeat if (statusReg == EthernetPacketGeneratorStateGenMoreBeat);

        ethernetFrameLeftByteCounterReg <= ethernetFrameLeftByteCounterReg - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        let isLast = ethernetFrameLeftByteCounterReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        EthernetNapMod mod = truncate(ethernetFrameLeftByteCounterReg);

        let payload = rdmaPayloadPipeInQ.first;
        rdmaPayloadPipeInQ.deq;
        NocData data = payload.data;

        // Form the forth beat and so on, these beats are payloads, no need to change byte order.
        let outBeat = genEthernetPacket(data, payload.startByteIdx, mod, False, isLast);

        ethernetPacketPipeOutQ.enq(outBeat);

        immAssert(
            !outBeat.isFirst,
            "The more beat's isFirst should be false",
            $format("outBeat=", fshow(outBeat))
        );

        // $display(
        //     "time=%0t:", $time, toGreen(" mkEthernetPacketGenerator genMoreBeat"),
        //     toBlue(", outBeat="), fshow(outBeat),
        //     toBlue(", ethernetFrameLeftByteCounterReg="), fshow(ethernetFrameLeftByteCounterReg)
        // );

        if (isLast) begin
            immAssert(
                payload.isLast,
                "payload should be last packet when isLast is true. mismatch between two calculate method",
                $format("Got payload = ", fshow(payload), "ethernetFrameLeftByteCounterReg=", fshow(ethernetFrameLeftByteCounterReg))
            );

            ByteEnBitNum byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
            if (isLast) begin
                byteNum = mod == 0 ? fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) : zeroExtend(pack(mod));
            end

            let byteNumPlusPcieDwordAlign = payload.byteNum + zeroExtend(payload.startByteIdx);
            immAssert(
                byteNumPlusPcieDwordAlign == byteNum,
                "last beat of payload length calcaluted by two different ways have different result.",
                $format(
                    "Got payload = ", fshow(payload),
                    ", outBeat=", fshow(outBeat),
                    ", mod=", fshow(mod),
                    ", ethernetFrameLeftByteCounterReg=", fshow(ethernetFrameLeftByteCounterReg)
                )
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