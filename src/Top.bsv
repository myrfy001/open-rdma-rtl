import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import Vector :: *;

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
import MemRegionAndAddressTranslate :: *;
import SQ :: *;
import RQ :: *;


interface BsvTop;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVec;
    interface Server#(WriteReqQPC, Bool) qpContextUpdateSrv;
    interface Server#(PgtModifyReq, PgtModifyResp) pgtModifySrv;
    interface Server#(MrTableModifyReq, MrTableModifyResp) mrTableModifySrv;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface

module mkBsvTop(BsvTop);

    QpContextFourWayQuery qpContext <- mkQpContextFourWayQuery;
    MemRegionTableEightWayQuery mrTable <- mkMemRegionTableEightWayQuery;
    AddressTranslateEightWayQuery addrTranslator <- mkAddressTranslateEightWayQuery;


    Vector#(HARDWARE_QP_CHANNEL_CNT, AcxNapEthernetWrapper) ethNapVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PayloadGenAndCon) payloadGenAndConVec <- replicateM(mkPayloadGenAndCon);
    Vector#(HARDWARE_QP_CHANNEL_CNT, SQ) sqVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, RQ) rqVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVecInst = newVector;

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        sqVec[idx] <- mkSQ(payloadGenAndConVec[idx]);
        rqVec[idx] <- mkRQ(payloadGenAndConVec[idx]);
        ethNapVec[idx] <- mkAcxNapEthernetWrapper(fromInteger(idx * 2), fromInteger(idx * 2 + 1));

        mkConnection(rqVec[idx].qpcQueryClt, qpContext.querySrvVec[idx]);

        mkConnection(sqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2]);
        mkConnection(rqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2 + 1]);

        mkConnection(payloadGenAndConVec[idx].genAddrTranslateClt, addrTranslator.querySrvVec[idx * 2]);
        mkConnection(payloadGenAndConVec[idx].conAddrTranslateClt, addrTranslator.querySrvVec[idx * 2 + 1]);

        wqePipeInVecInst[idx]               = sqVec[idx].wqePipeIn;
        otherRawPacketPipeOutVecInst[idx]   = rqVec[idx].otherRawPacketPipeOut;

        rule forwardEthBeatSend;
            if (sqVec[idx].packetPipeOut.notEmpty) begin
                ethNapVec[idx].send(sqVec[idx].packetPipeOut.first);
                sqVec[idx].packetPipeOut.deq;
            end
        endrule   
        
        rule forwardEthBeatRecv;
            let beat <- ethNapVec[idx].recv;
            rqVec[idx].ethernetFramePipeIn.enq(beat);
        endrule   
    end

    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
        for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            sqVec[idx].setLocalNetworkSettings(networkSettings);
            rqVec[idx].setLocalNetworkSettings(networkSettings);
        end
    endmethod

    interface wqePipeInVec              = wqePipeInVecInst;
    interface otherRawPacketPipeOutVec  = otherRawPacketPipeOutVecInst;
    interface qpContextUpdateSrv = qpContext.updateSrv;
    interface pgtModifySrv = addrTranslator.modifySrv;
    interface mrTableModifySrv = mrTable.modifySrv;
endmodule