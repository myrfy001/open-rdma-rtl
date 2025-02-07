import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;
import FullyPipelineChecker :: *;

import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;
import AddressChunker :: *;
import EthernetTypes :: *;
import DtldStream :: *;
import IoChannels :: *;


typedef struct {
    ADDR   addr;
    Length len;
    PTEIndex pgtOffset;
    ADDR baseVA;
} PayloadGenReq deriving(Bits, FShow);

typedef struct {
    ADDR            addr;
    Length          len;
    PTEIndex        pgtOffset;
    ADDR            baseVA;
    SimulationTime  fpDebugTime;
} PayloadConReq deriving(Bits, FShow);

typedef IO_CHANNEL_PCIE_MAX_REQ_LENGTH_IN_BYTE                          PAYLOAD_CON_AND_GEN_MAX_BURST_SIZE;
typedef TAdd#(1, TDiv#(MAX_PMTU, PAYLOAD_CON_AND_GEN_MAX_BURST_SIZE))   PAYLOAD_CON_AND_GEN_MAX_BURST_CNT_PER_REQUEST;

typedef TDiv#(PAYLOAD_CON_AND_GEN_MAX_BURST_SIZE, BYTE_CNT_PER_DWOED)   PAYLOAD_CON_AND_GEN_MAX_DWORD_CNT_PER_BURST;
typedef TAdd#(1, TLog#(PAYLOAD_CON_AND_GEN_MAX_DWORD_CNT_PER_BURST))    PAYLOAD_CON_AND_GEN_MAX_DWORD_CNT_PER_BURST_WIDTH;
typedef Bit#(PAYLOAD_CON_AND_GEN_MAX_DWORD_CNT_PER_BURST_WIDTH)         AlignBlockCntInPayloadConAndGenBurst;

interface PayloadGen;
    interface ClientP#(PgtAddrTranslateReq, ADDR) addrTranslateClt;
    interface PipeInB0#(PayloadGenReq) genReqPipeIn;
    interface PipeOut#(IoChannelMemoryAccessDataStream) payloadGenStreamPipeOut;

    interface IoChannelMemoryReadMasterPipeB0In dmaReadMasterPipe;
endinterface

interface PayloadCon;
    interface ClientP#(PgtAddrTranslateReq, ADDR) addrTranslateClt;
    interface PipeInB0#(PayloadConReq) conReqPipeIn;
    interface PipeOut#(Bool) conRespPipeOut;

    interface PipeInB0#(IoChannelMemoryAccessDataStream) payloadConStreamPipeIn;

    interface IoChannelMemoryWriteMasterPipe dmaWriteMasterPipe;
endinterface



interface PayloadGenAndCon;
    interface ClientP#(PgtAddrTranslateReq, ADDR) genAddrTranslateClt;
    interface PipeInB0#(PayloadGenReq) genReqPipeIn;
    interface PipeOut#(IoChannelMemoryAccessDataStream) payloadGenStreamPipeOut;

    interface ClientP#(PgtAddrTranslateReq, ADDR) conAddrTranslateClt;
    interface PipeInB0#(PayloadConReq) conReqPipeIn;
    interface PipeOut#(Bool) conRespPipeOut;
    interface PipeInB0#(IoChannelMemoryAccessDataStream) payloadConStreamPipeIn;

    interface IoChannelMemoryMasterPipeB0In ioChannelMemoryMasterPipeIfc;
endinterface

(* synthesize *)
module mkPayloadGenAndCon(PayloadGenAndCon);

    PayloadGen payloadGen <- mkPayloadGen;
    PayloadCon payloadCon <- mkPayloadCon;

    interface genAddrTranslateClt = payloadGen.addrTranslateClt;
    interface genReqPipeIn = payloadGen.genReqPipeIn;
    interface payloadGenStreamPipeOut = payloadGen.payloadGenStreamPipeOut;

    interface conAddrTranslateClt = payloadCon.addrTranslateClt;
    interface conReqPipeIn = payloadCon.conReqPipeIn;
    interface conRespPipeOut = payloadCon.conRespPipeOut;
    interface payloadConStreamPipeIn = payloadCon.payloadConStreamPipeIn;

    interface IoChannelMemoryMasterPipeB0In ioChannelMemoryMasterPipeIfc;
        interface writePipeIfc  = payloadCon.dmaWriteMasterPipe;
        interface readPipeIfc   = payloadGen.dmaReadMasterPipe;
    endinterface
