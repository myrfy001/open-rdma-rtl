import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
import Vector :: *;

import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import IoChannels :: *;
import PacketGenAndParse :: *;
import EthernetTypes :: *;
import MemRegionAndAddressTranslate :: *;
import QPContext :: *;
import PayloadGenAndCon :: *;


import Settings :: *;
import Utils4Test :: *;

import SQ :: *;
import RQ :: *;

import RTilePcieAdaptor :: *;
import FTileMacAdaptor :: *;


interface BsvTop;
        (* always_ready, always_enabled *)
        interface RTilePcieAdaptorRx rtilePcieAdaptorRxRawIfc;
        (* always_ready, always_enabled *)
        interface RTilePcieAdaptorTx rtilePcieAdaptorTxRawIfc;

        (* always_ready, always_enabled *)
        interface FTileMacAdaptorRx ftileMacAdaptorRxRawIfc;
        (* always_ready, always_enabled *)
        interface FTileMacAdaptorTx ftileMacAdaptorTxRawIfc;

        method Bit#(128) signalKeeperOutput;
        
endinterface


module mkBsvTop(BsvTop);
    RTilePcieAdaptor rtilePcieAdaptor   <- mkRTilePcieAdaptor;
    RTilePcie        rtilePcie          <- mkRTilePcie;

    FTileMacAdaptor  ftileMacAdaptor    <- mkFTileMacAdaptor;
    FTileMac         ftileMac           <- mkFTileMac;

    mkConnection(rtilePcieAdaptor.pcieRxPipeOut, rtilePcie.pcieRxPipeIn);
    mkConnection(rtilePcieAdaptor.pcieTxPipeIn, rtilePcie.pcieTxPipeOut);
    mkConnection(rtilePcieAdaptor.rxFlowControlReleaseReqPipeIn, rtilePcie.rxFlowControlReleaseReqPipeOut);
    mkConnection(rtilePcieAdaptor.txFlowControlConsumeReqPipeIn, rtilePcie.txFlowControlConsumeReqPipeOut);
    mkConnection(rtilePcieAdaptor.txFlowControlAvaliablePipeOut, rtilePcie.txFlowControlAvaliablePipeIn);

    mkConnection(ftileMacAdaptor.ftilemacRxPipeOut, ftileMac.ftilemacRxPipeIn);
    mkConnection(ftileMacAdaptor.ftilemacTxPipeIn, ftileMac.ftilemacTxPipeOut);

 

    ForceKeepWideSignals#(Bit#(4164), Bit#(32)) signalKeeperForPcieUserLogicReadOutput   <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(4164), Bit#(32)) signalKeeperForEthUserLogicReadOutput   <- mkForceKeepWideSignals; 

    Reg#(Bit#(128)) outReg <- mkReg(0);

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
    let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
    let randSource6 <- mkSynthesizableRng512('h11111111);
    let randSource7 <- mkSynthesizableRng512('h22222222);
    let randSource8 <- mkSynthesizableRng512('h33333333);
    let randSource9 <- mkSynthesizableRng512('h44444444);
    let randSourceA <- mkSynthesizableRng512('h55555555);
    let randSourceB <- mkSynthesizableRng512('h66666666);
    let randSourceC <- mkSynthesizableRng512('h77777777);
    let randSourceD <- mkSynthesizableRng512('h88888888);

    rule injectPcieUserLogicReq;
        let randValue1 <- randSource1.get;
        let randValue2 <- randSource2.get;
        let randValue3 <- randSource3.get;
        let randValue4 <- randSource4.get;
        let randValue5 <- randSource5.get;
        
        // write req as requester
        let writeMeta = unpack(truncate(randValue1));
        let writeData = unpack(truncate({randValue2, randValue3, randValue4}));
        rtilePcie.streamSlaveIfcVec[0].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[0].writePipeIfc.writeDataPipeIn.enq(writeData);

        writeMeta = unpack(truncate(randValue2));
        writeData = unpack(truncate({randValue1, randValue4, randValue3}));
        rtilePcie.streamSlaveIfcVec[1].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[1].writePipeIfc.writeDataPipeIn.enq(writeData);

        writeMeta = unpack(truncate(randValue5));
        writeData = unpack(truncate({randValue3, randValue2, randValue1}));
        rtilePcie.streamSlaveIfcVec[2].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[2].writePipeIfc.writeDataPipeIn.enq(writeData);

        writeMeta = unpack(truncate(randValue3));
        writeData = unpack(truncate({randValue4, randValue1, randValue2}));
        rtilePcie.streamSlaveIfcVec[3].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[3].writePipeIfc.writeDataPipeIn.enq(writeData);

        // read req as requester
        let readMeta = unpack(truncate(randValue5));
        rtilePcie.streamSlaveIfcVec[0].readPipeIfc.readMetaPipeIn.enq(readMeta);
        readMeta = unpack(truncate(randValue4));
        rtilePcie.streamSlaveIfcVec[1].readPipeIfc.readMetaPipeIn.enq(readMeta);
        readMeta = unpack(truncate(randValue3));
        rtilePcie.streamSlaveIfcVec[2].readPipeIfc.readMetaPipeIn.enq(readMeta);
        readMeta = unpack(truncate(randValue2));
        rtilePcie.streamSlaveIfcVec[3].readPipeIfc.readMetaPipeIn.enq(readMeta);

        // read resp as completer
        let readData = unpack(truncate({randValue1, randValue2, randValue5}));
        rtilePcie.streamMasterIfc.readPipeIfc.readDataPipeIn.enq(readData);
    endrule


    rule handlePcieUserlogicReadOutput;
        Vector#(NUMERIC_TYPE_FOUR, RtilePcieUserStream) resultVec = newVector;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
            if (rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.notEmpty) begin
                resultVec[idx] = rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.first;
                rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.deq;
            end
        end

        let completerWm = ?;
        let completerWd = ?;
        let completerRm = ?;
        if (rtilePcie.streamMasterIfc.writePipeIfc.writeMetaPipeOut.notEmpty) begin
            completerWm = rtilePcie.streamMasterIfc.writePipeIfc.writeMetaPipeOut.first;
            rtilePcie.streamMasterIfc.writePipeIfc.writeMetaPipeOut.deq;
        end
        if (rtilePcie.streamMasterIfc.writePipeIfc.writeDataPipeOut.notEmpty) begin
            completerWd = rtilePcie.streamMasterIfc.writePipeIfc.writeDataPipeOut.first;
            rtilePcie.streamMasterIfc.writePipeIfc.writeDataPipeOut.deq;
        end
        if (rtilePcie.streamMasterIfc.readPipeIfc.readMetaPipeOut.notEmpty) begin
            completerRm = rtilePcie.streamMasterIfc.readPipeIfc.readMetaPipeOut.first;
            rtilePcie.streamMasterIfc.readPipeIfc.readMetaPipeOut.deq;
        end

        signalKeeperForPcieUserLogicReadOutput.bitsPipeIn.enq(zeroExtend({pack(resultVec), pack(completerWm), pack(completerWd), pack(completerRm)}));

    endrule


    rule injectEthUserLogicReq;
        
        let randValue1 <- randSource6.get;
        let randValue2 <- randSource7.get;
        let randValue3 <- randSource8.get;
        let randValue4 <- randSource9.get;
        let randValue5 <- randSourceA.get;


        let writeStream1 = unpack(truncate(randValue1));
        let writeStream2 = unpack(truncate(randValue2));
        let writeStream3 = unpack(truncate(randValue3));
        let writeStream4 = unpack(truncate(randValue4));

        // write req
        ftileMac.ftilemacTxStreamPipeInVec[0].enq(writeStream1);
        ftileMac.ftilemacTxStreamPipeInVec[1].enq(writeStream2);
        ftileMac.ftilemacTxStreamPipeInVec[2].enq(writeStream3);
        ftileMac.ftilemacTxStreamPipeInVec[3].enq(writeStream4);
    endrule

    rule handleEthUSerlogicReadOutput;
        Vector#(NUMERIC_TYPE_FOUR, FtileMacRxUserStream) resultVec = newVector;

        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
            if (ftileMac.ftilemacRxStreamPipeOutVec[idx].notEmpty) begin
                resultVec[idx] = ftileMac.ftilemacRxStreamPipeOutVec[idx].first;
                ftileMac.ftilemacRxStreamPipeOutVec[idx].deq;
            end
        end

        signalKeeperForEthUserLogicReadOutput.bitsPipeIn.enq(zeroExtend(pack(resultVec)));

    endrule


    rule handleOutput;
        outReg <= zeroExtend({signalKeeperForPcieUserLogicReadOutput.out, signalKeeperForEthUserLogicReadOutput.out});
    endrule

    method signalKeeperOutput = outReg;

    interface rtilePcieAdaptorRxRawIfc = rtilePcieAdaptor.rx;
    interface rtilePcieAdaptorTxRawIfc = rtilePcieAdaptor.tx;
    interface ftileMacAdaptorRxRawIfc = ftileMacAdaptor.rx;
    interface ftileMacAdaptorTxRawIfc = ftileMacAdaptor.tx;
endmodule


interface QpMrPgtQpc;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)       qpDmaRequestMasterIfcVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelBiDirStreamNoMetaPipe)  qpEthDataStreamIfcVec;
        
    interface Server#(WriteReqQPC, Bool) qpContextUpdateSrv;
    interface Server#(PgtModifyReq, PgtModifyResp) pgtModifySrv;
    interface Server#(MrTableModifyReq, MrTableModifyResp) mrTableModifySrv;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface



(* synthesize *)
module mkQpMrPgtQpc(QpMrPgtQpc);

    Clock clkEthNap <- exposeCurrentClock;
    Reset rstEthNap <- exposeCurrentReset;
    Clock clkQpcMrPgtSrv <- exposeCurrentClock;
    Reset rstQpcMrPgtSrv <- exposeCurrentReset;


    QpContextFourWayQuery qpContext <- mkQpContextFourWayQuery(clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
    MemRegionTableEightWayQuery mrTable <- mkMemRegionTableEightWayQuery(clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
    AddressTranslateEightWayQuery addrTranslator <- mkAddressTranslateEightWayQuery(clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);


    Vector#(HARDWARE_QP_CHANNEL_CNT, PayloadGenAndCon) payloadGenAndConVec <- replicateM(mkPayloadGenAndCon(clkQpcMrPgtSrv, rstQpcMrPgtSrv, clocked_by clkEthNap, reset_by rstEthNap));
    Vector#(HARDWARE_QP_CHANNEL_CNT, SQ) sqVec <- replicateM(mkSQ(clkQpcMrPgtSrv, rstQpcMrPgtSrv));
    Vector#(HARDWARE_QP_CHANNEL_CNT, RQ) rqVec <- replicateM(mkRQ(clkQpcMrPgtSrv, rstQpcMrPgtSrv));
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVecInst = newVector;

    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)         qpDmaRequestMasterIfcVecInst    = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelBiDirStreamNoMetaPipe)    qpEthDataStreamIfcVecInst       = newVector;
    

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin

        // Payload gen and con
        mkConnection(sqVec[idx].payloadGenReqPipeOut, payloadGenAndConVec[idx].genReqPipeIn);
        mkConnection(sqVec[idx].payloadGenRespPipeIn, payloadGenAndConVec[idx].payloadGenStreamPipeOut);

        mkConnection(rqVec[idx].payloadConReqPipeOut, payloadGenAndConVec[idx].conReqPipeIn, clocked_by clkEthNap, reset_by rstEthNap);
        mkConnection(rqVec[idx].payloadConRespPipeIn, payloadGenAndConVec[idx].conRespPipeOut, clocked_by clkEthNap, reset_by rstEthNap);
        mkConnection(rqVec[idx].payloadConStreamPipeOut, payloadGenAndConVec[idx].payloadConStreamPipeIn, clocked_by clkEthNap, reset_by rstEthNap);

        // ethernet nap
        qpEthDataStreamIfcVecInst[idx] = (
                interface DtldStreamNoMetaBiDirPipes
                    interface dataPipeIn = rqVec[idx].ethernetFramePipeIn;
                    interface dataPipeOut = sqVec[idx].packetPipeOut;
                endinterface
            );


        // QPContext, MR Table and PGT
        mkConnection(rqVec[idx].qpcQueryClt, qpContext.querySrvVec[idx], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);

        mkConnection(sqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
        mkConnection(rqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2 + 1], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);

        mkConnection(payloadGenAndConVec[idx].genAddrTranslateClt, addrTranslator.querySrvVec[idx * 2], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
        mkConnection(payloadGenAndConVec[idx].conAddrTranslateClt, addrTranslator.querySrvVec[idx * 2 + 1], clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);

        // RDMA payload DMA Ifc
        qpDmaRequestMasterIfcVecInst[idx] = payloadGenAndConVec[idx].ioChannelMemoryMasterPipeIfc;
    
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
    interface qpDmaRequestMasterIfcVec = qpDmaRequestMasterIfcVecInst;
    interface qpEthDataStreamIfcVec = qpEthDataStreamIfcVecInst;
    interface qpContextUpdateSrv = qpContext.updateSrv;
    interface pgtModifySrv = addrTranslator.modifySrv;
    interface mrTableModifySrv = mrTable.modifySrv;
endmodule