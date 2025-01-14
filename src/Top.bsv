import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
import Vector :: *;
import Clocks :: *;

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
import AutoAckGenerator :: *;
import SimpleNic :: *;
import CnpPacketGen :: *;

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
endinterface


module mkBsvTop#(
        Clock ftileClk,
        Reset ftileRst
    )(BsvTop);

    BsvTopOnlyHardIp            bsvTopOnlyHardIp            <- mkBsvTopOnlyHardIp(ftileClk, ftileRst);
    BsvTopWithoutHardIpInstance bsvTopWithoutHardIpInstance <- mkBsvTopWithoutHardIpInstance;


    mkConnection(bsvTopOnlyHardIp.rtilepcieStreamMasterIfc, bsvTopWithoutHardIpInstance.dmaSlavePipeIfc);
    mkConnection(bsvTopWithoutHardIpInstance.dmaMasterPipeIfcVec, bsvTopOnlyHardIp.rtilepcieStreamSlaveIfcVec);

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(bsvTopOnlyHardIp.ftilemacRxStreamPipeOutVec[idx], bsvTopWithoutHardIpInstance.qpEthDataStreamIfcVec[idx].dataPipeIn);
        mkConnection(bsvTopOnlyHardIp.ftilemacTxStreamPipeInVec[idx], bsvTopWithoutHardIpInstance.qpEthDataStreamIfcVec[idx].dataPipeOut);
    end


    interface rtilePcieAdaptorRxRawIfc  = bsvTopOnlyHardIp.rtilePcieAdaptorRxRawIfc;
    interface rtilePcieAdaptorTxRawIfc  = bsvTopOnlyHardIp.rtilePcieAdaptorTxRawIfc;
    interface ftileMacAdaptorRxRawIfc   = bsvTopOnlyHardIp.ftileMacAdaptorRxRawIfc;
    interface ftileMacAdaptorTxRawIfc   = bsvTopOnlyHardIp.ftileMacAdaptorTxRawIfc;


endmodule


interface BsvTopOnlyHardIp;
    // to verilog side ===================================================
    
    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorRx rtilePcieAdaptorRxRawIfc;
    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorTx rtilePcieAdaptorTxRawIfc;

    (* always_ready, always_enabled *)
    interface FTileMacAdaptorRx ftileMacAdaptorRxRawIfc;
    (* always_ready, always_enabled *)
    interface FTileMacAdaptorTx ftileMacAdaptorTxRawIfc;

    // to bsv side =======================================================

    interface PcieBiDirUserDataStreamMasterPipes                                                rtilepcieStreamMasterIfc;
    interface Vector#(RTILE_PCIE_USER_LOGIC_CHANNEL_CNT, PcieBiDirUserDataStreamSlavePipes)     rtilepcieStreamSlaveIfcVec;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeIn#(FtileMacTxUserStream))          ftilemacTxStreamPipeInVec;
    interface Vector#(FTILE_MAC_USER_LOGIC_CHANNEL_CNT, PipeOut#(FtileMacRxUserStream))         ftilemacRxStreamPipeOutVec;
    
endinterface

