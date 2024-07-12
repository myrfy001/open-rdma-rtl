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
endinterface

module mkSQ#(PayloadGenAndCon payloadGenAndCon)(SQ);
    let packetGen <- mkPacketGen(payloadGenAndCon);

    interface wqePipeIn = packetGen.wqePipeIn;
    interface packetPipeOut = packetGen.packetPipeOut;
    interface mrTableQueryClt = packetGen.mrTableQueryClt;
    method setLocalNetworkSettings = packetGen.setLocalNetworkSettings; 
endmodule