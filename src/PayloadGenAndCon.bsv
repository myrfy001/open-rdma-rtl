import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

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
    ADDR   addr;
    Length len;
    PTEIndex pgtOffset;
    ADDR baseVA;
} PayloadConReq deriving(Bits, FShow);

typedef IO_CHANNEL_PCIE_MAX_REQ_LENGTH_IN_BYTE                          PAYLOAD_CON_AND_GEN_MAX_BURST_SIZE;
typedef TAdd#(1, TDiv#(MAX_PMTU, PAYLOAD_CON_AND_GEN_MAX_BURST_SIZE))   PAYLOAD_CON_AND_GEN_MAX_BURST_CNT_PER_REQUEST;

typedef TDiv#(PAYLOAD_CON_AND_GEN_MAX_BURST_SIZE, BYTE_CNT_PER_DWOED)   PAYLOAD_CON_AND_GEN_MAX_DWORD_CNT_PER_BURST;
typedef TAdd#(1, TLog#(PAYLOAD_CON_AND_GEN_MAX_DWORD_CNT_PER_BURST))    PAYLOAD_CON_AND_GEN_MAX_DWORD_CNT_PER_BURST_WIDTH;
typedef Bit#(PAYLOAD_CON_AND_GEN_MAX_DWORD_CNT_PER_BURST_WIDTH)         AlignBlockCntInPayloadConAndGenBurst;

interface PayloadGen;
    interface Client#(PgtAddrTranslateReq, ADDR) addrTranslateClt;
    interface PipeInB0#(PayloadGenReq) genReqPipeIn;
    interface PipeOut#(IoChannelMemoryAccessDataStream) payloadGenStreamPipeOut;

    interface IoChannelMemoryReadMasterPipeNrIn dmaReadMasterPipe;
endinterface

interface PayloadCon;
    interface Client#(PgtAddrTranslateReq, ADDR) addrTranslateClt;
    interface PipeIn#(PayloadConReq) conReqPipeIn;
    interface PipeOut#(Bool) conRespPipeOut;

    interface PipeIn#(IoChannelMemoryAccessDataStream) payloadConStreamPipeIn;

    interface IoChannelMemoryWriteMasterPipe dmaWriteMasterPipe;
endinterface



interface PayloadGenAndCon;
    interface Client#(PgtAddrTranslateReq, ADDR) genAddrTranslateClt;
    interface PipeInB0#(PayloadGenReq) genReqPipeIn;
    interface PipeOut#(IoChannelMemoryAccessDataStream) payloadGenStreamPipeOut;

    interface Client#(PgtAddrTranslateReq, ADDR) conAddrTranslateClt;
    interface PipeIn#(PayloadConReq) conReqPipeIn;
    interface PipeOut#(Bool) conRespPipeOut;
    interface PipeIn#(IoChannelMemoryAccessDataStream) payloadConStreamPipeIn;

    interface IoChannelMemoryMasterPipeNrIn ioChannelMemoryMasterPipeIfc;
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

    interface IoChannelMemoryMasterPipeNrIn ioChannelMemoryMasterPipeIfc;
        interface writePipeIfc  = payloadCon.dmaWriteMasterPipe;
        interface readPipeIfc   = payloadGen.dmaReadMasterPipe;
    endinterface
endmodule

