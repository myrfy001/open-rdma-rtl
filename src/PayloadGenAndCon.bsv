import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


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



interface PayloadGen;
    interface Client#(PgtAddrTranslateReq, ADDR) addrTranslateClt;
    interface PipeIn#(PayloadGenReq) genReqPipeIn;
    interface PipeOut#(DataStream) payloadGenStreamPipeOut;
endinterface

interface PayloadCon;
    interface Client#(PgtAddrTranslateReq, ADDR) addrTranslateClt;
    interface PipeIn#(PayloadConReq) conReqPipeIn;
    interface PipeOut#(Bool) conRespPipeOut;

    interface PipeIn#(DataStream) payloadConStreamPipeIn;
endinterface



interface PayloadGenAndCon;
    interface Client#(PgtAddrTranslateReq, ADDR) genAddrTranslateClt;
    interface PipeIn#(PayloadGenReq) genReqPipeIn;
    interface PipeOut#(DataStream) payloadGenStreamPipeOut;

    interface Client#(PgtAddrTranslateReq, ADDR) conAddrTranslateClt;
    interface PipeIn#(PayloadConReq) conReqPipeIn;
    interface PipeOut#(Bool) conRespPipeOut;
    interface PipeIn#(DataStream) payloadConStreamPipeIn;
endinterface


module mkPayloadGenAndCon(PayloadGenAndCon);
    AcxNapSlaveWrapper dmaReadWriteSlaveNap <- mkAcxNapSlaveWrapper;

    PayloadGen payloadGen <- mkPayloadGen(dmaReadWriteSlaveNap);
    PayloadCon payloadCon <- mkPayloadCon(dmaReadWriteSlaveNap);

    interface genAddrTranslateClt = payloadGen.addrTranslateClt;
    interface genReqPipeIn = payloadGen.genReqPipeIn;
    interface payloadGenStreamPipeOut = payloadGen.payloadGenStreamPipeOut;

    interface conAddrTranslateClt = payloadCon.addrTranslateClt;
    interface conReqPipeIn = payloadCon.conReqPipeIn;
    interface conRespPipeOut = payloadCon.conRespPipeOut;
    interface payloadConStreamPipeIn = payloadCon.payloadConStreamPipeIn;
endmodule

