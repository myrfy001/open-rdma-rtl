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
import PacketGenAndParse :: *;
import MemRegionAndAddressTranslate :: *;
import QPContext :: *;
import PayloadGenAndCon :: *;
import CsrRootConnector :: *;
import CsrFramework :: *;
import Ringbuf :: *;
import DescriptorParsers :: *;
import CsrAddress :: *;

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

    BsvTopWithoutHardIpInstance bsvTopWithoutHardIpInstance <- mkBsvTopWithoutHardIpInstance;

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


interface TopLevelDmaChannelMux;
    // upstream port
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)   dmaMasterPipeIfcVec;

    // downstream port
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemorySlavePipe)   qpRingbufDmaSlavePipeIfcVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemorySlavePipe)   qpDmaRequestSlaveIfcVec;
    interface IoChannelMemorySlavePipe cmdQueueRingbufDmaSlavePipeIfc;
    interface IoChannelMemorySlavePipe pgtUpdateDmaSlavePipe;


endinterface

(* synthesize *)
module mkTopLevelDmaChannelMux(TopLevelDmaChannelMux);
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelFourChannelDmaMux)     muxVector <- replicateM(mkDtldStreamArbiterSlave(256, True));
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)     dmaMasterPipeIfcVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemorySlavePipe)      qpRingbufDmaSlavePipeIfcVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemorySlavePipe)      qpDmaRequestSlaveIfcVecInst = newVector;

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        dmaMasterPipeIfcVecInst[idx] = muxVector[idx].masterIfc;
        qpRingbufDmaSlavePipeIfcVecInst[idx] = muxVector[idx].slaveIfcVec[0];
        qpDmaRequestSlaveIfcVecInst[idx] = muxVector[idx].slaveIfcVec[1];
    end

    // upstream port
    interface dmaMasterPipeIfcVec = dmaMasterPipeIfcVecInst;

    // downstream port
    interface qpRingbufDmaSlavePipeIfcVec = qpRingbufDmaSlavePipeIfcVecInst;
    interface qpDmaRequestSlaveIfcVec = qpDmaRequestSlaveIfcVecInst;
    interface cmdQueueRingbufDmaSlavePipeIfc = muxVector[0].slaveIfcVec[2]; // use channel 0 for cmd queue.
    interface pgtUpdateDmaSlavePipe = muxVector[1].slaveIfcVec[2]; // use channel 1 for pgt update.
endmodule

interface BsvTopWithoutHardIpInstance;
    interface IoChannelMemorySlavePipe dmaSlavePipeIfc;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)   dmaMasterPipeIfcVec;
endinterface


(* synthesize *)
module mkBsvTopWithoutHardIpInstance(BsvTopWithoutHardIpInstance);
    let qpMrPgtQpc <- mkQpMrPgtQpc;
    let ringbufAndDescriptorHandler <- mkRingbufAndDescriptorHandler;
    mkConnection(ringbufAndDescriptorHandler.wqePipeOutVec, qpMrPgtQpc.wqePipeInVec);

    TopLevelDmaChannelMux topLevelDmaChannelMux <- mkTopLevelDmaChannelMux;
    

    let csrRootConnector <- mkCsrRootConnector;
    function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
        actionvalue
            return tagged CsrNodeResultForward 0;
        endactionvalue
    endfunction
    
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_TWO));
    mkConnection(csrRootConnector.csrNodeRootPortIfc, csrNode.upStreamPort);
    mkConnection(ringbufAndDescriptorHandler.csrUpStreamPort, csrNode.downStreamPortsVec[0]);


    mkConnection(qpMrPgtQpc.pgtUpdateDmaMasterPipe, topLevelDmaChannelMux.pgtUpdateDmaSlavePipe);
    mkConnection(qpMrPgtQpc.qpDmaRequestMasterIfcVec, topLevelDmaChannelMux.qpDmaRequestSlaveIfcVec);
    mkConnection(ringbufAndDescriptorHandler.qpRingbufDmaMasterPipeIfcVec, topLevelDmaChannelMux.qpRingbufDmaSlavePipeIfcVec);
    mkConnection(ringbufAndDescriptorHandler.cmdQueueRingbufDmaMasterPipeIfc, topLevelDmaChannelMux.cmdQueueRingbufDmaSlavePipeIfc);

 

    interface dmaSlavePipeIfc = csrRootConnector.dmaSidePipeIfc;
    interface dmaMasterPipeIfcVec = topLevelDmaChannelMux.dmaMasterPipeIfcVec;
