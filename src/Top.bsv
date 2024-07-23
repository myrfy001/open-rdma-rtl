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
import Ringbuf :: *;


interface BsvTop;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVec;
    interface Server#(WriteReqQPC, Bool) qpContextUpdateSrv;
    interface Server#(PgtModifyReq, PgtModifyResp) pgtModifySrv;
    interface Server#(MrTableModifyReq, MrTableModifyResp) mrTableModifySrv;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface


module mkBsvTop#(
        Clock clkEthNap,
        Reset rstEthNap,
        Clock clkQpcMrPgtSrv,
        Reset rstQpcMrPgtSrv
    )(BsvTop);

    let qpMrPgtQpc <- mkQpMrPgtQpc(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv);

    // Ringbuf and it's NAPs
    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufC2hSlot4096) c2hRingbufVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufH2cSlot4096) h2cRingbufVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufDmaNapWrappr) ringbufDmaNapVec <- replicateM(mkRingbufDmaNapWrappr);

    Vector#(HARDWARE_QP_CHANNEL_CNT, WorkQueueRingbufController) sendQueueDescToWqeConvertorVec <- replicateM(mkWorkQueueRingbufController);

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        c2hRingbufVec[idx] <- mkRingbufC2h(fromInteger(idx));
        h2cRingbufVec[idx] <- mkRingbufH2c(fromInteger(idx));

        mkConnection(c2hRingbufVec[idx].dmaWriteReqPipeOut, ringbufDmaNapVec[idx].dmaWriteReqPipeIn);
        mkConnection(c2hRingbufVec[idx].dmaWriteDataPipeOut, ringbufDmaNapVec[idx].dmaWriteDataPipeIn);
        mkConnection(c2hRingbufVec[idx].dmaWriteRespPipeIn, ringbufDmaNapVec[idx].dmaWriteRespPipeOut);
        mkConnection(h2cRingbufVec[idx].dmaReadReqPipeOut, ringbufDmaNapVec[idx].dmaReadReqPipeIn);
        mkConnection(h2cRingbufVec[idx].dmaReadRespPipeIn, ringbufDmaNapVec[idx].dmaReadRespPipeOut);

        mkConnection(h2cRingbufVec[idx].descPipeOut, sendQueueDescToWqeConvertorVec[idx].rawDescPipeIn);
        mkConnection(sendQueueDescToWqeConvertorVec[idx].workReqPipeOut, qpMrPgtQpc.wqePipeInVec[idx]);
    end


    interface otherRawPacketPipeOutVec = qpMrPgtQpc.otherRawPacketPipeOutVec; 
    interface qpContextUpdateSrv = qpMrPgtQpc.qpContextUpdateSrv; 
    interface pgtModifySrv = qpMrPgtQpc.pgtModifySrv; 
    interface mrTableModifySrv = qpMrPgtQpc.mrTableModifySrv; 
    method setLocalNetworkSettings = qpMrPgtQpc.setLocalNetworkSettings; 
endmodule


interface QpMrPgtQpc;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVec;
    interface Server#(WriteReqQPC, Bool) qpContextUpdateSrv;
    interface Server#(PgtModifyReq, PgtModifyResp) pgtModifySrv;
    interface Server#(MrTableModifyReq, MrTableModifyResp) mrTableModifySrv;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface

