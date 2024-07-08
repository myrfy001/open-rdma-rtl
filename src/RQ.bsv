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

interface RQ;
    interface Client#(ReadReqQPC, Maybe#(EntryQPC)) qpcQueryClt; 

    interface PipeIn#(EthernetNapBeatEntry) ethernetFramePipeIn;
    interface PipeOut#(DataStream) otherRawPacketPipeOut;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 


endinterface


module mkRQ(RQ);
    PacketParse packetParser <- mkPacketParse;

    FIFOF#(DataStream) payloadStorage <- mkSizedFIFOF(valueOf(MAX_PAYLOAD_STORAGE_CAPACITY_PER_RQ));
    FIFOF#(ThinMacIpUdpMetaDataForRecv) peerMetaStorage <- mkSizedFIFOF(valueOf(MAX_PEER_META_STORAGE_CAPACITY_PER_RQ));
    mkConnection(packetParser.rdmaPayloadPipeOut, toPipeIn(payloadStorage));
    mkConnection(packetParser.rdmaMacIpUdpMetaPipeOut, toPipeIn(peerMetaStorage));

    QueuedClient#(ReadReqQPC, Maybe#(EntryQPC)) qpcQueryCltInst <- mkQueuedClient("qpcQueryCltInst");

    // Pipeline Queues

    rule sendQpcQueryReq;
        let rdmaPacketMeta = packetParser.rdmaPacketMetaPipeOut.first;
        packetParser.rdmaPacketMetaPipeOut.deq;

        let qpcQueryResp = ReadReqQPC{
            qpn: rdmaPacketMeta.header.bth.dqpn
        };
        qpcQueryCltInst.putReq(qpcQueryResp);

    endrule

    // rule getQpcQueryResp;
    // endrule
    

    interface qpcQueryClt = qpcQueryCltInst.clt; 

    interface ethernetFramePipeIn = packetParser.ethernetFramePipeIn;
    interface otherRawPacketPipeOut = packetParser.otherRawPacketPipeOut;
    method setLocalNetworkSettings = packetParser.setLocalNetworkSettings; 
endmodule