(* synthesize *)
module mkPayloadGen(PayloadGen);

    PipeInAdapterB0#(PayloadGenReq) genReqPipeInQ <- mkPipeInAdapterB0;

    FIFOF#(IoChannelMemoryAccessMeta)        dmaReadReqPipeOutQ   <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream)  dmaReadRespPipeInQ   <- mkSizedFIFOF(2);


    QueuedClient#(PgtAddrTranslateReq, ADDR) addrTranslateCltInst <- mkQueuedClient("mkPayloadGen addrTranslateCltInst");
    AddressChunker#(ADDR, Length, ChunkAlignLogValue) rawReqToBurstChunker <- mkAddressChunker;

    DtldStreamConcator#(DATA, LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE) dsConcator <- mkDtldStreamConcator;
    mkConnection(toPipeOut(dmaReadRespPipeInQ), dsConcator.dataPipeIn);

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
    FIFOF#(Tuple2#(PTEIndex, ADDR)) getBurstChunRespAndIssueAddrTranslateReqPipelineQ <- mkLFIFOF;
    FIFOF#(Tuple2#(Length, Bool)) issueDmaReadPipelineQ <- mkLFIFOF;


    let dsConcatorIsLastStreamFlagPipeInConverter <- mkPipeInB0ToPipeIn(dsConcator.isLastStreamFlagPipeIn, 1);

    rule handleInReq;
        let req = genReqPipeInQ.first;
        genReqPipeInQ.deq;

        let chunkReq = AddressChunkReq{
            startAddr: req.addr,
            len: req.len,
            chunk: fromInteger(valueOf(TLog#(IO_CHANNEL_PCIE_MAX_REQ_LENGTH_IN_BYTE)))
        };

        rawReqToBurstChunker.requestPipeIn.enq(chunkReq);
        getBurstChunRespAndIssueAddrTranslateReqPipelineQ.enq(
            tuple2(req.pgtOffset, req.baseVA));

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadGen handleInReq"),
        //     toBlue(", req="), fshow(req),
        //     toBlue(", chunkReq="), fshow(chunkReq)
        // );
    endrule

    rule getBurstChunRespAndIssueAddrTranslateReq;
        let burstAddrBoundry = rawReqToBurstChunker.responsePipeOut.first;
        rawReqToBurstChunker.responsePipeOut.deq;

        let {pgtOffset, baseVA} = getBurstChunRespAndIssueAddrTranslateReqPipelineQ.first;
        if (burstAddrBoundry.isLast) begin
            getBurstChunRespAndIssueAddrTranslateReqPipelineQ.deq;
        end

        let addrTranslateReq = PgtAddrTranslateReq {
            pgtOffset: pgtOffset,
            baseVA: baseVA,
            addrToTrans: burstAddrBoundry.startAddr
        };
        addrTranslateCltInst.putReq(addrTranslateReq);
        issueDmaReadPipelineQ.enq(tuple2(burstAddrBoundry.len, burstAddrBoundry.isLast));

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadGen getBurstChunRespAndIssueAddrTranslateReq"),
        //     toBlue(", burstAddrBoundry="), fshow(burstAddrBoundry),
        //     toBlue(", addrTranslateReq="), fshow(addrTranslateReq)
        // );
    endrule

    rule issueDmaRead;
        let translatedAddr <- addrTranslateCltInst.getResp;
        let {len, isLast} = issueDmaReadPipelineQ.first;
        issueDmaReadPipelineQ.deq;
        
        let readReq = DtldStreamMemAccessMeta {
            addr: translatedAddr,
            totalLen: len
        };
        dmaReadReqPipeOutQ.enq(readReq);
        dsConcatorIsLastStreamFlagPipeInConverter.enq(isLast);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadGen issueDmaRead"),
        //     toBlue(", translatedAddr="), fshow(translatedAddr),
        //     toBlue(", len="), fshow(len),
        //     toBlue(", isLast="), fshow(isLast)
        // );
    endrule

    let fifoToPipeInNrBridge <- mkFifofToPipeInB0(dmaReadRespPipeInQ);

    interface addrTranslateClt = addrTranslateCltInst.clt;
    interface genReqPipeIn = toPipeInB0(genReqPipeInQ);
    interface payloadGenStreamPipeOut = dsConcator.dataPipeOut;

    interface IoChannelMemoryReadMasterPipeNrIn dmaReadMasterPipe;
        interface readMetaPipeOut = toPipeOut(dmaReadReqPipeOutQ);
        interface readDataPipeIn = fifoToPipeInNrBridge;   // TODO: when stream spliter/concator is refactored into NR, replace this one
    endinterface

endmodule


(* synthesize *)
module mkPayloadCon(PayloadCon);

    FIFOF#(PayloadConReq) conReqPipeInQ <- mkLFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream) payloadConStreamPipeInQ <- mkLFIFOF;
    FIFOF#(Bool) conRespPipeOutQ <- mkFIFOF;

    FIFOF#(IoChannelMemoryAccessMeta)       dmaWriteReqAddrPipeOutQ <- mkFIFOF;
    FIFOF#(IoChannelMemoryAccessDataStream) dmaWriteReqDataPipeOutQ <- mkFIFOF;


    QueuedClient#(PgtAddrTranslateReq, ADDR) addrTranslateCltInst <- mkQueuedClient("mkPayloadCon addrTranslateCltInst");
    AddressChunker#(ADDR, Length, ChunkAlignLogValue) rawReqToBurstChunker <- mkAddressChunker;

    DtldStreamSplitor#(DATA, AlignBlockCntInPayloadConAndGenBurst, LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE) dsSpliter <- mkDtldStreamSplitor;

    FIFOF#(Tuple2#(PTEIndex, ADDR)) getBurstChunRespAndIssueAddrTranslateReqPipelineQ <- mkLFIFOF;
    FIFOF#(Length) issueDmaWritePipelineQ <- mkLFIFOF;
    FIFOF#(Tuple2#(Length, Length)) streamSplitorMetaCalcPipelineQ <- mkLFIFOF;

    let dsSpliterStreamAlignBlockCountPipeInConverter <- mkPipeInB0ToPipeIn(dsSpliter.streamAlignBlockCountPipeIn, 1);
    let dsSpliterDataPipeInConverter <- mkPipeInB0ToPipeIn(dsSpliter.dataPipeIn, 1);

    rule handleInReq;
        let req = conReqPipeInQ.first;
        conReqPipeInQ.deq;

        let chunkReq = AddressChunkReq{
            startAddr: req.addr,
            len: req.len,
            chunk: fromInteger(valueOf(TLog#(IO_CHANNEL_PCIE_MAX_REQ_LENGTH_IN_BYTE)))
        };

        rawReqToBurstChunker.requestPipeIn.enq(chunkReq);
        getBurstChunRespAndIssueAddrTranslateReqPipelineQ.enq(
            tuple2(req.pgtOffset, req.baseVA));
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadCon handleInReq"),
        //     toBlue(", req="), fshow(req),
        //     toBlue(", chunkReq="), fshow(chunkReq)
        // );
    endrule

    rule getBurstChunRespAndIssueAddrTranslateReq;
        let burstAddrBoundry = rawReqToBurstChunker.responsePipeOut.first;
        rawReqToBurstChunker.responsePipeOut.deq;

        let {pgtOffset, baseVA} = getBurstChunRespAndIssueAddrTranslateReqPipelineQ.first;
        if (burstAddrBoundry.isLast) begin
            getBurstChunRespAndIssueAddrTranslateReqPipelineQ.deq;
        end

        let addrTranslateReq = PgtAddrTranslateReq {
            pgtOffset: pgtOffset,
            baseVA: baseVA,
            addrToTrans: burstAddrBoundry.startAddr
        };
        addrTranslateCltInst.putReq(addrTranslateReq);

        issueDmaWritePipelineQ.enq(burstAddrBoundry.len);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadCon getBurstChunRespAndIssueAddrTranslateReq"),
        //     toBlue(", addrTranslateReq="), fshow(addrTranslateReq),
        //     toBlue(", burstAddrBoundry="), fshow(burstAddrBoundry)
        // );
    endrule

    rule getBeatChunkMetaCalculateRespAndIssueAxiWrite;
        let len = issueDmaWritePipelineQ.first;
        issueDmaWritePipelineQ.deq;

        let translatedAddr <- addrTranslateCltInst.getResp;

        ADDR truncatedStartAddr = translatedAddr;
        ADDR truncatedEndAddrForALignCalc = translatedAddr + zeroExtend(len - 1);

        streamSplitorMetaCalcPipelineQ.enq(tuple2(truncate(truncatedStartAddr), truncate(truncatedEndAddrForALignCalc)));

        let writeReq = DtldStreamMemAccessMeta {
            addr: translatedAddr,
            totalLen: len
        };
        dmaWriteReqAddrPipeOutQ.enq(writeReq);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadCon getBeatChunkMetaCalculateRespAndIssueAxiWrite"),
        //     toBlue(", writeReq="), fshow(writeReq),
        //     toBlue(", truncatedStartAddr="), fshow(truncatedStartAddr),
        //     toBlue(", truncatedEndAddrForALignCalc="), fshow(truncatedEndAddrForALignCalc)
        // );
    endrule

    rule calcStreamSpliterMeta;
        let {truncatedStartAddr, truncatedEndAddrForALignCalc} = streamSplitorMetaCalcPipelineQ.first;
        streamSplitorMetaCalcPipelineQ.deq;

        AlignBlockCntInPayloadConAndGenBurst alignBlockCntForStreamSplit = truncate( 
            (truncatedEndAddrForALignCalc >> valueOf(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE)) - 
            (truncatedStartAddr >> valueOf(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE))
        ) + 1;

        dsSpliterStreamAlignBlockCountPipeInConverter.enq(alignBlockCntForStreamSplit);
    endrule

    rule forwardConsumedFinishedSignal;
        let ds = payloadConStreamPipeInQ.first;
        payloadConStreamPipeInQ.deq;
        dsSpliterDataPipeInConverter.enq(ds);
       
        if (ds.isLast) begin
            conRespPipeOutQ.enq(True);
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadCon forwardConsumedFinishedSignal"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    rule debugForwardSplitOutput;
        let ds = dsSpliter.dataPipeOut.first;
        dsSpliter.dataPipeOut.deq;
        dmaWriteReqDataPipeOutQ.enq(ds);
        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadCon debugForwardSplitOutput"),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule

    interface addrTranslateClt = addrTranslateCltInst.clt;
    interface conReqPipeIn = toPipeIn(conReqPipeInQ);
    interface conRespPipeOut = toPipeOut(conRespPipeOutQ);
    interface payloadConStreamPipeIn = toPipeIn(payloadConStreamPipeInQ);

    interface IoChannelMemoryWriteMasterPipe dmaWriteMasterPipe;
        interface writeMetaPipeOut = toPipeOut(dmaWriteReqAddrPipeOutQ);
        // interface writeDataPipeOut = dsSpliter.dataPipeOut;
        interface writeDataPipeOut = toPipeOut(dmaWriteReqDataPipeOutQ);
    endinterface

endmodule