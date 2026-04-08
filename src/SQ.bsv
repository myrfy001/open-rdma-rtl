import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;

import Vector :: *;


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
import QPContext :: *;
import PacketGenAndParse :: *;
import IoChannels :: *;
import Arbitration :: *;
import FullyPipelineChecker :: *;




interface WqePipeDispatcher#(type nChannel);
    interface PipeIn#(WorkQueueElem)                     pipeIn;
    interface Vector#(nChannel, PipeOut#(WorkQueueElem)) pipeOutVec;
endinterface


module mkWqePipeDispatcher#(Integer bufferDepth)(WqePipeDispatcher#(nChannel)) provisos (
        Add#(a__, TLog#(nChannel), QPN_WIDTH)
    );
    Vector#(nChannel, PipeOut#(WorkQueueElem)) pipeOutVecInst = newVector;
    
    Vector#(nChannel, FIFOF#(WorkQueueElem)) pipeOutQueueVec <- replicateM(mkFIFOF);

    
    FIFOF#(WorkQueueElem) pipeInQueue <- mkSizedFIFOF(bufferDepth);


    for (Integer channelIdx = 0; channelIdx < valueOf(nChannel); channelIdx = channelIdx + 1) begin
        pipeOutVecInst[channelIdx] = toPipeOut(pipeOutQueueVec[channelIdx]);
    end


    rule recvArbitResp;
        let wqe = pipeInQueue.first;
        pipeInQueue.deq;
        Bit#(TLog#(nChannel)) curChannelIdx = truncate(wqe.sqpn);
        pipeOutQueueVec[curChannelIdx].enq(wqe);
    endrule



    interface pipeIn            = toPipeIn(pipeInQueue);
    interface pipeOutVec        = pipeOutVecInst;
endmodule







interface SQ;
    interface PipeInB0#(WorkQueueElem) wqePipeIn;

    interface PipeOut#(ThinMacIpUdpMetaDataForSend) macIpUdpMetaPipeOut;
    interface PipeOut#(RdmaSendPacketMeta)          rdmaPacketMetaPipeOut;
    interface PipeOut#(DataStream)                  rdmaPayloadPipeOut;

    interface ClientP#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryClt;

    interface PipeOut#(PayloadGenReq) payloadGenReqPipeOut;
    interface PipeIn#(DataStream) payloadGenRespPipeIn;
endinterface

(* synthesize *)
module mkSQ(SQ);

    let packetGen <- mkPacketGen;
    
    interface wqePipeIn = packetGen.wqePipeIn;
    
    interface macIpUdpMetaPipeOut = packetGen.macIpUdpMetaPipeOut;
    interface rdmaPacketMetaPipeOut = packetGen.rdmaPacketMetaPipeOut;
    interface rdmaPayloadPipeOut = packetGen.rdmaPayloadPipeOut;

    interface mrTableQueryClt = packetGen.mrTableQueryClt;

    interface payloadGenReqPipeOut = packetGen.genReqPipeOut;
    interface payloadGenRespPipeIn = packetGen.genRespPipeIn;
endmodule


interface SqGroup;

    interface PipeIn#(WorkQueueElem) wqePipeIn;

    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(ThinMacIpUdpMetaDataForSend)) macIpUdpMetaPipeOutVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(RdmaSendPacketMeta))          rdmaPacketMetaPipeOutVec;
    interface Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream))                  rdmaPayloadPipeOutVec;


    interface ClientP#(PgtAddrTranslateReq, ADDR)  pgtQueryCltIfc;
    interface ClientP#(MrTableQueryReq, Maybe#(MemRegionTableEntry))  mrQueryCltIfc;

    interface Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryReadMasterPipe) sqDmaReadRequestMasterIfcVec;

endinterface

