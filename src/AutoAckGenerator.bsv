import RegFile :: * ;
import FIFOF :: *;
import ClientServer :: *;
import Connectable :: *;
import PAClib :: *;
import PrimUtils :: *;
import Vector :: *;
import GetPut :: *;
import Printf:: *;

import Settings :: *;
import DataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;

import ConnectableF :: *;

import PsnContinousChecker :: *;

typedef struct {
    PSN psn;
    QPN qpn;
    Bool needAck;
} AutoAckGeneratorReq deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool needGenAck;
    Bool needReportToHost;
    BitmapWindowStorageEntry#(OooWindowBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(OooWindowBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorResp deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool bitmapUnrecoverable;
    BitmapWindowStorageEntry#(OooWindowBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(OooWindowBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorToCpsnCounterPipelineEntry deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool bitmapUnrecoverable;
    BitmapWindowStorageEntry#(OooWindowBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(OooWindowBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorToMaxAckPsnCalculatorPipelineEntry deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool bitmapUnrecoverable;
    BitmapWindowStorageEntry#(OooWindowBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(OooWindowBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorToMaxAckPsnStoragePipelineEntry deriving(Bits, FShow);


interface AutoAckGenerator;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(AutoAckGeneratorReq)) reqPipeInVec;
    // interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeOut#(Maybe#(AutoAckGeneratorResp))) respPipeOutVec;
    method Bool outputVal;
endinterface