endmodule



interface RingbufAndDescriptorHandler;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)   qpRingbufDmaMasterPipeIfcVec;
    interface IoChannelMemoryMasterPipe cmdQueueRingbufDmaMasterPipeIfc;
    interface BlueRdmaCsrUpStreamPort csrUpStreamPort;

    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(WorkQueueElem))     wqePipeOutVec;
    interface Client#(RingbufRawDescriptor, Bool)                           mrAndPgtManagerClt;
    interface Client#(WriteReqQPC, Bool)                                    qpcModifyClt;
    interface PipeOut#(LocalNetworkSettings)                                setNetworkParamReqPipeOut;
endinterface

(* synthesize *)
module mkRingbufAndDescriptorHandler(RingbufAndDescriptorHandler);


    Clock clkQpcMrPgtSrv <- exposeCurrentClock;
    Reset rstQpcMrPgtSrv <- exposeCurrentReset;

    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufH2cSlot4096) wqeRingbufVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufC2hSlot4096) rqMetaReportRingbufVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, WorkQueueDescParser) workQueueDescParserVec <- replicateM(mkWorkQueueDescParser);
    CommandQueueDescParserAndDispatcher cmdQueueDescParserAndDispatcher <- mkCommandQueueDescParserAndDispatcher(clkQpcMrPgtSrv, rstQpcMrPgtSrv);

    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(WorkQueueElem)) wqePipeOutVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufDmaIfcConvertor) qpRingbufDmaIfcConvertorVec <- replicateM(mkRingbufDmaIfcConvertor);
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe) qpRingbufDmaMasterPipeIfcVecInst = newVector;

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        wqeRingbufVec[idx] <- mkRingbufH2c(fromInteger(idx));
        rqMetaReportRingbufVec[idx] <- mkRingbufC2h(fromInteger(idx));
        mkConnection(wqeRingbufVec[idx].descPipeOut, workQueueDescParserVec[idx].rawDescPipeIn);
        wqePipeOutVecInst[idx] = workQueueDescParserVec[idx].workReqPipeOut;

        mkConnection(wqeRingbufVec[idx].dmaReadReqPipeOut, qpRingbufDmaIfcConvertorVec[idx].dmaReadReqPipeIn);
        mkConnection(wqeRingbufVec[idx].dmaReadRespPipeIn, qpRingbufDmaIfcConvertorVec[idx].dmaReadRespPipeOut);
        mkConnection(rqMetaReportRingbufVec[idx].dmaWriteReqPipeOut, qpRingbufDmaIfcConvertorVec[idx].dmaWriteReqPipeIn);
        mkConnection(rqMetaReportRingbufVec[idx].dmaWriteDataPipeOut, qpRingbufDmaIfcConvertorVec[idx].dmaWriteDataPipeIn);
        mkConnection(rqMetaReportRingbufVec[idx].dmaWriteRespPipeIn, qpRingbufDmaIfcConvertorVec[idx].dmaWriteRespPipeOut);
        qpRingbufDmaMasterPipeIfcVecInst[idx] = qpRingbufDmaIfcConvertorVec[idx].dmaMasterPipeIfc;
    end
    
    RingbufH2cSlot4096 cmdReqQueueRingbuf <- mkRingbufH2c(4);
    RingbufC2hSlot4096 cmdRespQueueRingbuf <- mkRingbufC2h(4);
    RingbufDmaIfcConvertor cmdQueueRingbufDmaIfcConvertor <- mkRingbufDmaIfcConvertor;

    mkConnection(cmdReqQueueRingbuf.descPipeOut, cmdQueueDescParserAndDispatcher.reqRawDescPipeIn);
    mkConnection(cmdRespQueueRingbuf.descPipeIn, cmdQueueDescParserAndDispatcher.respRawDescPipeOut);

    mkConnection(cmdReqQueueRingbuf.dmaReadReqPipeOut, cmdQueueRingbufDmaIfcConvertor.dmaReadReqPipeIn);
    mkConnection(cmdReqQueueRingbuf.dmaReadRespPipeIn, cmdQueueRingbufDmaIfcConvertor.dmaReadRespPipeOut);
    mkConnection(cmdRespQueueRingbuf.dmaWriteReqPipeOut, cmdQueueRingbufDmaIfcConvertor.dmaWriteReqPipeIn);
    mkConnection(cmdRespQueueRingbuf.dmaWriteDataPipeOut, cmdQueueRingbufDmaIfcConvertor.dmaWriteDataPipeIn);
    mkConnection(cmdRespQueueRingbuf.dmaWriteRespPipeIn, cmdQueueRingbufDmaIfcConvertor.dmaWriteRespPipeOut);


    function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
        actionvalue
            $display("aaaaa=", fshow(req));
            if (req.isWrite) begin
                case (req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM))
                    // QP ring bufs
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbufVec[0].controlRegs.addr;
                        t[31:0] = req.value;
                        wqeRingbufVec[0].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbufVec[0].controlRegs.addr;
                        t[63:32] = req.value;
                        wqeRingbufVec[0].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[0].controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[0].controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbufVec[0].controlRegs.addr;
                        t[31:0] = req.value;
                        rqMetaReportRingbufVec[0].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbufVec[0].controlRegs.addr;
                        t[63:32] = req.value;
                        rqMetaReportRingbufVec[0].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbufVec[0].controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbufVec[0].controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbufVec[1].controlRegs.addr;
                        t[31:0] = req.value;
                        wqeRingbufVec[1].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbufVec[1].controlRegs.addr;
                        t[63:32] = req.value;
                        wqeRingbufVec[1].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[1].controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[1].controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbufVec[1].controlRegs.addr;
                        t[31:0] = req.value;
                        rqMetaReportRingbufVec[1].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbufVec[1].controlRegs.addr;
                        t[63:32] = req.value;
                        rqMetaReportRingbufVec[1].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbufVec[1].controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbufVec[1].controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbufVec[2].controlRegs.addr;
                        t[31:0] = req.value;
                        wqeRingbufVec[2].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbufVec[2].controlRegs.addr;
                        t[63:32] = req.value;
                        wqeRingbufVec[2].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[2].controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[2].controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbufVec[2].controlRegs.addr;
                        t[31:0] = req.value;
                        rqMetaReportRingbufVec[2].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbufVec[2].controlRegs.addr;
                        t[63:32] = req.value;
                        rqMetaReportRingbufVec[2].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbufVec[2].controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbufVec[2].controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbufVec[2].controlRegs.addr;
                        t[31:0] = req.value;
                        wqeRingbufVec[2].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbufVec[2].controlRegs.addr;
                        t[63:32] = req.value;
                        wqeRingbufVec[2].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[2].controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[2].controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbufVec[3].controlRegs.addr;
                        t[31:0] = req.value;
                        rqMetaReportRingbufVec[3].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = rqMetaReportRingbufVec[3].controlRegs.addr;
                        t[63:32] = req.value;
                        rqMetaReportRingbufVec[3].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbufVec[3].controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        rqMetaReportRingbufVec[3].controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end

                    // Cmd Queue ring bufs
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        let t =cmdReqQueueRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        cmdReqQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        let t = cmdReqQueueRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        cmdReqQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        cmdReqQueueRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        cmdReqQueueRingbuf.controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        let t = cmdRespQueueRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        cmdRespQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        let t = cmdRespQueueRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        cmdRespQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        cmdRespQueueRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        cmdRespQueueRingbuf.controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end

                    default: begin
                        return tagged CsrNodeResultNotMatched;
                    end
                endcase
            end
            else begin
            case (req.addr >> valueOf(BYTE_DWORD_CONVERT_SHIFT_NUM))
                // QP ring bufs
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbufVec[0].controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbufVec[0].controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbufVec[0].controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbufVec[0].controlRegs.tail)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbufVec[0].controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbufVec[0].controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbufVec[0].controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 0 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbufVec[0].controlRegs.tail)))};
                end

                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbufVec[1].controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbufVec[1].controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbufVec[1].controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbufVec[1].controlRegs.tail)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbufVec[1].controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbufVec[1].controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbufVec[1].controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 1 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbufVec[1].controlRegs.tail)))};
                end

                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbufVec[2].controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbufVec[2].controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbufVec[2].controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbufVec[2].controlRegs.tail)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbufVec[2].controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbufVec[2].controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbufVec[2].controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 2 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbufVec[2].controlRegs.tail)))};
                end

                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW)      + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbufVec[3].controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: wqeRingbufVec[3].controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbufVec[3].controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(wqeRingbufVec[3].controlRegs.tail)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW)     + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbufVec[3].controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH)    + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: rqMetaReportRingbufVec[3].controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD)              + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbufVec[3].controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL)              + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(rqMetaReportRingbufVec[3].controlRegs.tail)))};
                end

                //  Cmd Queue ring bufs
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdReqQueueRingbuf.controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdReqQueueRingbuf.controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdReqQueueRingbuf.controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdReqQueueRingbuf.controlRegs.tail)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdRespQueueRingbuf.controlRegs.addr[31:0]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdRespQueueRingbuf.controlRegs.addr[63:32]};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdRespQueueRingbuf.controlRegs.head)))};
                end
                fromInteger(valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                    return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdRespQueueRingbuf.controlRegs.tail)))};
                end
                
                default: begin
                    return tagged CsrNodeResultNotMatched;
                end
            endcase
            end
        endactionvalue
    endfunction
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_TWO));


    interface qpRingbufDmaMasterPipeIfcVec = qpRingbufDmaMasterPipeIfcVecInst;
    interface cmdQueueRingbufDmaMasterPipeIfc = cmdQueueRingbufDmaIfcConvertor.dmaMasterPipeIfc;
    interface csrUpStreamPort = csrNode.upStreamPort;
    
    interface wqePipeOutVec = wqePipeOutVecInst;
    interface mrAndPgtManagerClt = cmdQueueDescParserAndDispatcher.mrAndPgtManagerClt;
    interface qpcModifyClt = cmdQueueDescParserAndDispatcher.qpcModifyClt;
    interface setNetworkParamReqPipeOut = cmdQueueDescParserAndDispatcher.setNetworkParamReqPipeOut;
    