(* synthesize *)
module mkBsvTopOnlyHardIp#(
        Clock ftileClk,
        Reset ftileRst
    )(BsvTopOnlyHardIp);
    RTilePcieAdaptor rtilePcieAdaptor   <- mkRTilePcieAdaptor;
    RTilePcie        rtilePcie          <- mkRTilePcie;

    FTileMacAdaptor  ftileMacAdaptor    <- mkFTileMacAdaptor(clocked_by ftileClk, reset_by ftileRst);
    FTileMac         ftileMac           <- mkFTileMac;

    mkConnection(rtilePcieAdaptor.pcieRxPipeOut, rtilePcie.pcieRxPipeIn);
    mkConnection(rtilePcieAdaptor.pcieTxPipeIn, rtilePcie.pcieTxPipeOut);
    mkConnection(rtilePcieAdaptor.rxFlowControlReleaseReqPipeIn, rtilePcie.rxFlowControlReleaseReqPipeOut);
    mkConnection(rtilePcieAdaptor.txFlowControlConsumeReqPipeIn, rtilePcie.txFlowControlConsumeReqPipeOut);
    mkConnection(rtilePcieAdaptor.txFlowControlAvaliablePipeOut, rtilePcie.txFlowControlAvaliablePipeIn);

    SyncFIFOIfc#(FtileMacRxBeat) ftileRxSyncQueue <- mkSyncFIFOToCC(valueOf(NUMERIC_TYPE_FOUR), ftileClk, ftileRst);
    SyncFIFOIfc#(FtileMacTxBeat) ftileTxSyncQueue <- mkSyncFIFOFromCC(valueOf(NUMERIC_TYPE_FOUR), ftileClk);

    mkConnection(ftileMacAdaptor.ftilemacRxPipeOut, toPipeInSync(ftileRxSyncQueue));
    mkConnection(toPipeOutSync(ftileRxSyncQueue), ftileMac.ftilemacRxPipeIn, clocked_by ftileClk, reset_by ftileRst);

    mkConnection(toPipeInSync(ftileTxSyncQueue), ftileMac.ftilemacTxPipeOut);
    mkConnection(ftileMacAdaptor.ftilemacTxPipeIn, toPipeOutSync(ftileTxSyncQueue), clocked_by ftileClk, reset_by ftileRst);

    interface rtilePcieAdaptorRxRawIfc      = rtilePcieAdaptor.rx;
    interface rtilePcieAdaptorTxRawIfc      = rtilePcieAdaptor.tx;
    interface ftileMacAdaptorRxRawIfc       = ftileMacAdaptor.rx;
    interface ftileMacAdaptorTxRawIfc       = ftileMacAdaptor.tx;

    interface rtilepcieStreamMasterIfc      = rtilePcie.streamMasterIfc;
    interface rtilepcieStreamSlaveIfcVec    = rtilePcie.streamSlaveIfcVec;
    interface ftilemacTxStreamPipeInVec     = ftileMac.ftilemacTxStreamPipeInVec;
    interface ftilemacRxStreamPipeOutVec    = ftileMac.ftilemacRxStreamPipeOutVec;
endmodule


interface TopLevelDmaChannelMux;
    // upstream port
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)   dmaMasterPipeIfcVec;

    // downstream port
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemorySlavePipe)   qpRingbufDmaSlavePipeIfcVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemorySlavePipe)   qpDmaRequestSlaveIfcVec;
    interface IoChannelMemorySlavePipe cmdQueueRingbufDmaSlavePipeIfc;
    interface IoChannelMemorySlavePipe pgtUpdateDmaSlavePipe;
    interface IoChannelMemorySlavePipe simpleNicRingbufDmaSlavePipeIfc;
    interface IoChannelMemorySlavePipe simpleNicPacketDmaSlavePipeIfc;
endinterface

(* synthesize *)
module mkTopLevelDmaChannelMux(TopLevelDmaChannelMux);
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelThreeChannelDmaMux)    muxVector <- replicateM(mkDtldStreamArbiterSlave(256, True));
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)     dmaMasterPipeIfcVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemorySlavePipe)      qpRingbufDmaSlavePipeIfcVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemorySlavePipe)      qpDmaRequestSlaveIfcVecInst = newVector;

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        dmaMasterPipeIfcVecInst[idx] = muxVector[idx].masterIfc;
        qpRingbufDmaSlavePipeIfcVecInst[idx] = muxVector[idx].slaveIfcVec[0];
        qpDmaRequestSlaveIfcVecInst[idx] = muxVector[idx].slaveIfcVec[1];

        rule discardUselessPipeOutSignal;
            if (muxVector[idx].writeSourceChannelIdPipeOut.notEmpty) begin
                muxVector[idx].writeSourceChannelIdPipeOut.deq;
            end
            if (muxVector[idx].readSourceChannelIdPipeOut.notEmpty) begin
                muxVector[idx].readSourceChannelIdPipeOut.deq;
            end
        endrule
    end

    // upstream port
    interface dmaMasterPipeIfcVec = dmaMasterPipeIfcVecInst;

    // downstream port
    interface qpRingbufDmaSlavePipeIfcVec = qpRingbufDmaSlavePipeIfcVecInst;
    interface qpDmaRequestSlaveIfcVec = qpDmaRequestSlaveIfcVecInst;
    interface cmdQueueRingbufDmaSlavePipeIfc    = muxVector[0].slaveIfcVec[2]; // use channel 0 for cmd queue.
    interface pgtUpdateDmaSlavePipe             = muxVector[1].slaveIfcVec[2]; // use channel 1 for pgt update.
    interface simpleNicRingbufDmaSlavePipeIfc   = muxVector[2].slaveIfcVec[2]; // use channel 2 for simpleNic descriptor.
    interface simpleNicPacketDmaSlavePipeIfc    = muxVector[3].slaveIfcVec[2]; // use channel 3 for simpleNic payload.