(* synthesize *)
module mkAutoAckGenerator(AutoAckGenerator);
    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(AutoAckGeneratorReq)) reqPipeInVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(AutoAckGeneratorReq)) reqPipeInQueueVec <- replicateM(mkFIFOF);

    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeOut#(Maybe#(AutoAckGeneratorResp))) respPipeOutVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(Maybe#(AutoAckGeneratorResp))) respPipeOutQueueVec <- replicateM(mkFIFOF);


    FourChannelPsnBitmapPreMerge allPacketPsnPermerge <- mkFourChannelPsnBitmapPreMerge;
    FourChannelPsnBitmapPreMerge needAckPacketPsnPermerge <- mkFourChannelPsnBitmapPreMerge;

    BitmapWindowStorage#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE) allPacketPsnBitmapStorage <- mkBitmapWindowStorage("init_bram_psn_merge_storage.bin");
    BitmapWindowStorage#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE) needAckPacketPsnBitmapStorage <- mkBitmapWindowStorage("init_bram_psn_merge_storage.bin");

    // buffer needAckPacketPsnBitmapStorage output to make fully pipeline
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageUpdateResp#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary)))) needAckPacketPsnBitmapStorageOutputBufferVec <- replicateM(mkSizedFIFOF(8));
    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        mkConnection(toGet(needAckPacketPsnBitmapStorage.respPipeOutVec[idx]), toPut(needAckPacketPsnBitmapStorageOutputBufferVec[idx]));
    end

    Reg#(Bool) forwardToStorageEvenOddReg <- mkReg(True);

    Vector#(NUMERIC_TYPE_TWO, CpsnCounter#(OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE)) cpsnCounterVec <- replicateM(mkCpsnCounter);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(AutoAckGeneratorToCpsnCounterPipelineEntry))) cpsnCountPipelineQueueVec <- replicateM(mkFIFOF);
    MonoInrcNumberStorage#(IndexQP, PSN) cpsnStorage <- mkMonoInrcNumberStorage("init_bram_psn_incr_storage.bin", tagged Valid fromInteger(valueOf(OOO_WINDOW_SIZE) - 1));
    
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(AutoAckGeneratorToMaxAckPsnCalculatorPipelineEntry))) toMaxAckPsnCalculatorPipelineQueueVec <- replicateM(mkFIFOF);

    Vector#(NUMERIC_TYPE_TWO, MaxAckPsnCalculator#(OooWindowBitmap, PsnMergeWindowBoundary)) maxAckPsnCalculatorVec <- replicateM(mkMaxAckPsnCalculator);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(AutoAckGeneratorToMaxAckPsnStoragePipelineEntry))) maxAckPsnCalcPipelineQueueVec <- replicateM(mkFIFOF);
    MonoInrcNumberStorage#(IndexQP, PSN) maxAckPsnStorage <- mkMonoInrcNumberStorage("init_bram_psn_incr_storage.bin", tagged Invalid);


    

    Reg#(Bool) tmpOutputReg <- mkRegU;

    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        rule forwardInputReqToPsnPreMerge;
            let req = reqPipeInQueueVec[idx].first;
            reqPipeInQueueVec[idx].deq;

            let preMergeReq = FourChannelPsnBitmapPreMergeReq {
                psn: req.psn,
                qpn: req.qpn
            };

            allPacketPsnPermerge.reqPipeInVec[idx].enq(preMergeReq);
            if (req.needAck) begin
                needAckPacketPsnPermerge.reqPipeInVec[idx].enq(preMergeReq);
            end
        endrule
    end


    rule forwardPremergeToStorage;
        forwardToStorageEvenOddReg <= !forwardToStorageEvenOddReg;

        let allPacketStorageResp = allPacketPsnPermerge.respPipeOut.first;
        let needAckPacketStorageResp = needAckPacketPsnPermerge.respPipeOut.first;

        if (forwardToStorageEvenOddReg) begin
            if (allPacketStorageResp[0] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });
               
            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (allPacketStorageResp[1] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end

            if (needAckPacketStorageResp[0] matches tagged Valid .req) begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });
               
            end
            else begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (needAckPacketStorageResp[1] matches tagged Valid .req) begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end
        end
        else begin
            if (allPacketStorageResp[2] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (allPacketStorageResp[3] matches tagged Valid .req) begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                allPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end

            if (needAckPacketStorageResp[2] matches tagged Valid .req) begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (needAckPacketStorageResp[3] matches tagged Valid .req) begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });

            end
            else begin
                needAckPacketPsnBitmapStorage.reqPipeInVec[1].enq(tagged Invalid);
            end

            allPacketPsnPermerge.respPipeOut.deq;
            needAckPacketPsnPermerge.respPipeOut.deq;
        end
    endrule

    
    rule forwardPsnBitmapStorageOutputToCpsnCounter;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let psnBitmapStorageOutputMaybe = allPacketPsnBitmapStorage.respPipeOutVec[idx].first;
            allPacketPsnBitmapStorage.respPipeOutVec[idx].deq;

            if (psnBitmapStorageOutputMaybe matches tagged Valid .psnBitmapStorageOutput) begin
                let cpsnCountReq = CpsnCounterReq {
                    bitmapEntry: psnBitmapStorageOutput.newEntry
                };

                // if shift offset too large, then the bitmap must be un-recoverable
                Bool bitmapUnrecoverable = psnBitmapStorageOutput.isShiftOutOfBoundary;
                // if the shift is not that large, but some '0' bit has been shifted out, then the bitmap 
                // is also un-recoverable
                // Note: we can not only check this condition, since when doing window shift, the shift offset is
                // a truncated number, if the original shift offset is larger than the truncated shift value, 
                // e.g., the window is 128 bit, the shift offset is a 8-bit number, but if PSN delta is 512, whose 
                // lower 8-bit is all 0, then after truncate, the shift offst is zero, but infact, this shift is 
                // already overflow the shift window.
                bitmapUnrecoverable = bitmapUnrecoverable || (psnBitmapStorageOutput.windowShiftedOutData != -1);

                cpsnCounterVec[idx].reqPipeIn.enq(tagged Valid cpsnCountReq);

                let pipelineEntryOut = AutoAckGeneratorToCpsnCounterPipelineEntry {
                    qpnIdx: psnBitmapStorageOutput.rowAddr,
                    bitmapUnrecoverable: bitmapUnrecoverable,
                    oldBitmapEntry: psnBitmapStorageOutput.oldEntry,
                    newBitmapEntry: psnBitmapStorageOutput.newEntry
                };

                cpsnCountPipelineQueueVec[idx].enq(tagged Valid pipelineEntryOut);
            end
            else begin
                cpsnCounterVec[idx].reqPipeIn.enq(tagged Invalid);
                cpsnCountPipelineQueueVec[idx].enq(tagged Invalid);
            end
        end 
    endrule

    rule forwardCpsnToCpsnStorage;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin

            let cpsnResultMaybe = cpsnCounterVec[idx].respPipeOut.first;
            cpsnCounterVec[idx].respPipeOut.deq;

            let pipelineEntryInMaybe = cpsnCountPipelineQueueVec[idx].first;
            cpsnCountPipelineQueueVec[idx].deq;

            if (cpsnResultMaybe matches tagged Valid .cpsn) begin
                immAssert(
                    isValid(pipelineEntryInMaybe), 
                    "pipelineEntryInMaybe must be valid here",
                    $format("")
                );
                let pipelineEntryIn = fromMaybe(?, pipelineEntryInMaybe);

                let cpsnUpdateReq = MonoInrcNumberStorageUpdateReq {
                    rowAddr: pipelineEntryIn.qpnIdx,
                    value: cpsn
                };
                cpsnStorage.reqPipeInVec[idx].enq(tagged Valid cpsnUpdateReq);

                let pipelineEntryOut = AutoAckGeneratorToMaxAckPsnCalculatorPipelineEntry{
                    qpnIdx: pipelineEntryIn.qpnIdx,
                    bitmapUnrecoverable: pipelineEntryIn.bitmapUnrecoverable,
                    oldBitmapEntry: pipelineEntryIn.oldBitmapEntry,
                    newBitmapEntry: pipelineEntryIn.newBitmapEntry
                };
                toMaxAckPsnCalculatorPipelineQueueVec[idx].enq(tagged Valid pipelineEntryOut);
            end
            else begin
                cpsnStorage.reqPipeInVec[idx].enq(tagged Invalid);
                toMaxAckPsnCalculatorPipelineQueueVec[idx].enq(tagged Invalid);
            end
        end
    endrule

    rule forwardCpsnAndNeedAckBitmapToMaxAckPsnCalculator;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin

            let cpsnStorageRespMaybe = cpsnStorage.respPipeOutVec[idx].first;
            cpsnStorage.respPipeOutVec[idx].deq;

            if (cpsnStorageRespMaybe matches tagged Valid .cpsnStorageResp) begin
                let needAckBitmapStorageRespMaybe = needAckPacketPsnBitmapStorageOutputBufferVec[idx].first;
                needAckPacketPsnBitmapStorageOutputBufferVec[idx].deq;
                let needAckBitmapStorageResp = fromMaybe(?, needAckBitmapStorageRespMaybe);

                let pipelineEntryInMaybe = toMaxAckPsnCalculatorPipelineQueueVec[idx].first;
                toMaxAckPsnCalculatorPipelineQueueVec[idx].deq;
                let pipelineEntryIn = fromMaybe(?, pipelineEntryInMaybe);
                
                immAssert(
                    isValid(needAckBitmapStorageRespMaybe) && needAckBitmapStorageResp.rowAddr == cpsnStorageResp.rowAddr,
                    "forked pipeline path should matching each other when being joined",
                    $format("cpsnStorageRespMaybe=", fshow(cpsnStorageRespMaybe), "needAckBitmapStorageRespMaybe=", fshow(needAckBitmapStorageRespMaybe))
                );

                immAssert(
                    isValid(pipelineEntryInMaybe) && pipelineEntryIn.qpnIdx == cpsnStorageResp.rowAddr,
                    "forked pipeline path should matching each other when being joined",
                    $format("cpsnStorageRespMaybe=", fshow(cpsnStorageRespMaybe), "pipelineEntryInMaybe=", fshow(pipelineEntryInMaybe))
                );

                let maxAckPsnCalcReq = MaxAckPsnCalculatorReq {
                    needAckBitmap: needAckBitmapStorageResp.newEntry,
                    cpsn: cpsnStorageResp.newValue
                };
                maxAckPsnCalculatorVec[idx].reqPipeIn.enq(tagged Valid maxAckPsnCalcReq);

                let pipelineEntryOut = AutoAckGeneratorToMaxAckPsnStoragePipelineEntry {
                    qpnIdx: pipelineEntryIn.qpnIdx,
                    bitmapUnrecoverable: pipelineEntryIn.bitmapUnrecoverable,
                    oldBitmapEntry: pipelineEntryIn.oldBitmapEntry,
                    newBitmapEntry: pipelineEntryIn.newBitmapEntry
                };
                maxAckPsnCalcPipelineQueueVec[idx].enq(tagged Valid pipelineEntryOut );
            end
            else begin
                maxAckPsnCalculatorVec[idx].reqPipeIn.enq(tagged Invalid);
                maxAckPsnCalcPipelineQueueVec[idx].enq(tagged Invalid);
            end
        end
    endrule

    rule forwardAckPsnToStorage;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin

            let maxAckResultMaybe = maxAckPsnCalculatorVec[idx].respPipeOut.first;
            maxAckPsnCalculatorVec[idx].respPipeOut.deq;

            let pipelineEntryInMaybe = maxAckPsnCalcPipelineQueueVec[idx].first;
            maxAckPsnCalcPipelineQueueVec[idx].deq;

            if (maxAckResultMaybe matches tagged Valid .maxAckPsn) begin
                immAssert(
                    isValid(pipelineEntryInMaybe), 
                    "pipelineEntryInMaybe must be valid here",
                    $format("")
                );
                let pipelineEntryIn = fromMaybe(?, pipelineEntryInMaybe);

                let maxAckPsnUpdateReq = MonoInrcNumberStorageUpdateReq {
                    rowAddr: pipelineEntryIn.qpnIdx,
                    value: maxAckPsn
                };
                maxAckPsnStorage.reqPipeInVec[idx].enq(tagged Valid maxAckPsnUpdateReq);
            end
            else begin
                maxAckPsnStorage.reqPipeInVec[idx].enq(tagged Invalid);
            end
        end
    endrule












    rule outputResp;
        Bool t = False;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let maxAckPsnStorageRespMaybe = maxAckPsnStorage.respPipeOutVec[idx].first;
            maxAckPsnStorage.respPipeOutVec[idx].deq;
            if (maxAckPsnStorageRespMaybe matches tagged Valid .maxAckPsn &&& pack(maxAckPsn) == 9999) begin
                t = unpack(pack(t) ^ pack(True));
            end
            else begin
                t = unpack(pack(t) ^ pack(False));
            end
        end

        tmpOutputReg <= t;
    endrule

    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end
    interface reqPipeInVec = reqPipeInVecInst;
    // interface respPipeOutVec = respPipeOutVecInst;
    method outputVal = tmpOutputReg;
endmodule