endmodule


interface QpMrPgtQpc;
    // DMA interfaces
    interface IoChannelMemoryMasterPipe pgtUpdateDmaMasterPipe;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)       qpDmaRequestMasterIfcVec;

    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelBiDirStreamNoMetaPipe)  qpEthDataStreamIfcVec;
        
    interface Server#(WriteReqQPC, Bool) qpContextUpdateSrv;
    interface Server#(RingbufRawDescriptor, Bool) mrAndPgtModifyDescSrv;
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
    MrAndPgtUpdater mrAndPgtUpdater <- mkMrAndPgtUpdater(clkQpcMrPgtSrv, rstQpcMrPgtSrv);
    PgtUpdateDmaInterfaceConvertor pgtUpdateDmaInterfaceConvertor <- mkPgtUpdateDmaInterfaceConvertor;


    Vector#(HARDWARE_QP_CHANNEL_CNT, PayloadGenAndCon) payloadGenAndConVec <- replicateM(mkPayloadGenAndCon(clkQpcMrPgtSrv, rstQpcMrPgtSrv, clocked_by clkEthNap, reset_by rstEthNap));
    Vector#(HARDWARE_QP_CHANNEL_CNT, SQ) sqVec <- replicateM(mkSQ(clkQpcMrPgtSrv, rstQpcMrPgtSrv));
    Vector#(HARDWARE_QP_CHANNEL_CNT, RQ) rqVec <- replicateM(mkRQ(clkQpcMrPgtSrv, rstQpcMrPgtSrv));
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVecInst = newVector;

    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)         qpDmaRequestMasterIfcVecInst    = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelBiDirStreamNoMetaPipe)    qpEthDataStreamIfcVecInst       = newVector;
    
    mkConnection(mrAndPgtUpdater.mrModifyClt, mrTable.modifySrv, clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
    mkConnection(mrAndPgtUpdater.pgtModifyClt, addrTranslator.modifySrv, clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
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

    interface pgtUpdateDmaMasterPipe = pgtUpdateDmaInterfaceConvertor.dmaSidePipeIfc;

    interface wqePipeInVec                      = wqePipeInVecInst;
    interface otherRawPacketPipeOutVec          = otherRawPacketPipeOutVecInst;
    interface qpDmaRequestMasterIfcVec          = qpDmaRequestMasterIfcVecInst;
    interface qpEthDataStreamIfcVec             = qpEthDataStreamIfcVecInst;
    interface qpContextUpdateSrv                = qpContext.updateSrv;
    interface qpContextForAutoAckUpdateSrv      = qpContextForAutoAck.updateSrv;
    interface mrAndPgtModifyDescSrv             = mrAndPgtUpdater.mrAndPgtModifyDescSrv;
endmodule