endmodule

interface BsvTopWithoutHardIpInstance;
    interface IoChannelMemorySlavePipe dmaSlavePipeIfc;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)   dmaMasterPipeIfcVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelBiDirStreamNoMetaPipe)  qpEthDataStreamIfcVec;
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
    
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_TWO), "mkBsvTopWithoutHardIpInstance");
    mkConnection(csrRootConnector.csrNodeRootPortIfc, csrNode.upStreamPort);
    mkConnection(ringbufAndDescriptorHandler.csrUpStreamPort, csrNode.downStreamPortsVec[0]);


    mkConnection(qpMrPgtQpc.pgtUpdateDmaMasterPipe, topLevelDmaChannelMux.pgtUpdateDmaSlavePipe);
    mkConnection(qpMrPgtQpc.qpDmaRequestMasterIfcVec, topLevelDmaChannelMux.qpDmaRequestSlaveIfcVec);
    mkConnection(ringbufAndDescriptorHandler.qpRingbufDmaMasterPipeIfcVec, topLevelDmaChannelMux.qpRingbufDmaSlavePipeIfcVec);
    mkConnection(ringbufAndDescriptorHandler.cmdQueueRingbufDmaMasterPipeIfc, topLevelDmaChannelMux.cmdQueueRingbufDmaSlavePipeIfc);
    mkConnection(ringbufAndDescriptorHandler.simpleNicRingbufDmaMasterPipeIfc, topLevelDmaChannelMux.simpleNicRingbufDmaSlavePipeIfc);
    mkConnection(ringbufAndDescriptorHandler.qpResetReqPipeOut, qpMrPgtQpc.qpResetReqPipeIn);
    mkConnection(qpMrPgtQpc.metaReportDescPipeOutVec, ringbufAndDescriptorHandler.metaReportDescPipeInVec);
    mkConnection(ringbufAndDescriptorHandler.mrAndPgtManagerClt, qpMrPgtQpc.mrAndPgtModifyDescSrv);
    mkConnection(ringbufAndDescriptorHandler.qpcModifyClt, qpMrPgtQpc.qpContextUpdateSrv);

    mkConnection(qpMrPgtQpc.simpleNicRxDescPipeOut, ringbufAndDescriptorHandler.simpleNicRxDescPipeIn);
    mkConnection(qpMrPgtQpc.simpleNicTxDescPipeIn, ringbufAndDescriptorHandler.simpleNicTxDescPipeOut);
    mkConnection(qpMrPgtQpc.simpleNicPacketDmaMasterPipeIfc, topLevelDmaChannelMux.simpleNicPacketDmaSlavePipeIfc);
    rule forwardSetNetworkParamReqPipeOut;
        ringbufAndDescriptorHandler.setNetworkParamReqPipeOut.deq;
        qpMrPgtQpc.setLocalNetworkSettings(ringbufAndDescriptorHandler.setNetworkParamReqPipeOut.first);
    endrule
 

    interface dmaSlavePipeIfc = csrRootConnector.dmaSidePipeIfc;
    interface dmaMasterPipeIfcVec = topLevelDmaChannelMux.dmaMasterPipeIfcVec;
    interface qpEthDataStreamIfcVec = qpMrPgtQpc.qpEthDataStreamIfcVec;
endmodule



interface RingbufAndDescriptorHandler;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)   qpRingbufDmaMasterPipeIfcVec;
    interface IoChannelMemoryMasterPipe cmdQueueRingbufDmaMasterPipeIfc;
    interface IoChannelMemoryMasterPipe simpleNicRingbufDmaMasterPipeIfc;
    interface BlueRdmaCsrUpStreamPort csrUpStreamPort;

    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(WorkQueueElem))         wqePipeOutVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(RingbufRawDescriptor))   metaReportDescPipeInVec;

    interface PipeIn#(RingbufRawDescriptor)                                     simpleNicRxDescPipeIn;
    interface PipeOut#(RingbufRawDescriptor)                                    simpleNicTxDescPipeOut;
    
    interface Client#(RingbufRawDescriptor, Bool)                               mrAndPgtManagerClt;
    interface Client#(WriteReqQPC, Bool)                                        qpcModifyClt;
    interface PipeOut#(LocalNetworkSettings)                                    setNetworkParamReqPipeOut;
    interface PipeOut#(IndexQP)                                                 qpResetReqPipeOut;
