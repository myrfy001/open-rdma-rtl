import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import GetPut :: *;
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
import CsrFramework :: *;
import CsrNapConnector :: *;
import BluerdmaConsts :: *;
import DescriptorParsers :: *;

interface BsvTop;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream)) otherRawPacketPipeOutVec;
endinterface


module mkBsvTop#(
        Clock clkEthNap,
        Reset rstEthNap,
        Clock clkQpcMrPgtSrv,
        Reset rstQpcMrPgtSrv
    )(BsvTop);

    let qpMrPgtQpc <- mkQpMrPgtQpc(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv);



    // Ringbuf and it's NAPs
    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufH2cSlot4096) wqeRingbufVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufC2hSlot4096) rqMetaReportRingbufVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, RingbufDmaNapWrappr) ringbufDmaNapVec <- replicateM(mkRingbufDmaNapWrappr);

    Vector#(HARDWARE_QP_CHANNEL_CNT, WorkQueueDescParser) workQueueDescParserVec <- replicateM(mkWorkQueueDescParser);
    CommandQueueDescParserAndDispatcher cmdQueueDescParserAndDispatcher <- mkCommandQueueDescParserAndDispatcher(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv);
    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        wqeRingbufVec[idx] <- mkRingbufH2c(fromInteger(idx));
        rqMetaReportRingbufVec[idx] <- mkRingbufC2h(fromInteger(idx));

        mkConnection(rqMetaReportRingbufVec[idx].dmaWriteReqPipeOut, ringbufDmaNapVec[idx].dmaWriteReqPipeIn);
        mkConnection(rqMetaReportRingbufVec[idx].dmaWriteDataPipeOut, ringbufDmaNapVec[idx].dmaWriteDataPipeIn);
        mkConnection(rqMetaReportRingbufVec[idx].dmaWriteRespPipeIn, ringbufDmaNapVec[idx].dmaWriteRespPipeOut);
        mkConnection(wqeRingbufVec[idx].dmaReadReqPipeOut, ringbufDmaNapVec[idx].dmaReadReqPipeIn);
        mkConnection(wqeRingbufVec[idx].dmaReadRespPipeIn, ringbufDmaNapVec[idx].dmaReadRespPipeOut);

        mkConnection(wqeRingbufVec[idx].descPipeOut, workQueueDescParserVec[idx].rawDescPipeIn);
        mkConnection(workQueueDescParserVec[idx].workReqPipeOut, qpMrPgtQpc.wqePipeInVec[idx]);
    end

    RingbufH2cSlot4096 cmdReqQueueRingbuf <- mkRingbufH2c(4);
    RingbufC2hSlot4096 cmdRespQueueRingbuf <- mkRingbufC2h(4);
    RingbufDmaNapWrappr cmdQueueRingbufDmaNap <- mkRingbufDmaNapWrappr;

    mkConnection(cmdRespQueueRingbuf.dmaWriteReqPipeOut, cmdQueueRingbufDmaNap.dmaWriteReqPipeIn);
    mkConnection(cmdRespQueueRingbuf.dmaWriteDataPipeOut, cmdQueueRingbufDmaNap.dmaWriteDataPipeIn);
    mkConnection(cmdRespQueueRingbuf.dmaWriteRespPipeIn, cmdQueueRingbufDmaNap.dmaWriteRespPipeOut);
    mkConnection(cmdReqQueueRingbuf.dmaReadReqPipeOut, cmdQueueRingbufDmaNap.dmaReadReqPipeIn);
    mkConnection(cmdReqQueueRingbuf.dmaReadRespPipeIn, cmdQueueRingbufDmaNap.dmaReadRespPipeOut);



    // CSR Access
    RdmaCsrSwitch#(40) csrRootSwitch <- mkCsrRootSwitch;
    Integer blockOffset = 0;
    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        blockOffset = valueOf(ASR_ADDR_BLOCK_START_ADDR_FOR_QP) + valueOf(CSR_ADDR_BLOCK_SIZE_FOR_EACH_QP) * idx;

        RdmaCsrLeafAccessor csrAccessorSqBaseAddrLow    <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_LOW));
        RdmaCsrLeafAccessor csrAccessorSqBaseAddrHigh   <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_BASE_ADDR_HIGH));
        RdmaCsrLeafAccessor csrAccessorSqHead           <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_HEAD));
        RdmaCsrLeafAccessor csrAccessorSqTail           <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_WQE_RINGBUF_TAIL));

        RdmaCsrLeafAccessor csrAccessorRqBaseAddrLow    <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_LOW));
        RdmaCsrLeafAccessor csrAccessorRqBaseAddrHigh   <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_BASE_ADDR_HIGH));
        RdmaCsrLeafAccessor csrAccessorRqHead           <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_HEAD));
        RdmaCsrLeafAccessor csrAccessorRqTail           <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_RECV_RINGBUF_TAIL));

        mkConnection(csrAccessorSqBaseAddrLow.busInputSrv, csrRootSwitch.busOutputCltVecIfc[idx * 8 + 0]);
        mkConnection(csrAccessorSqBaseAddrHigh.busInputSrv, csrRootSwitch.busOutputCltVecIfc[idx * 8 + 1]);
        mkConnection(csrAccessorSqHead.busInputSrv, csrRootSwitch.busOutputCltVecIfc[idx * 8 + 2]);
        mkConnection(csrAccessorSqTail.busInputSrv, csrRootSwitch.busOutputCltVecIfc[idx * 8 + 3]);

        mkConnection(csrAccessorRqBaseAddrLow.busInputSrv, csrRootSwitch.busOutputCltVecIfc[idx * 8 + 4]);
        mkConnection(csrAccessorRqBaseAddrHigh.busInputSrv, csrRootSwitch.busOutputCltVecIfc[idx * 8 + 5]);
        mkConnection(csrAccessorRqHead.busInputSrv, csrRootSwitch.busOutputCltVecIfc[idx * 8 + 6]);
        mkConnection(csrAccessorRqTail.busInputSrv, csrRootSwitch.busOutputCltVecIfc[idx * 8 + 7]);


        mkConnectionCsrAccessorAndRingbuf(
            csrAccessorSqBaseAddrLow,
            csrAccessorSqBaseAddrHigh,
            csrAccessorSqHead,
            csrAccessorSqTail,
            wqeRingbufVec[idx].controlRegs
        );

        mkConnectionCsrAccessorAndRingbuf(
            csrAccessorRqBaseAddrLow,
            csrAccessorRqBaseAddrHigh,
            csrAccessorRqHead,
            csrAccessorRqTail,
            rqMetaReportRingbufVec[idx].controlRegs
        );
    end

    blockOffset = valueOf(ASR_ADDR_BLOCK_START_ADDR_FOR_CMDQ);
    RdmaCsrLeafAccessor csrAccessorCmdReqQueueBaseAddrLow    <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_LOW));
    RdmaCsrLeafAccessor csrAccessorCmdReqQueueBaseAddrHigh   <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_BASE_ADDR_HIGH));
    RdmaCsrLeafAccessor csrAccessorCmdReqQueueHead           <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_HEAD));
    RdmaCsrLeafAccessor csrAccessorCmdReqQueueTail           <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_CMD_REQ_Q_RINGBUF_TAIL));

    RdmaCsrLeafAccessor csrAccessorCmdRespQueueBaseAddrLow    <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_LOW));
    RdmaCsrLeafAccessor csrAccessorCmdRespQueueBaseAddrHigh   <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_BASE_ADDR_HIGH));
    RdmaCsrLeafAccessor csrAccessorCmdRespQueueHead           <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_HEAD));
    RdmaCsrLeafAccessor csrAccessorCmdRespQueueTail           <- mkCsrLeafAccessor(blockOffset + valueOf(CSR_ADDR_OFFSET_CMD_RESP_Q_RINGBUF_TAIL));

    Integer cmdQueueCsrSwitchPortBaseIdx = valueOf(HARDWARE_QP_CHANNEL_CNT) * 8;
    mkConnection(csrAccessorCmdReqQueueBaseAddrLow.busInputSrv, csrRootSwitch.busOutputCltVecIfc[cmdQueueCsrSwitchPortBaseIdx + 0]);
    mkConnection(csrAccessorCmdReqQueueBaseAddrHigh.busInputSrv, csrRootSwitch.busOutputCltVecIfc[cmdQueueCsrSwitchPortBaseIdx + 1]);
    mkConnection(csrAccessorCmdReqQueueHead.busInputSrv, csrRootSwitch.busOutputCltVecIfc[cmdQueueCsrSwitchPortBaseIdx + 2]);
    mkConnection(csrAccessorCmdReqQueueTail.busInputSrv, csrRootSwitch.busOutputCltVecIfc[cmdQueueCsrSwitchPortBaseIdx + 3]);
    
    mkConnection(csrAccessorCmdRespQueueBaseAddrLow.busInputSrv, csrRootSwitch.busOutputCltVecIfc[cmdQueueCsrSwitchPortBaseIdx + 4]);
    mkConnection(csrAccessorCmdRespQueueBaseAddrHigh.busInputSrv, csrRootSwitch.busOutputCltVecIfc[cmdQueueCsrSwitchPortBaseIdx + 5]);
    mkConnection(csrAccessorCmdRespQueueHead.busInputSrv, csrRootSwitch.busOutputCltVecIfc[cmdQueueCsrSwitchPortBaseIdx + 6]);
    mkConnection(csrAccessorCmdRespQueueTail.busInputSrv, csrRootSwitch.busOutputCltVecIfc[cmdQueueCsrSwitchPortBaseIdx + 7]);

    mkConnectionCsrAccessorAndRingbuf(
        csrAccessorCmdReqQueueBaseAddrLow,
        csrAccessorCmdReqQueueBaseAddrHigh,
        csrAccessorCmdReqQueueHead,
        csrAccessorCmdReqQueueTail,
        cmdReqQueueRingbuf.controlRegs
    );

    mkConnectionCsrAccessorAndRingbuf(
        csrAccessorCmdRespQueueBaseAddrLow,
        csrAccessorCmdRespQueueBaseAddrHigh,
        csrAccessorCmdRespQueueHead,
        csrAccessorCmdRespQueueTail,
        cmdRespQueueRingbuf.controlRegs
    );

    mkConnection(cmdReqQueueRingbuf.descPipeOut, cmdQueueDescParserAndDispatcher.reqRawDescPipeIn);
    mkConnection(cmdRespQueueRingbuf.descPipeIn, cmdQueueDescParserAndDispatcher.respRawDescPipeOut);

    MrAndPgtUpdater mrAndPgtUpdater <- mkMrAndPgtUpdater(clkQpcMrPgtSrv, rstQpcMrPgtSrv);
    PgtUpdateDmaNapWrappr pgtUpdateDmaNapWrappr <- mkPgtUpdateDmaNapWrappr;

    mkConnection(mrAndPgtUpdater.dmaReadReqPipeOut, pgtUpdateDmaNapWrappr.dmaReadReqPipeIn);
    mkConnection(mrAndPgtUpdater.dmaReadRespPipeIn, pgtUpdateDmaNapWrappr.dmaReadRespPipeOut);

    mkConnection(cmdQueueDescParserAndDispatcher.mrAndPgtManagerClt, mrAndPgtUpdater.mrAndPgtModifyDescSrv);
    mkConnection(mrAndPgtUpdater.mrModifyClt, qpMrPgtQpc.mrTableModifySrv, clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
    mkConnection(mrAndPgtUpdater.pgtModifyClt, qpMrPgtQpc.pgtModifySrv, clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
    mkConnection(cmdQueueDescParserAndDispatcher.qpcModifyClt, qpMrPgtQpc.qpContextUpdateSrv, clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);

    rule setLocalNetworkSettings;
        qpMrPgtQpc.setLocalNetworkSettings(cmdQueueDescParserAndDispatcher.setNetworkParamReqPipeOut.first);
        cmdQueueDescParserAndDispatcher.setNetworkParamReqPipeOut.deq;
    endrule

    interface otherRawPacketPipeOutVec = qpMrPgtQpc.otherRawPacketPipeOutVec; 
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