(* synthesize *)
module mkSqGroup(SqGroup);
    Vector#(HARDWARE_QP_CHANNEL_CNT, SQ) sqVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PayloadGen) payloadGenVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, IoChannelMemoryReadMasterPipe) sqDmaReadRequestMasterIfcVecInst = newVector;


    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(ThinMacIpUdpMetaDataForSend)) macIpUdpMetaPipeOutVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(RdmaSendPacketMeta))          rdmaPacketMetaPipeOutVecInst = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, PipeOut#(DataStream))                  rdmaPayloadPipeOutVecInst = newVector;



    Vector#(HARDWARE_QP_CHANNEL_CNT, ClientP#(PgtAddrTranslateReq, ADDR)) pgtQueryCltVec = newVector;
    Vector#(HARDWARE_QP_CHANNEL_CNT, ClientP#(MrTableQueryReq, Maybe#(MemRegionTableEntry))) mrQueryCltVec = newVector;

    WqePipeDispatcher#(HARDWARE_QP_CHANNEL_CNT) wqeDispatcher <- mkWqePipeDispatcher(valueOf(NUMERIC_TYPE_SIXTEEN));

    
    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        sqVecInst[idx] <- mkSQ;
        payloadGenVecInst[idx] <- mkPayloadGen;

        pgtQueryCltVec[idx] = payloadGenVecInst[idx].addrTranslateClt;
        mrQueryCltVec[idx] = sqVecInst[idx].mrTableQueryClt;

        macIpUdpMetaPipeOutVecInst[idx] = sqVecInst[idx].macIpUdpMetaPipeOut;
        rdmaPacketMetaPipeOutVecInst[idx] = sqVecInst[idx].rdmaPacketMetaPipeOut;
        rdmaPayloadPipeOutVecInst[idx] = sqVecInst[idx].rdmaPayloadPipeOut;

        mkConnection(wqeDispatcher.pipeOutVec[idx], sqVecInst[idx].wqePipeIn);  // already Nr

         // Payload gen and con
        mkConnection(sqVecInst[idx].payloadGenReqPipeOut, payloadGenVecInst[idx].genReqPipeIn);    // already Nr
        mkConnection(sqVecInst[idx].payloadGenRespPipeIn, payloadGenVecInst[idx].payloadGenStreamPipeOut);

        let payloadGenPipeInB0Convertor <- mkPipeInB0ToPipeIn(payloadGenVecInst[idx].dmaReadMasterPipe.readDataPipeIn, 2);

        sqDmaReadRequestMasterIfcVecInst[idx] = (
            interface DtldStreamMasterReadPipes; 
                interface readMetaPipeOut = payloadGenVecInst[idx].dmaReadMasterPipe.readMetaPipeOut;
                interface readDataPipeIn = payloadGenPipeInB0Convertor;
            endinterface
        );
    end

    function Bool isReqFinishedPGT(PgtAddrTranslateReq request) = True;
    function Bool isRespFinishedPGT(ADDR response) = True;
    ClientP#(PgtAddrTranslateReq, ADDR)  pgtQueryArbiter <- mkClientPArbiter(
        valueOf(NUMERIC_TYPE_TWO),
        pgtQueryCltVec,
        isReqFinishedPGT,
        isRespFinishedPGT,
        DebugConf{name: "pgtQueryArbiter", enableDebug: False}
    );

    function Bool isReqFinishedMR(MrTableQueryReq request) = True;
    function Bool isRespFinishedMR(Maybe#(MemRegionTableEntry) response) = True;
    ClientP#(MrTableQueryReq, Maybe#(MemRegionTableEntry))  mrQueryArbiter <- mkClientPArbiter(
        valueOf(NUMERIC_TYPE_TWO),
        mrQueryCltVec,
        isReqFinishedMR,
        isRespFinishedMR,
        DebugConf{name: "mrQueryArbiter", enableDebug: False}
    );


    interface wqePipeIn = wqeDispatcher.pipeIn;
    interface macIpUdpMetaPipeOutVec = macIpUdpMetaPipeOutVecInst;
    interface rdmaPacketMetaPipeOutVec = rdmaPacketMetaPipeOutVecInst;
    interface rdmaPayloadPipeOutVec = rdmaPayloadPipeOutVecInst;

    interface pgtQueryCltIfc = pgtQueryArbiter;
    interface mrQueryCltIfc = mrQueryArbiter;
    interface sqDmaReadRequestMasterIfcVec = sqDmaReadRequestMasterIfcVecInst;
endmodule