endinterface

(* synthesize *)
module mkRingbufAndDescriptorHandler(RingbufAndDescriptorHandler);

    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufH2cSlot4096) wqeRingbufVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufC2hSlot4096) rqMetaReportRingbufVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, WorkQueueDescParser) workQueueDescParserVec <- replicateM(mkWorkQueueDescParser);
    CommandQueueDescParserAndDispatcher cmdQueueDescParserAndDispatcher <- mkCommandQueueDescParserAndDispatcher;

    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(WorkQueueElem)) wqePipeOutVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(RingbufRawDescriptor))   metaReportDescPipeInVecInst = newVector;

    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufDmaIfcConvertor) qpRingbufDmaIfcConvertorVec <- replicateM(mkRingbufDmaIfcConvertor);
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe) qpRingbufDmaMasterPipeIfcVecInst = newVector;

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        wqeRingbufVec[idx] <- mkRingbufH2c(fromInteger(idx));
        rqMetaReportRingbufVec[idx] <- mkRingbufC2h(fromInteger(idx));
        mkConnection(wqeRingbufVec[idx].descPipeOut, workQueueDescParserVec[idx].rawDescPipeIn);
        wqePipeOutVecInst[idx] = workQueueDescParserVec[idx].workReqPipeOut;
        metaReportDescPipeInVecInst[idx] = rqMetaReportRingbufVec[idx].descPipeIn;

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


    RingbufH2cSlot4096 simpleNicTxQueueRingbuf <- mkRingbufH2c(4);
    RingbufC2hSlot4096 simpleNicRxQueueRingbuf <- mkRingbufC2h(4);
    RingbufDmaIfcConvertor simpleNicRingbufDmaIfcConvertor <- mkRingbufDmaIfcConvertor;

    mkConnection(simpleNicTxQueueRingbuf.dmaReadReqPipeOut, simpleNicRingbufDmaIfcConvertor.dmaReadReqPipeIn);
    mkConnection(simpleNicTxQueueRingbuf.dmaReadRespPipeIn, simpleNicRingbufDmaIfcConvertor.dmaReadRespPipeOut);
    mkConnection(simpleNicRxQueueRingbuf.dmaWriteReqPipeOut, simpleNicRingbufDmaIfcConvertor.dmaWriteReqPipeIn);
    mkConnection(simpleNicRxQueueRingbuf.dmaWriteDataPipeOut, simpleNicRingbufDmaIfcConvertor.dmaWriteDataPipeIn);
    mkConnection(simpleNicRxQueueRingbuf.dmaWriteRespPipeIn, simpleNicRingbufDmaIfcConvertor.dmaWriteRespPipeOut);
    




    function ActionValue#(CsrNodeResultFork8) csrMatchFunc(CsrAccessReq req);
        actionvalue
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
                        let t = wqeRingbufVec[3].controlRegs.addr;
                        t[31:0] = req.value;
                        wqeRingbufVec[3].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH)     + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        let t = wqeRingbufVec[3].controlRegs.addr;
                        t[63:32] = req.value;
                        wqeRingbufVec[3].controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD)               + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[3].controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL)               + 3 * valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_QP)): begin
                        wqeRingbufVec[3].controlRegs.tail <= unpack(truncate(req.value));
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

                    // Simple NIC Ringbuf
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        let t =simpleNicTxQueueRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        simpleNicTxQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        let t = simpleNicTxQueueRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        simpleNicTxQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        simpleNicTxQueueRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        simpleNicTxQueueRingbuf.controlRegs.tail <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        let t = simpleNicRxQueueRingbuf.controlRegs.addr;
                        t[31:0] = req.value;
                        simpleNicRxQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        let t = simpleNicRxQueueRingbuf.controlRegs.addr;
                        t[63:32] = req.value;
                        simpleNicRxQueueRingbuf.controlRegs.addr <= t;
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        simpleNicRxQueueRingbuf.controlRegs.head <= unpack(truncate(req.value));
                        return tagged CsrNodeResultWriteHandled;
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        simpleNicRxQueueRingbuf.controlRegs.tail <= unpack(truncate(req.value));
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
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdReqQueueRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdReqQueueRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdReqQueueRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdReqQueueRingbuf.controlRegs.tail)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdRespQueueRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: cmdRespQueueRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdRespQueueRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_CMDQ)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(cmdRespQueueRingbuf.controlRegs.tail)))};
                    end
                    
                    // Simple NIC Ringbuf
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: simpleNicTxQueueRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: simpleNicTxQueueRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(simpleNicTxQueueRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_TX_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(simpleNicTxQueueRingbuf.controlRegs.tail)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_BASE_ADDR_LOW) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: simpleNicRxQueueRingbuf.controlRegs.addr[31:0]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_BASE_ADDR_HIGH) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: simpleNicRxQueueRingbuf.controlRegs.addr[63:32]};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_HEAD) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(simpleNicRxQueueRingbuf.controlRegs.head)))};
                    end
                    fromInteger(valueOf(CSR_ADDR_OFFSET_SIMPLE_NIC_RX_Q_RINGBUF_TAIL) + valueOf(CSR_ADDR_BLOCK_START_ADDR_FOR_SIMPLE_NIC)): begin
                        return tagged CsrNodeResultReadHandled CsrReadWriteResp {value: unpack(zeroExtend(pack(simpleNicRxQueueRingbuf.controlRegs.tail)))};
                    end
                    default: begin
                        return tagged CsrNodeResultNotMatched;
                    end
                endcase
            end
        endactionvalue
    endfunction
    CsrNodeFork8 csrNode <- mkCsrNode(csrMatchFunc, valueOf(NUMERIC_TYPE_TWO), "mkRingbufAndDescriptorHandler");


    interface qpRingbufDmaMasterPipeIfcVec = qpRingbufDmaMasterPipeIfcVecInst;
    interface cmdQueueRingbufDmaMasterPipeIfc = cmdQueueRingbufDmaIfcConvertor.dmaMasterPipeIfc;
    interface simpleNicRingbufDmaMasterPipeIfc = simpleNicRingbufDmaIfcConvertor.dmaMasterPipeIfc;
    interface csrUpStreamPort = csrNode.upStreamPort;
    
    interface wqePipeOutVec = wqePipeOutVecInst;
    interface metaReportDescPipeInVec = metaReportDescPipeInVecInst;

    interface simpleNicRxDescPipeIn = simpleNicRxQueueRingbuf.descPipeIn;
    interface simpleNicTxDescPipeOut = simpleNicTxQueueRingbuf.descPipeOut;

    interface mrAndPgtManagerClt = cmdQueueDescParserAndDispatcher.mrAndPgtManagerClt;
    interface qpcModifyClt = cmdQueueDescParserAndDispatcher.qpcModifyClt;
    interface setNetworkParamReqPipeOut = cmdQueueDescParserAndDispatcher.setNetworkParamReqPipeOut;
    interface qpResetReqPipeOut = cmdQueueDescParserAndDispatcher.qpResetReqPipeOut;
