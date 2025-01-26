import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


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
import EthernetFrameIO :: *;
import QPContext :: *;
import PacketGenAndParse :: *;
import IoChannels :: *;

interface SQ;
    interface PipeInB0#(WorkQueueElem) wqePipeIn;
    interface PipeOut#(IoChannelEthDataStream) packetPipeOut;

    interface ClientP#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryClt;

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