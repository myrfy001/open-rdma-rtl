import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;

import Vector :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;
import AddressChunker :: *;
import EthernetTypes :: *;
import PayloadGenAndCon :: *;
import QPContext :: *;
import PacketGenAndParse :: *;
import IoChannels :: *;

interface SQ;
    interface PipeInB0#(WorkQueueElem) wqePipeIn;

    interface PipeOut#(ThinMacIpUdpMetaDataForSend) macIpUdpMetaPipeOut;
    interface PipeOut#(RdmaSendPacketMeta)          rdmaPacketMetaPipeOut;
    interface PipeOut#(DataStream)                  rdmaPayloadPipeOut;

    interface ClientP#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryClt;

    interface PipeOut#(PayloadGenReq) payloadGenReqPipeOut;
    interface PipeIn#(DataStream) payloadGenRespPipeIn;
endinterface

(* synthesize *)
module mkSQ(SQ);

    let packetGen <- mkPacketGen;
    
    interface wqePipeIn = packetGen.wqePipeIn;
    
    interface macIpUdpMetaPipeOut = packetGen.macIpUdpMetaPipeOut;
    interface rdmaPacketMetaPipeOut = packetGen.rdmaPacketMetaPipeOut;
    interface rdmaPayloadPipeOut = packetGen.rdmaPayloadPipeOut;

    interface mrTableQueryClt = packetGen.mrTableQueryClt;

    interface payloadGenReqPipeOut = packetGen.genReqPipeOut;
    interface payloadGenRespPipeIn = packetGen.genRespPipeIn;
endmodule


interface SqGroup;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, SQ) sqVec;
endinterface

(* synthesize *)
module mkSqGroup(SqGroup);
    Vector#(HARDWARE_QP_CHANNEL_CNT, SQ) inner = newVector;
    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        inner[idx] <- mkSQ;
    end
    interface sqVec = inner;
endmodule