module mkPayloadGen#(AcxNapSlaveWrapper dmaReadSlaveNap)(PayloadGen);

    FIFOF#(PayloadGenReq) genReqPipeInQ <- mkFIFOF;
    FIFOF#(DataStream) payloadGenStreamPipeOutQ <- mkFIFOF;

    QueuedClient#(PgtAddrTranslateReq, ADDR) addrTranslateCltInst <- mkQueuedClient("mkPayloadGen addrTranslateCltInst");


    AddressChunkMetaCalculator#(
            ADDR, Length, PcieAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, PCIE_BURST_ALIGN_BIT_NUM)
        ) rawReqToBurstChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrForPcieBurst,
            devideLengthForPcieBurst,
            isAddrAndLengthLowerPartSumOverflowForPcieBurst,
            getChunkSizeForPcieBurst
        );
    AddressChunker#(
            ADDR, Length, PcieAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, PCIE_BURST_ALIGN_BIT_NUM)
        ) rawReqToBurstChunker <- mkAddressChunker;
    AddressChunkMetaCalculator#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) burstToBeatChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrForBeat,
            devideLengthForBeat,
            isAddrAndLengthLowerPartSumOverflowForBeat,
            getChunkSizeForBeat
        );
    AddressChunker#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) burstToBeatChunker <- mkAddressChunker;

    Reg#(Bool) outputIsFirstReg <- mkReg(True);

    mkConnection(rawReqToBurstChunkMetaCalc.metaPipeOut, rawReqToBurstChunker.requestPipeIn);

    // Pipeline FIFOs
    FIFOF#(AddressChunkResp#(ADDR, Length)) chunkedBurstMetaQ <- mkFIFOF;
    FIFOF#(Tuple2#(PTEIndex, ADDR)) getBurstChunRespAndIssueBeatChunkMetaCalculateReqPipelineQ <- mkFIFOF;

    rule handleInReq;
        let req = genReqPipeInQ.first;
        genReqPipeInQ.deq;

        let chunkReq = AddressChunkReq{
            startAddr: req.addr,
            len: req.len,
            chunk: dontCareValue
        };

        rawReqToBurstChunkMetaCalc.requestPipeIn.enq(chunkReq);
        getBurstChunRespAndIssueBeatChunkMetaCalculateReqPipelineQ.enq(
            tuple2(req.pgtOffset, req.baseVA));

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadGen handleInReq"),
        //     toBlue(", req="), fshow(req)
        // );
    endrule

    rule getBurstChunRespAndIssueBeatChunkMetaCalculateReq;
        let burstAddrBoundry = rawReqToBurstChunker.responsePipeOut.first;
        rawReqToBurstChunker.responsePipeOut.deq;

        let {pgtOffset, baseVA} = getBurstChunRespAndIssueBeatChunkMetaCalculateReqPipelineQ.first;
        if (burstAddrBoundry.isLast) begin
            getBurstChunRespAndIssueBeatChunkMetaCalculateReqPipelineQ.deq;
        end

        let chunkReq = AddressChunkReq{
            startAddr: burstAddrBoundry.startAddr,
            len: burstAddrBoundry.len,
            chunk: dontCareValue
        };
        burstToBeatChunkMetaCalc.requestPipeIn.enq(chunkReq);

        let addrTranslateReq = PgtAddrTranslateReq {
            pgtOffset: pgtOffset,
            baseVA: baseVA,
            addrToTrans: burstAddrBoundry.startAddr
        };
        addrTranslateCltInst.putReq(addrTranslateReq);

        chunkedBurstMetaQ.enq(burstAddrBoundry);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadGen getBurstChunRespAndIssueBeatChunkMetaCalculateReq"),
        //     toBlue(", burstAddrBoundry="), fshow(burstAddrBoundry),
        //     toBlue(", pgtOffset="), fshow(pgtOffset),
        //     toBlue(", baseVA="), fshow(baseVA)
        // );
    endrule


    rule issueAxiRead;
        let burstToBeatChunkMeta = burstToBeatChunkMetaCalc.metaPipeOut.first;
        burstToBeatChunkMetaCalc.metaPipeOut.deq;

        let translatedAddr <- addrTranslateCltInst.getResp;
        
        let ar = AxiMmNapBeatAr {
            arid: 0,
            araddr: truncate(translatedAddr),
            arlen: unpack(truncate(burstToBeatChunkMeta.zeroBasedChunkNum)),
            arsize: unpack(pack(NapAxiSize32B)),
            arburst: unpack(pack(NapAxiBurstIncr)),
            arlock: False,
            arqos: 0
        };

        dmaReadSlaveNap.sendReadAddr(ar);
        burstToBeatChunker.requestPipeIn.enq(burstToBeatChunkMeta);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadGen issueAxiRead"),
        //     toBlue(", burstToBeatChunkMeta="), fshow(burstToBeatChunkMeta)
        // );
    endrule

    rule gatherAxiReadResp;
        let axiReadResp <- dmaReadSlaveNap.recvReadResp;
        let burstMeta = chunkedBurstMetaQ.first;
        let beatMeta = burstToBeatChunker.responsePipeOut.first;
        burstToBeatChunker.responsePipeOut.deq;

        Bool isLast = False;
        if (axiReadResp.rlast) begin
            immAssert(
                beatMeta.isLast,
                "beatMeta.isLast should also be true here, but it doesn't, which means our chunk algroithm is not the same as the NAP hardware",
                $format("")
            );
            chunkedBurstMetaQ.deq;
            if (burstMeta.isLast) begin
                isLast = True;
            end
        end

        outputIsFirstReg <= isLast;

        Bool isFirst = outputIsFirstReg;

        ByteEnBitNum    startByteIdx = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
        ByteIndexInBeat startAddrByteOffsetInBeat = truncate(burstMeta.startAddr);
        ByteEnBitNum    byteNum = truncate(beatMeta.len);

        // TODO: maybe we can split this calculate into previous beat and this beat
        startByteIdx = isFirst ? startByteIdx - zeroExtend(startAddrByteOffsetInBeat) - byteNum : 0;

        let ds = DataStream {
            data: axiReadResp.rdata,
            byteNum: byteNum,
            startByteIdx: truncate(startByteIdx),
            isFirst: isFirst,
            isLast: isLast
        };
        ds = reverseStream(ds);

        payloadGenStreamPipeOutQ.enq(ds);

        // $display(
        //     "time=%0t:", $time, toGreen(" mkPayloadGen gatherAxiReadResp"),
        //     toBlue(", ds="), fshow(ds)
        // );

    endrule

    interface addrTranslateClt = addrTranslateCltInst.clt;
    interface genReqPipeIn = toPipeIn(genReqPipeInQ);
    interface payloadGenStreamPipeOut = toPipeOut(payloadGenStreamPipeOutQ);

