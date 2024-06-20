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

import DataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;

import ConnectableF :: *;

interface InputPacketClassifier;
    interface PipeIn#(EthernetNapBeatEntry) ethRawPacketPipeIn;
    interface PipeOut#(DataStream) rdmaRawPacketPipeOut;
    interface PipeOut#(ThinMacIpUdpMetaData) rdmaMacIpUdpMetaPipeOut;
    interface PipeOut#(DataStream) otherRawPacketPipeOut;
    method setMacAndIp(EthMacAddr macAddr, IpAddr ipADdr);
endinterface


typedef 14 IP_HEADER_OFFSET_IN_FIRST_BEAT;

typedef 2 UDP_HEADER_OFFSET_IN_SECOND_BEAT;


typedef enum {
    InputPacketClassifierStateHandleFirstBeat = 0,
    InputPacketClassifierStateHandleSecondBeat = 1,
    InputPacketClassifierStateHandleMoreBeat = 2
} InputPacketClassifierState deriving#(FShow, Eq);

typedef struct {
    Bool mustNotBeRdmaPacket;
    ThinMacIpUdpMetaData macIpUdpMeta;
} EthernetPacketMetaExtractPipelineEntry;;

typedef struct {
    Bool isRdmaPacket;
    Bool isError;
} EthernetPacketMeta;