endmodule


interface QpMrPgtQpc;
    // DMA interfaces
    interface IoChannelMemoryMasterPipe pgtUpdateDmaMasterPipe;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)       qpDmaRequestMasterIfcVec;
    interface IoChannelMemoryMasterPipe                                         simpleNicPacketDmaMasterPipeIfc;

    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(RingbufRawDescriptor)) metaReportDescPipeOutVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelBiDirStreamNoMetaPipe)  qpEthDataStreamIfcVec;

    interface PipeOut#(RingbufRawDescriptor)                                     simpleNicRxDescPipeOut;
    interface PipeIn#(RingbufRawDescriptor)                                      simpleNicTxDescPipeIn;

    interface PipeIn#(IndexQP) qpResetReqPipeIn;
        
    interface Server#(WriteReqQPC, Bool) qpContextUpdateSrv;
    interface Server#(RingbufRawDescriptor, Bool) mrAndPgtModifyDescSrv;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface



(* synthesize *)
module mkQpMrPgtQpc(QpMrPgtQpc);
    FIFOF#(WriteReqQPC) qpContextUpdateReqQueue <- mkFIFOF;
    FIFOF#(Bool) qpContextUpdateRespQueue <- mkFIFOF;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(RingbufRawDescriptor)) metaReportDescPipeOutVecInst = newVector;

    QpContextFourWayQuery qpContext <- mkQpContextFourWayQuery;
    MemRegionTableEightWayQuery mrTable <- mkMemRegionTableEightWayQuery;
    AddressTranslateEightWayQuery addrTranslator <- mkAddressTranslateEightWayQuery;
    MrAndPgtUpdater mrAndPgtUpdater <- mkMrAndPgtUpdater;
    PgtUpdateDmaInterfaceConvertor pgtUpdateDmaInterfaceConvertor <- mkPgtUpdateDmaInterfaceConvertor;
    AutoAckGenerator    autoAckGenerator <- mkAutoAckGenerator;
    SimpleNic simpleNic <- mkSimpleNic;
    CnpPacketGenerator cnpPacketGenerator <- mkCnpPacketGenerator;

    Vector#(HARDWARE_QP_CHANNEL_CNT, PayloadGenAndCon) payloadGenAndConVec <- replicateM(mkPayloadGenAndCon);
    Vector#(HARDWARE_QP_CHANNEL_CNT, SQ) sqVec <- replicateM(mkSQ);
    Vector#(HARDWARE_QP_CHANNEL_CNT, RQ) rqVec <- replicateM(mkRQ);
    Vector#(HARDWARE_QP_CHANNEL_CNT, DtldStreamNoMetaArbiterSlave#(NUMERIC_TYPE_THREE, DATA)) ethTxStreamArbiterVec <- replicateM(mkDtldStreamNoMetaArbiterSlave(valueOf(NUMERIC_TYPE_THREE)));
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeIn#(WorkQueueElem)) wqePipeInVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, DescriptorMux) descriptorMuxVec <- replicateM(mkDescriptorMux);


    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryMasterPipe)         qpDmaRequestMasterIfcVecInst    = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelBiDirStreamNoMetaPipe)    qpEthDataStreamIfcVecInst       = newVector;

    mkConnection(mrAndPgtUpdater.dmaReadReqPipeOut, pgtUpdateDmaInterfaceConvertor.dmaReadReqPipeIn);
    mkConnection(mrAndPgtUpdater.dmaReadRespPipeIn, pgtUpdateDmaInterfaceConvertor.dmaReadRespPipeOut);    
    mkConnection(mrAndPgtUpdater.mrModifyClt, mrTable.modifySrv);
    mkConnection(mrAndPgtUpdater.pgtModifyClt, addrTranslator.modifySrv);

    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        // Payload gen and con
        mkConnection(sqVec[idx].payloadGenReqPipeOut, payloadGenAndConVec[idx].genReqPipeIn);
        mkConnection(sqVec[idx].payloadGenRespPipeIn, payloadGenAndConVec[idx].payloadGenStreamPipeOut);

        mkConnection(rqVec[idx].payloadConReqPipeOut, payloadGenAndConVec[idx].conReqPipeIn);
        mkConnection(rqVec[idx].payloadConRespPipeIn, payloadGenAndConVec[idx].conRespPipeOut);
        mkConnection(rqVec[idx].payloadConStreamPipeOut, payloadGenAndConVec[idx].payloadConStreamPipeIn);

        // ethernet ifc
        mkConnection(sqVec[idx].packetPipeOut, ethTxStreamArbiterVec[idx].pipeInIfcVec[0]);
        qpEthDataStreamIfcVecInst[idx] = (
                interface DtldStreamNoMetaBiDirPipes
                    interface dataPipeIn = rqVec[idx].ethernetFramePipeIn;
                    interface dataPipeOut = ethTxStreamArbiterVec[idx].pipeOutIfc;
                endinterface
            );


        // QPContext, MR Table and PGT
        mkConnection(rqVec[idx].qpcQueryClt, qpContext.querySrvVec[idx]);

        mkConnection(sqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2]);
        mkConnection(rqVec[idx].mrTableQueryClt, mrTable.querySrvVec[idx * 2 + 1]);

        mkConnection(payloadGenAndConVec[idx].genAddrTranslateClt, addrTranslator.querySrvVec[idx * 2]);
        mkConnection(payloadGenAndConVec[idx].conAddrTranslateClt, addrTranslator.querySrvVec[idx * 2 + 1]);

        // Simple Nic Packet input
        mkConnection(rqVec[idx].otherRawPacketPipeOut, simpleNic.rawEthernetPacketPipeInVec[idx]);

        // auto ack, bitmap report and CNP
        mkConnection(rqVec[idx].autoAckGenReqPipeOut, autoAckGenerator.reqPipeInVec[idx]);
        mkConnection(rqVec[idx].genCnpReqPipeOut, cnpPacketGenerator.genReqPipeInVec[idx]);
        mkConnection(cnpPacketGenerator.cnpEthPacketPipeOutVec[idx], ethTxStreamArbiterVec[idx].pipeInIfcVec[1]);

        // meta report descriptors
        mkConnection(rqVec[idx].metaReportDescPipeOut, descriptorMuxVec[idx].descPipeInVec[0]);
        metaReportDescPipeOutVecInst[idx] = descriptorMuxVec[idx].descPipeOut;

        // RDMA payload DMA Ifc
        qpDmaRequestMasterIfcVecInst[idx] = payloadGenAndConVec[idx].ioChannelMemoryMasterPipeIfc;
    
        // IO interface 
        wqePipeInVecInst[idx]               = sqVec[idx].wqePipeIn;

        rule deqNotused;
            ethTxStreamArbiterVec[idx].sourceChannelIdPipeOut.deq;
        endrule
    end

    // other meta report desc related connection
    // since after bitmap merge, four channel becomes two channel, and background loop tooks another channel
    // to simpilify design, we won't dispatch them evenly.
    mkConnection(autoAckGenerator.metaReportDescPipeOutVec[0], descriptorMuxVec[0].descPipeInVec[1]);
    mkConnection(autoAckGenerator.metaReportDescPipeOutVec[1], descriptorMuxVec[1].descPipeInVec[1]);
    mkConnection(autoAckGenerator.metaReportDescPipeOutVec[2], descriptorMuxVec[2].descPipeInVec[1]);

    // Ethernet Tx channel 0 will handle simple Nic's traffic. Tx channel 1 and 2 will handle auto ack traffic. It may lead to unbalance between other channels.
    mkConnection(simpleNic.rawEthernetPacketPipeOut         , ethTxStreamArbiterVec[0].pipeInIfcVec[2]);
    mkConnection(autoAckGenerator.ackEthPacketPipeOutVec[0] , ethTxStreamArbiterVec[1].pipeInIfcVec[2]);
    mkConnection(autoAckGenerator.ackEthPacketPipeOutVec[1] , ethTxStreamArbiterVec[2].pipeInIfcVec[2]);

    
    
    rule forwardQpContextUpdateReq;
        let req = qpContextUpdateReqQueue.first;
        qpContextUpdateReqQueue.deq;
        qpContext.updateSrv.request.put(req);
        autoAckGenerator.qpcUpdateSrv.request.put(req);
    endrule
    
    rule forwardQpContextUpdateResp;
        let r1 <- qpContext.updateSrv.response.get;
        let r2 <-autoAckGenerator.qpcUpdateSrv.response.get;
        qpContextUpdateRespQueue.enq(r1 && r2);
    endrule

    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
        for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            sqVec[idx].setLocalNetworkSettings(networkSettings);
            rqVec[idx].setLocalNetworkSettings(networkSettings);
        end
        autoAckGenerator.setLocalNetworkSettings(networkSettings);
        cnpPacketGenerator.setLocalNetworkSettings(networkSettings);
    endmethod

    interface pgtUpdateDmaMasterPipe            = pgtUpdateDmaInterfaceConvertor.dmaSidePipeIfc;
    interface wqePipeInVec                      = wqePipeInVecInst;
    interface metaReportDescPipeOutVec          = metaReportDescPipeOutVecInst;
    interface qpDmaRequestMasterIfcVec          = qpDmaRequestMasterIfcVecInst;
    interface qpEthDataStreamIfcVec             = qpEthDataStreamIfcVecInst;
    interface qpContextUpdateSrv                = toGPServer(qpContextUpdateReqQueue, qpContextUpdateRespQueue);

    interface simpleNicRxDescPipeOut            = simpleNic.simpleNicRxDescPipeOut;
    interface simpleNicTxDescPipeIn             = simpleNic.simpleNicTxDescPipeIn;

    interface qpResetReqPipeIn                  = autoAckGenerator.resetReqPipeIn;
    interface mrAndPgtModifyDescSrv             = mrAndPgtUpdater.mrAndPgtModifyDescSrv;

    interface simpleNicPacketDmaMasterPipeIfc   = simpleNic.simpleNicPacketDmaMasterPipeIfc;
endmodule