endmodule



module mkPayloadCon#(AcxNapSlaveWrapper dmaWriteSlaveNap)(PayloadCon);

    FIFOF#(PayloadConReq) conReqPipeInQ <- mkFIFOF;
    FIFOF#(DataStream) payloadConStreamPipeInQ <- mkFIFOF;
    FIFOF#(Bool) conRespPipeOutQ <- mkFIFOF;

    QueuedClient#(PgtAddrTranslateReq, ADDR) addrTranslateCltInst <- mkQueuedClient("mkPayloadCon addrTranslateCltInst");

    AddressChunkMetaCalculator#(
            ADDR, Length, PcieAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, PCIE_BURST_ALIGN_BIT_NUM)
        ) rawReqToBurstChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrForPcieBurst,
            devideLengthForPcieBurst,
            isAddrAndLengthLowerPartSumOverflowForPcieBurst,
            getChunkSizeForPcieBurst
        );
    AddressChunker#(
            ADDR, Length, PcieAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, PCIE_BURST_ALIGN_BIT_NUM)
        ) rawReqToBurstChunker <- mkAddressChunker;
    AddressChunkMetaCalculator#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) burstToBeatChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrForBeat,
            devideLengthForBeat,
            isAddrAndLengthLowerPartSumOverflowForBeat,
            getChunkSizeForBeat
        );
    AddressChunker#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder,
            TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) burstToBeatChunker <- mkAddressChunker;

    

    FIFOF#(AddressChunkResp#(ADDR, Length)) chunkedBurstMetaQ <- mkFIFOF;
    FIFOF#(Tuple2#(PTEIndex, ADDR)) getBurstChunRespAndIssueBeatChunkMetaCalculateReqPipelineQ <- mkFIFOF;
    FIFOF#(Tuple2#(DataStreamEn, ByteIndexInBeat)) dataStreamEnPreCalcPipelineQ <- mkFIFOF;
    FIFOF#(AddressChunkResp#(ADDR, Length)) inflightAxiWriteBurstMetaQ <- mkFIFOF; 

    mkConnection(rawReqToBurstChunkMetaCalc.metaPipeOut, rawReqToBurstChunker.requestPipeIn);

    Reg#(Bool) errorOccuredReg <- mkReg(False);

    rule handleInReq;
        let req = conReqPipeInQ.first;
        conReqPipeInQ.deq;

        let chunkReq = AddressChunkReq{
            startAddr: req.addr,
            len: req.len,
            chunk: dontCareValue
        };

        rawReqToBurstChunkMetaCalc.requestPipeIn.enq(chunkReq);
        getBurstChunRespAndIssueBeatChunkMetaCalculateReqPipelineQ.enq(
            tuple2(req.pgtOffset, req.baseVA));
    endrule

    rule getBurstChunRespAndIssueBeatChunkMetaCalculateReq;
        let burstAddrBoundry = rawReqToBurstChunker.responsePipeOut.first;
        rawReqToBurstChunker.responsePipeOut.deq;

        let {pgtOffset, baseVA} = getBurstChunRespAndIssueBeatChunkMetaCalculateReqPipelineQ.first;
        if (burstAddrBoundry.isLast) begin
            getBurstChunRespAndIssueBeatChunkMetaCalculateReqPipelineQ.deq;
        end

        let chunkReq = AddressChunkReq{
            startAddr: burstAddrBoundry.startAddr,
            len: burstAddrBoundry.len,
            chunk: dontCareValue
        };
        burstToBeatChunkMetaCalc.requestPipeIn.enq(chunkReq);

        let addrTranslateReq = PgtAddrTranslateReq {
            pgtOffset: pgtOffset,
            baseVA: baseVA,
            addrToTrans: burstAddrBoundry.startAddr
        };
        addrTranslateCltInst.putReq(addrTranslateReq);

        chunkedBurstMetaQ.enq(burstAddrBoundry);
    endrule

    rule getBeatChunkMetaCalculateRespAndIssueAxiWrite;
        let burstToBeatChunkMeta = burstToBeatChunkMetaCalc.metaPipeOut.first;
        burstToBeatChunkMetaCalc.metaPipeOut.deq;

        let burstAddrBoundry = chunkedBurstMetaQ.first;
        chunkedBurstMetaQ.deq;

        let translatedAddr <- addrTranslateCltInst.getResp;

        let awReq = AxiMmNapBeatAw {
            awid: 0,
            awaddr: truncate(translatedAddr),
            awlen: unpack(truncate(burstToBeatChunkMeta.zeroBasedChunkNum)),
            awsize: unpack(pack(NapAxiSize32B)),
            awburst: unpack(pack(NapAxiBurstIncr)),
            awlock: False,
            awqos: 0
        };
        dmaWriteSlaveNap.sendWriteAddr(awReq);
        burstToBeatChunker.requestPipeIn.enq(burstToBeatChunkMeta);
        inflightAxiWriteBurstMetaQ.enq(burstAddrBoundry);
    endrule


    rule preCalcWriteStreamByteEn;
        let ds = payloadConStreamPipeInQ.first;
        payloadConStreamPipeInQ.deq;
        ByteEn allOneByteEn = -1;
        ByteEn allZeroByteEn = 0;
        ByteEn byteEn = truncate({allOneByteEn, allZeroByteEn} >> ds.byteNum);

        let dsEn = DataStreamEn {
            data: ds.data,
            byteEn: byteEn,
            isFirst: ds.isFirst,
            isLast: ds.isLast
        };
        dataStreamEnPreCalcPipelineQ.enq(tuple2(dsEn, ds.startByteIdx));
    endrule

    rule sendAxiWriteBeat;
        let beatInfo = burstToBeatChunker.responsePipeOut.first;
        burstToBeatChunker.responsePipeOut.deq;

        let {dsEn, startByteIdx} = dataStreamEnPreCalcPipelineQ.first;
        dataStreamEnPreCalcPipelineQ.deq;

        // Note: the following lines complete the byteEN generation. Those lines of code should 
        // be placed in the `rule preCalcWriteStreamByteEn`, but the shift timing is worse.
        // to fix timing, split the byteEn generation into this rule and `rule preCalcWriteStreamByteEn`
        dsEn.byteEn = dsEn.byteEn >> startByteIdx;
        if (dsEn.isFirst) begin
            // since only first beat in the stream is right aligned
            dsEn.byteEn = swapEndianBit(dsEn.byteEn);
        end


        dsEn = reverseStreamEnAndData(dsEn);

        let wlast = beatInfo.isLast;

        let wReq = AxiMmNapBeatW {
            wdata: dsEn.data,
            wstrb: dsEn.byteEn,
            wlast: wlast
        };
        dmaWriteSlaveNap.sendWriteData(wReq);

        if (dsEn.isLast) begin
            immAssert(
                wlast,
                "wlast should also be true here, but it doesn't, which means the chunk calculated from address and len doesn't match the received stream",
                $format("")
            );
        end
    endrule

    rule forwardAxiB;
        let resp <- dmaWriteSlaveNap.recvWriteResp;
        let burstMeta = inflightAxiWriteBurstMetaQ.first;
        inflightAxiWriteBurstMetaQ.deq;

        let errorOccured = errorOccuredReg || (resp.bresp != 0);
        if (burstMeta.isLast) begin
            conRespPipeOutQ.enq(!errorOccured);
            errorOccuredReg <= False;
        end
        else begin
            errorOccuredReg <= errorOccured;
        end
    endrule

    interface addrTranslateClt = addrTranslateCltInst.clt;
    interface conReqPipeIn = toPipeIn(conReqPipeInQ);
    interface conRespPipeOut = toPipeOut(conRespPipeOutQ);
    interface payloadConStreamPipeIn = toPipeIn(payloadConStreamPipeInQ);

endmodule