(* synthesize *)
module mkQpMrPgtQpc#(
        Clock clkEthNap,
        Reset rstEthNap,
        Clock clkQpcMrPgtSrv,
        Reset rstQpcMrPgtSrv
    )(QpMrPgtQpc);


    QpContextFourWayQuery qpContext <- mkQpContextFourWayQuery(clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
    MemRegionTableEightWayQuery mrTable <- mkMemRegionTableEightWayQuery(clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
    AddressTranslateEightWayQuery addrTranslator <- mkAddressTranslateEightWayQuery(clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);


    Vector#(HARDWARE_QP_CHANNEL_CNT, AcxNapEthernetWrapperPipe) ethNapVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PayloadGenAndCon) payloadGenAndConVec <- replicateM(mkPayloadGenAndCon(clkQpcMrPgtSrv, rstQpcMrPgtSrv, clocked_by clkEthNap, reset_by rstEthNap));
    Vector#(HARDWARE_QP_CHANNEL_CNT, AcxNapSlaveWrapperPipe) dmaReadWriteSlaveNapVec <- replicateM(mkAcxNapSlaveWrapperPipe(clocked_by clkEthNap, reset_by rstEthNap));
    Vector#(HARDWARE_QP_CHANNEL_CNT, SQ) sqVec <- replicateM(mkSQ(clkEthNap,  rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv));
    Vector#(HARDWARE_QP_CHANNEL_CNT, RQ) rqVec <- replicateM(mkRQ(clkEthNap,  rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv));
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVecInst = newVector;

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin

        // Payload gen and con
        mkConnection(sqVec[idx].payloadGenReqPipeOut, payloadGenAndConVec[idx].genReqPipeIn);
        mkConnection(sqVec[idx].payloadGenRespPipeIn, payloadGenAndConVec[idx].payloadGenStreamPipeOut);

        mkConnection(rqVec[idx].payloadConReqPipeOut, payloadGenAndConVec[idx].conReqPipeIn, clocked_by clkEthNap, reset_by rstEthNap);
        mkConnection(rqVec[idx].payloadConRespPipeIn, payloadGenAndConVec[idx].conRespPipeOut, clocked_by clkEthNap, reset_by rstEthNap);
        mkConnection(rqVec[idx].payloadConStreamPipeOut, payloadGenAndConVec[idx].payloadConStreamPipeIn, clocked_by clkEthNap, reset_by rstEthNap);

        // ethernet nap
        ethNapVec[idx] <- mkAcxNapEthernetWrapperPipe(fromInteger(idx * 2), fromInteger(idx * 2 + 1), clocked_by clkEthNap, reset_by rstEthNap);
        mkConnection(sqVec[idx].packetPipeOut, ethNapVec[idx].sendPipeIn);
        mkConnection(rqVec[idx].ethernetFramePipeIn, ethNapVec[idx].recvPipeOut);


        // QPContext, MR Table and PGT
        mkConnection(rqVec[idx].qpcQueryClt, qpContext.querySrvVec[idx], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);

        mkConnection(sqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
        mkConnection(rqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2 + 1], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);

        mkConnection(payloadGenAndConVec[idx].genAddrTranslateClt, addrTranslator.querySrvVec[idx * 2], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
        mkConnection(payloadGenAndConVec[idx].conAddrTranslateClt, addrTranslator.querySrvVec[idx * 2 + 1], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);

        // RDMA payload DMA NAP

        mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.writePipeIfc.writeAddrPipeOut, dmaReadWriteSlaveNapVec[idx].writePipeIfc.writeAddrPipeIn, clocked_by clkEthNap, reset_by rstEthNap);
        mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.writePipeIfc.writeDataPipeOut, dmaReadWriteSlaveNapVec[idx].writePipeIfc.writeDataPipeIn, clocked_by clkEthNap, reset_by rstEthNap);
        mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.writePipeIfc.writeRespPipeIn, dmaReadWriteSlaveNapVec[idx].writePipeIfc.writeRespPipeOut, clocked_by clkEthNap, reset_by rstEthNap);
        mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.readPipeIfc.readAddrPipeOut, dmaReadWriteSlaveNapVec[idx].readPipeIfc.readAddrPipeIn, clocked_by clkEthNap, reset_by rstEthNap);
        mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.readPipeIfc.readRespPipeIn, dmaReadWriteSlaveNapVec[idx].readPipeIfc.readRespPipeOut, clocked_by clkEthNap, reset_by rstEthNap);

    
        // IO interface 
        wqePipeInVecInst[idx]               = sqVec[idx].wqePipeIn;
        otherRawPacketPipeOutVecInst[idx]   = rqVec[idx].otherRawPacketPipeOut;
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