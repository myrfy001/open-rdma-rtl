import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;
import AddressChunker :: *;
import EthernetTypes :: *;
import PayloadGenAndCon :: *;
import EthernetFrameIO :: *;
import StreamShifter :: *;
import QPContext :: *;
import PacketGenAndParse :: *;

interface SQ;
    interface PipeIn#(WorkQueueElem) wqePipeIn;
    interface PipeOut#(EthernetNapBeatEntry) packetPipeOut;

    interface Client#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryClt;

    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 

    interface PipeOut#(PayloadGenReq) payloadGenReqPipeOut;
    interface PipeIn#(DataStream) payloadGenRespPipeIn;
endinterface

(* synthesize *)
module mkSQ(SQ);
    let packetGen <- mkPacketGen;
    interface wqePipeIn = packetGen.wqePipeIn;
    interface packetPipeOut = packetGen.packetPipeOut;
    interface mrTableQueryClt = packetGen.mrTableQueryClt;
    method setLocalNetworkSettings = packetGen.setLocalNetworkSettings; 

    interface payloadGenReqPipeOut = packetGen.genReqPipeOut;
    interface payloadGenRespPipeIn = packetGen.genRespPipeIn;
endmodule