endmodule

(* synthesize *)
module mkPayloadGen(PayloadGen);

    PipeInAdapterB0#(PayloadGenReq) genReqPipeInQ <- mkPipeInAdapterB0;

    FIFOF#(IoChannelMemoryAccessMeta)        dmaReadReqPipeOutQ   <- mkSizedFIFOF(256);  // Since DMA port is shared by multi module (e.g., WQE desc fetch), we may queue up here. 
    // FIFOF#(IoChannelMemoryAccessDataStream)  dmaReadRespPipeInQ   <- mkSizedFIFOF(2);


    QueuedClientP#(PgtAddrTranslateReq, ADDR) addrTranslateCltInst <- mkQueuedClientPWithDebug("mkPayloadGen addrTranslateCltInst", False);
    AddressChunker#(ADDR, Length, ChunkAlignLogValue) rawReqToBurstChunker <- mkAddressChunker;
    let rawReqToBurstChunkerRequestPipeInAdapter <- mkPipeInB0ToPipeIn(rawReqToBurstChunker.requestPipeIn, 1);

    DtldStreamConcator#(DATA, LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE) dsConcator <- mkDtldStreamConcator;
    // mkConnection(toPipeOut(dmaReadRespPipeInQ), dsConcator.dataPipeIn);

    // rule forwardReadRespToConcator;
    //     let ds = dmaReadRespPipeInQ.first;
    //     dmaReadRespPipeInQ.deq;
    //     dsConcator.dataPipeIn.enq(ds);

    //     // $display(
    //     //     "time=%0t:", $time, toGreen(" mkPayloadGen forwardReadRespToConcator"),
    //     //     toBlue(", ds="), fshow(ds)
    //     // );
    // endrule


    // Pipeline FIFOs
    FIFOF#(Tuple3#(PTEIndex, ADDR, SimulationTime)) getBurstChunRespAndIssueAddrTranslateReqPipelineQ <- mkSizedFIFOF(2);
    FIFOF#(Tuple3#(Length, Bool, SimulationTime)) issueDmaReadPipelineQ <- mkSizedFIFOF(10);


    let dsConcatorIsLastStreamFlagPipeInConverter <- mkPipeInB0ToPipeIn(dsConcator.isLastStreamFlagPipeIn, 256);   // PCIe has max outstanding read req limit (PCIe tag).

    rule printDebugInfo;
        if (!dmaReadReqPipeOutQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ dmaReadReqPipeOutQ");
    endrule


    rule handleInReq;
        let curFpDebugTime <- getSimulationTime;
        let req = genReqPipeInQ.first;
        genReqPipeInQ.deq;

        let chunkReq = AddressChunkReq{
            startAddr: req.addr,
            len: req.len,
            chunk: fromInteger(valueOf(TLog#(IO_CHANNEL_PCIE_MAX_REQ_LENGTH_IN_BYTE)))
        };

        rawReqToBurstChunkerRequestPipeInAdapter.enq(chunkReq);
        getBurstChunRespAndIssueAddrTranslateReqPipelineQ.enq(
            tuple3(req.pgtOffset, req.baseVA, curFpDebugTime));

        $display(
            "time=%0t:", $time, toGreen(" mkPayloadGen handleInReq"),
            toBlue(", req="), fshow(req),
            toBlue(", chunkReq="), fshow(chunkReq)
        );
    endrule

    rule getBurstChunRespAndIssueAddrTranslateReq;
        let curFpDebugTime <- getSimulationTime;
        let burstAddrBoundry = rawReqToBurstChunker.responsePipeOut.first;
        rawReqToBurstChunker.responsePipeOut.deq;

        let {pgtOffset, baseVA, fpDebugTime} = getBurstChunRespAndIssueAddrTranslateReqPipelineQ.first;
        if (burstAddrBoundry.isLast) begin
            getBurstChunRespAndIssueAddrTranslateReqPipelineQ.deq;
        end

        let addrTranslateReq = PgtAddrTranslateReq {
            pgtOffset: pgtOffset,
            baseVA: baseVA,
            addrToTrans: burstAddrBoundry.startAddr
        };
        addrTranslateCltInst.putReq(addrTranslateReq);
        issueDmaReadPipelineQ.enq(tuple3(burstAddrBoundry.len, burstAddrBoundry.isLast, curFpDebugTime));

        $display(
            "time=%0t:", $time, toGreen(" mkPayloadGen getBurstChunRespAndIssueAddrTranslateReq"),
            toBlue(", burstAddrBoundry="), fshow(burstAddrBoundry),
            toBlue(", addrTranslateReq="), fshow(addrTranslateReq)
        );
        checkFullyPipeline(fpDebugTime, 3, 2000, "mkPayloadGen getBurstChunRespAndIssueAddrTranslateReq");
    endrule

    rule issueDmaRead;
        let curFpDebugTime <- getSimulationTime;
        let translatedAddr <- addrTranslateCltInst.getResp;
        let {len, isLast, fpDebugTime} = issueDmaReadPipelineQ.first;
        issueDmaReadPipelineQ.deq;
        
        let readReq = DtldStreamMemAccessMeta {
            addr: translatedAddr,
            totalLen: len
        };
        dmaReadReqPipeOutQ.enq(readReq);
        dsConcatorIsLastStreamFlagPipeInConverter.enq(isLast);

        $display(
            "time=%0t:", $time, toGreen(" mkPayloadGen issueDmaRead"),
            toBlue(", translatedAddr="), fshow(translatedAddr),
            toBlue(", len="), fshow(len),
            toBlue(", isLast="), fshow(isLast)
        );
        checkFullyPipeline(fpDebugTime, 11, 2000, "mkPayloadGen issueDmaRead");
    endrule

    // let fifoToPipeInB0Bridge <- mkFifofToPipeInB0(dmaReadRespPipeInQ);

    interface addrTranslateClt = addrTranslateCltInst.clt;
    interface genReqPipeIn = toPipeInB0(genReqPipeInQ);
    interface payloadGenStreamPipeOut = dsConcator.dataPipeOut;

    interface IoChannelMemoryReadMasterPipeB0In dmaReadMasterPipe;
        interface readMetaPipeOut = toPipeOut(dmaReadReqPipeOutQ);
        interface readDataPipeIn = dsConcator.dataPipeIn;
    endinterface

endmodule


(* synthesize *)
module mkPayloadCon(PayloadCon);

    PipeInAdapterB0#(PayloadConReq) conReqPipeInQ <- mkPipeInAdapterB0;
    PipeInAdapterB0#(IoChannelMemoryAccessDataStream) payloadConStreamPipeInQ <- mkPipeInAdapterB0;
    FIFOF#(Bool) conRespPipeOutQ <- mkFIFOF;  // TODO: maybe need to be sized fifo

    FIFOF#(IoChannelMemoryAccessMeta)       dmaWriteReqAddrPipeOutQ <- mkSizedFIFOF(valueOf(PAYLOAD_STORAGE_CAPACITY_FOR_RQ_OUTPUT_DMA_DATA_STREAM_BUF));
    FIFOF#(IoChannelMemoryAccessDataStream) dmaWriteReqDataPipeOutQ <- mkSizedFIFOF(valueOf(PAYLOAD_STORAGE_CAPACITY_FOR_RQ_OUTPUT_DMA_DATA_STREAM_BUF));


    QueuedClientP#(PgtAddrTranslateReq, ADDR) addrTranslateCltInst <- mkQueuedClientPWithDebug("mkPayloadCon addrTranslateCltInst", False);
    AddressChunker#(ADDR, Length, ChunkAlignLogValue) rawReqToBurstChunker <- mkAddressChunker;
    let rawReqToBurstChunkerRequestPipeInAdapter <- mkPipeInB0ToPipeIn(rawReqToBurstChunker.requestPipeIn, 1);

    DtldStreamSplitor#(DATA, AlignBlockCntInPayloadConAndGenBurst, LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE) dsSpliter <- mkDtldStreamSplitor;

    FIFOF#(Tuple3#(PTEIndex, ADDR, SimulationTime)) getBurstChunRespAndIssueAddrTranslateReqPipelineQ <- mkSizedFIFOF(2);  // Pipeline Fifo for forked path, so at least 2
    FIFOF#(Tuple2#(Length, SimulationTime)) issueDmaWritePipelineQ <- mkSizedFIFOF(3);
    FIFOF#(Tuple3#(Length, Length, SimulationTime)) streamSplitorMetaCalcPipelineQ <- mkLFIFOF;

    let dsSpliterStreamAlignBlockCountPipeInConverter <- mkPipeInB0ToPipeInWithDebug(dsSpliter.streamAlignBlockCountPipeIn, 1, False, "dsSpliterStreamAlignBlockCountPipeInConverter");
    let dsSpliterDataPipeInConverter <- mkPipeInB0ToPipeInWithDebug(dsSpliter.dataPipeIn, 2, False, "dsSpliterDataPipeInConverter");


    rule printDebugInfo;
        if (!conRespPipeOutQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkPayloadCon conRespPipeOutQ");
    endrule

    
    rule handleInReq;
        let curFpDebugTime <- getSimulationTime;
        let req = conReqPipeInQ.first;
        conReqPipeInQ.deq;

        let chunkReq = AddressChunkReq{
            startAddr: req.addr,
            len: req.len,
            chunk: fromInteger(valueOf(TLog#(IO_CHANNEL_PCIE_MAX_REQ_LENGTH_IN_BYTE)))
        };

        rawReqToBurstChunkerRequestPipeInAdapter.enq(chunkReq);
        getBurstChunRespAndIssueAddrTranslateReqPipelineQ.enq(
            tuple3(req.pgtOffset, req.baseVA, curFpDebugTime));
        $display(
            "time=%0t:", $time, toGreen(" mkPayloadCon handleInReq"),
            toBlue(", req="), fshow(req),
            toBlue(", chunkReq="), fshow(chunkReq)
        );
        checkFullyPipeline(req.fpDebugTime, 1, 2000, "mkPayloadCon handleInReq");
    endrule

    rule getBurstChunRespAndIssueAddrTranslateReq;
        let curFpDebugTime <- getSimulationTime;
        let burstAddrBoundry = rawReqToBurstChunker.responsePipeOut.first;
        rawReqToBurstChunker.responsePipeOut.deq;

        let {pgtOffset, baseVA, fpDebugTime} = getBurstChunRespAndIssueAddrTranslateReqPipelineQ.first;
        if (burstAddrBoundry.isLast) begin
            getBurstChunRespAndIssueAddrTranslateReqPipelineQ.deq;
        end

        let addrTranslateReq = PgtAddrTranslateReq {
            pgtOffset: pgtOffset,
            baseVA: baseVA,
            addrToTrans: burstAddrBoundry.startAddr
        };
        addrTranslateCltInst.putReq(addrTranslateReq);

        issueDmaWritePipelineQ.enq(tuple2(burstAddrBoundry.len, curFpDebugTime));
        $display(
            "time=%0t:", $time, toGreen(" mkPayloadCon getBurstChunRespAndIssueAddrTranslateReq"),
            toBlue(", addrTranslateReq="), fshow(addrTranslateReq),
            toBlue(", burstAddrBoundry="), fshow(burstAddrBoundry)
        );
        if (burstAddrBoundry.isFirst) begin
            checkFullyPipeline(fpDebugTime, 3, 2000, "mkPayloadCon getBurstChunRespAndIssueAddrTranslateReq");
        end
    endrule

    rule getBeatChunkMetaCalculateRespAndIssueAxiWrite;
        let curFpDebugTime <- getSimulationTime;
        let {len, fpDebugTime} = issueDmaWritePipelineQ.first;
        issueDmaWritePipelineQ.deq;

        let translatedAddr <- addrTranslateCltInst.getResp;

        ADDR truncatedStartAddr = translatedAddr;
        ADDR truncatedEndAddrForALignCalc = translatedAddr + zeroExtend(len - 1);

        streamSplitorMetaCalcPipelineQ.enq(tuple3(truncate(truncatedStartAddr), truncate(truncatedEndAddrForALignCalc), curFpDebugTime));

        let writeReq = DtldStreamMemAccessMeta {
            addr: translatedAddr,
            totalLen: len
        };
        dmaWriteReqAddrPipeOutQ.enq(writeReq);
        $display(
            "time=%0t:", $time, toGreen(" mkPayloadCon getBeatChunkMetaCalculateRespAndIssueAxiWrite"),
            toBlue(", writeReq="), fshow(writeReq),
            toBlue(", truncatedStartAddr="), fshow(truncatedStartAddr),
            toBlue(", truncatedEndAddrForALignCalc="), fshow(truncatedEndAddrForALignCalc)
        );
        checkFullyPipeline(fpDebugTime, 10, 2000, "mkPayloadCon getBeatChunkMetaCalculateRespAndIssueAxiWrite");
    endrule

    rule calcStreamSpliterMeta;
        let curFpDebugTime <- getSimulationTime;
        let {truncatedStartAddr, truncatedEndAddrForALignCalc, fpDebugTime} = streamSplitorMetaCalcPipelineQ.first;
        streamSplitorMetaCalcPipelineQ.deq;

        AlignBlockCntInPayloadConAndGenBurst alignBlockCntForStreamSplit = truncate( 
            (truncatedEndAddrForALignCalc >> valueOf(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE)) - 
            (truncatedStartAddr >> valueOf(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE))
        ) + 1;

        dsSpliterStreamAlignBlockCountPipeInConverter.enq(alignBlockCntForStreamSplit);

        $display(
            "time=%0t:", $time, toGreen(" mkPayloadCon calcStreamSpliterMeta"),
            toBlue(", truncatedStartAddr="), fshow(truncatedStartAddr),
            toBlue(", truncatedEndAddrForALignCalc="), fshow(truncatedEndAddrForALignCalc),
            toBlue(", alignBlockCntForStreamSplit="), fshow(alignBlockCntForStreamSplit)
        );
        checkFullyPipeline(fpDebugTime, 1, 2000, "mkPayloadCon calcStreamSpliterMeta");
    endrule

    rule forwardConsumedFinishedSignal;
        let curFpDebugTime <- getSimulationTime;
        let ds = payloadConStreamPipeInQ.first;
        payloadConStreamPipeInQ.deq;
        dsSpliterDataPipeInConverter.enq(ds);
       
        if (ds.isLast) begin
            conRespPipeOutQ.enq(True);
        end
        $display(
            "time=%0t:", $time, toGreen(" mkPayloadCon forwardConsumedFinishedSignal"),
            toBlue(", ds="), fshow(ds)
        );
    endrule

    rule debugForwardSplitOutput;
        let curFpDebugTime <- getSimulationTime;
        let ds = dsSpliter.dataPipeOut.first;
        dsSpliter.dataPipeOut.deq;
        dmaWriteReqDataPipeOutQ.enq(ds);
        $display(
            "time=%0t:", $time, toGreen(" mkPayloadCon debugForwardSplitOutput"),
            toBlue(", ds="), fshow(ds)
        );
    endrule

    interface addrTranslateClt = addrTranslateCltInst.clt;
    interface conReqPipeIn = toPipeInB0(conReqPipeInQ);
    interface conRespPipeOut = toPipeOut(conRespPipeOutQ);
    interface payloadConStreamPipeIn = toPipeInB0(payloadConStreamPipeInQ);

    interface IoChannelMemoryWriteMasterPipe dmaWriteMasterPipe;
        interface writeMetaPipeOut = toPipeOut(dmaWriteReqAddrPipeOutQ);
        // interface writeDataPipeOut = dsSpliter.dataPipeOut;
        interface writeDataPipeOut = toPipeOut(dmaWriteReqDataPipeOutQ);
    endinterface

endmodule