module mkInputPacketClassifier(InputPacketClassifier);
    Reg#(InputPacketClassifierState) stateReg <- mkReg(InputPacketClassifierStateHandleFirstBeat);

    FIFOF#(EthernetNapBeatEntry) ethRawPacketInQ <- mkFIFOF;
    FIFOF#(DataStream) rdmaRawPacketOutQ <- mkFIFOF;
    FIFOF#(ThinMacIpUdpMetaData) rdmaMacIpUdpMetaOutQ <- mkFIFOF;
    FIFOF#(DataStream) otherRawPacketOutQ <- mkFIFOF;

    FIFOF#(DataStream) waitingForRouteQ <- mkFIFOF;
    FIFOF#(EthernetPacketMeta) ethPacketMetaQ <- mkFIFOF;

    Reg#(EthernetPacketMetaExtractPipelineEntry) ethPacketMetaExtractPipelineEntry <- mkRegU;

    Reg#(Maybe#(Tuple2#(EthMacAddr, IpAddr))) macIpReg <- mkReg(tagged Invalid);

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

        let macIpUdpMeta = ThinMacIpUdpMetaData{
            srcMacAddr: ethHeader,
            ipDscp: partialIpHeader.ipDscp,
            ipEcn: partialIpHeader.ipEcn,
            srcIpAddr:partialIpHeader.srcIpAddr,
            srcPort: ?
        };

        ethPacketMetaExtractPipelineEntry <= EthernetPacketMetaExtractPipelineEntry{
            mustNotBeRdmaPacket: mustNotBeRdmaPacket,
            macIpUdpMeta: macIpUdpMeta
        };
        
        stateReg <= InputPacketClassifierStateHandleSecondBeat;
    endrule

    rule handleSecondBeatStage if (stateReg == InputPacketClassifierStateHandleFirstBeat);
        let beat = reverseStream(ethRawPacketInQ.first);
        ethRawPacketInQ.deq;

        EthernetNapRecvOtherBeat beatPayload = unpack(beat.data);

        let byteNum =  beat.eop ? (
                beatPayload.mod == 0 ? fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH)) : beatPayload.mod
            ) : fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH));

        let ds = DataStream{
            data: swapEndianByte(beatPayload.data),
            byteNum: byteNum,
            isFirst: beat.sop,
            isLast: beat.eop
        };

        waitingForRouteQ.enq(ds);

        immAssert(
            !beat.sop,
            "mkInputPacketClassifier second beat error",
            $format("sop should be False handleSecondBeatStage, beat=", fshow(beat))
        );

        UdpHeader udpHeader = unpack(truncateLSB(pack(ds.data) << valueOf(UDP_HEADER_OFFSET_IN_SECOND_BEAT)));

        Bool mustNotBeRdmaPacket = False;
        if (udpHeader.dstPort != fromInteger(valueOf(UDP_PORT_RDMA))) begin
            mustNotBeRdmaPacket = True;
        end
        mustNotBeRdmaPacket = mustNotBeRdmaPacket | ethPacketMetaExtractPipelineEntry.mustNotBeRdmaPacket;

        // This is the final check condition. so if it is not "mustn't be RDMA", then it is RDMA
        Bool isRDMA = !mustNotBeRdmaPacket;
        ethPacketMetaQ.enq(EthernetPacketMeta{
            isRdmaPacket: isRDMA,
            isError: beatPayload.error
        });

        let macIpUdpMeta = ethPacketMetaExtractPipelineEntry.macIpUdpMeta;
        macIpUdpMeta.srcPort = udpHeader.srcPort;

        if (isRDMA && !beatPayload.error) begin
            rdmaMacIpUdpMetaOutQ.enq(macIpUdpMeta);
        end
        
        stateReg <= beat.eop ? InputPacketClassifierStateHandleFirstBeat : InputPacketClassifierStateHandleMoreBeat;
    endrule

    rule handleMoreBeatStage if (stateReg == InputPacketClassifierStateHandleMoreBeat);
        let beat = reverseStream(ethRawPacketInQ.first);
        ethRawPacketInQ.deq;

        immAssert(
            !beat.sop,
            "mkInputPacketClassifier second beat error",
            $format("sop should be False handleMoreBeatStage, beat=", fshow(beat))
        );

        EthernetNapRecvOtherBeat beatPayload = unpack(beat.data);
        let byteNum =  beat.eop ? (
                beatPayload.mod == 0 ? fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH)) : beatPayload.mod
            ) : fromInteger(valueOf(NOC_DATA_BUS_BYTE_WIDTH));

        let ds = DataStream{
            data: swapEndianByte(beatPayload.data),
            byteNum: byteNum,
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
        let etmPktMeta = ethPacketMetaQ.first;

        // discard error packet.
        if (!etmPktMeta.isError) begin
            if (isRDMA) begin
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


    method setMacAndIp(EthMacAddr macAddr, IpAddr ipADdr);
        macIpReg <= tagged Valid tuple2(macAddr, ipADdr);
    endmethod
endmodule



// // ETH + IP + UDP = 14 + 20 + 8 = 42, each beat has 32 byte
// // So, in the second beat, the BTH offset should be at 42 - 32 = 10
// typedef 10 BTH_OFFSET_IN_SECOND_BEAT;

interface RdmaHeaderExtractor;
        interface PipeIn#(DataStream) ethPipeIn;
        interface PipeOut#(DataStream) rdmaPipeOut;
endinterface

module mkRdmaHeaderExtractor(RdmaHeaderExtractor);
    Reg#(Bool) isSecondBeadReg <- mkReg(False);

    FIFOF#(DataStream) ethPipeInQ <- mkFIFOF;
    // FIFOF#(DataStream) rdmaPipeOutQ <- mkFIFOF;
    rule handleFirstAndSecondBeat;
        let ds = ethPipeInQ.first;
        ethPipeInQ.deq;

        if (ds.isFirst) begin
            isSecondBeadReg <= True
        end
        
        if (isSecondBeadReg) begin
            isSecondBeadReg <= False;
            BTH bth = unpack(ds.data[valueOf(BTH_OFFSET_IN_SECOND_BEAT) : valueOf(BTH_OFFSET_IN_SECOND_BEAT) + sizeOf(BTH)]);
            
        end
    endrule
endmodule


// interface RemoveMacIpUdpHeaderFromStream;
//     interface PipeIn#(DataStream) ethPipeIn;
//     interface PipeOut#(DataStream) rdmaPipeOut;
// endinterface

// module mkRemoveMacIpUdpHeaderFromStream(RemoveMacIpUdpHeaderFromStream);
//     FIFOF#(DataStream) ethPipeInQ <- mkFIFOF;
//     FIFOF#(DataStream) rdmaPipeOutQ <- mkFIFOF;

//     Reg#(DataStream) previousBeatReg <- mkRegU;

//     rule shiftBeatFirst;
//         let ds = ethPipeInQ.first;
//         ethPipeInQ.deq;

//         previousBeatReg <= ds;
//         if (ds.isLast) begin

//         end
//         else begin
//         end


//     endrule

//     rule shiftBeatMiddle;
//         let ds = ethPipeInQ.first;
//         ethPipeInQ.deq;
//     endrule

//     rule outputExtraBeat;
//     endrule
// endmodule



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