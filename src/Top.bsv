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

module mkBsvTop#(
        Clock clkEthNap,
        Reset rstEthNap,
        Clock clkQpcMrPgtSrv,
        Reset rstQpcMrPgtSrv
    )(BsvTop);

    // Clock clkEthNap <- exposeCurrentClock;
    // Reset rstEthNap <- exposeCurrentReset;

    // Clock clkQpcMrPgtSrv <- exposeCurrentClock;
    // Reset rstQpcMrPgtSrv <- exposeCurrentReset;


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

    // Vector#(HARDWARE_QP_CHANNEL_CNT, FIFOF#(AxiMmNapBeatAw)) awRelayVecInst <- replicateM(mkFIFOF(clocked_by clkEthNap, reset_by rstEthNap));
    // Vector#(HARDWARE_QP_CHANNEL_CNT, FIFOF#(AxiMmNapBeatW)) wRelayVecInst <- replicateM(mkFIFOF(clocked_by clkEthNap, reset_by rstEthNap));
    // Vector#(HARDWARE_QP_CHANNEL_CNT, FIFOF#(AxiMmNapBeatB)) bRelayVecInst <- replicateM(mkFIFOF(clocked_by clkEthNap, reset_by rstEthNap));
    // Vector#(HARDWARE_QP_CHANNEL_CNT, FIFOF#(AxiMmNapBeatAr)) arRelayVecInst <- replicateM(mkFIFOF(clocked_by clkEthNap, reset_by rstEthNap));
    // Vector#(HARDWARE_QP_CHANNEL_CNT, FIFOF#(AxiMmNapBeatR)) rRelayVecInst <- replicateM(mkFIFOF(clocked_by clkEthNap, reset_by rstEthNap));


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

        // mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.writePipeIfc.writeAddrPipeOut, toPipeIn(awRelayVecInst[idx]), clocked_by clkEthNap, reset_by rstEthNap);
        // mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.writePipeIfc.writeDataPipeOut, toPipeIn(wRelayVecInst[idx]), clocked_by clkEthNap, reset_by rstEthNap);
        // mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.writePipeIfc.writeRespPipeIn, toPipeOut(bRelayVecInst[idx]), clocked_by clkEthNap, reset_by rstEthNap);
        // mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.readPipeIfc.readAddrPipeOut, toPipeIn(arRelayVecInst[idx]), clocked_by clkEthNap, reset_by rstEthNap);
        // mkConnection(payloadGenAndConVec[idx].axiNapPipeIfc.readPipeIfc.readRespPipeIn, toPipeOut(rRelayVecInst[idx]), clocked_by clkEthNap, reset_by rstEthNap);

        // mkConnection(toPipeOut(awRelayVecInst[idx]), dmaReadWriteSlaveNapVec[idx].writePipeIfc.writeAddrPipeIn, clocked_by clkEthNap, reset_by rstEthNap);
        // mkConnection(toPipeOut(wRelayVecInst[idx]), dmaReadWriteSlaveNapVec[idx].writePipeIfc.writeDataPipeIn, clocked_by clkEthNap, reset_by rstEthNap);
        // mkConnection(toPipeIn(bRelayVecInst[idx]), dmaReadWriteSlaveNapVec[idx].writePipeIfc.writeRespPipeOut, clocked_by clkEthNap, reset_by rstEthNap);
        // mkConnection(toPipeOut(arRelayVecInst[idx]), dmaReadWriteSlaveNapVec[idx].readPipeIfc.readAddrPipeIn, clocked_by clkEthNap, reset_by rstEthNap);
        // mkConnection(toPipeIn(rRelayVecInst[idx]), dmaReadWriteSlaveNapVec[idx].readPipeIfc.readRespPipeOut, clocked_by clkEthNap, reset_by rstEthNap);


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