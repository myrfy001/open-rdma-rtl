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
import BasicDataTypes :: *;
import RdmaUtils :: *;
import RdmaHeaders :: *;

import ConnectableF :: *;

import PsnContinousChecker :: *;

typedef struct {
    PSN psn;
    QPN qpn;
} AutoAckGeneratorReq deriving(Bits, FShow);

typedef struct {
    IndexQP                                                             qpnIdx;
    Bool                                                                isPacketLost;
    MSN                                                                 lastAckMsn;
    MSN                                                                 curAckMsn;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary)  oldBitmapEntry;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary)  newBitmapEntry;
} AutoAckGeneratorResp deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool bitmapUnrecoverable;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorToCpsnCounterPipelineEntry deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool bitmapUnrecoverable;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorToMaxAckPsnCalculatorPipelineEntry deriving(Bits, FShow);

typedef struct {
    IndexQP qpnIdx;
    Bool bitmapUnrecoverable;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) oldBitmapEntry;
    BitmapWindowStorageEntry#(AckBitmap, PsnMergeWindowBoundary) newBitmapEntry;
} AutoAckGeneratorToMaxAckPsnStoragePipelineEntry deriving(Bits, FShow);


interface AutoAckGenerator;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(AutoAckGeneratorReq)) reqPipeInVec;
    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(AutoAckGeneratorResp))) respPipeOutVec;

    interface PipeIn#(IndexQP) resetReqPipeIn;
    interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface


(* synthesize *)
module mkAutoAckGenerator(AutoAckGenerator);
    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(AutoAckGeneratorReq)) reqPipeInVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(AutoAckGeneratorReq)) reqPipeInQueueVec <- replicateM(mkFIFOF);
    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
    end

    Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(AutoAckGeneratorResp))) respPipeOutVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(AutoAckGeneratorResp))) respPipeOutQueueVec <- replicateM(mkFIFOF);
    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end

    PsnPerMergeAndStorage psnMergeAndStorage <- mkPsnPerMergeAndStorage;

    // TODO: maybe we can remove this rule
    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        rule forwardInputReqToPsnPreMerge;
            let req = reqPipeInQueueVec[idx].first;
            reqPipeInQueueVec[idx].deq;

            let preMergeReq = FourChannelPsnBitmapPreMergeReq {
                psn: req.psn,
                qpn: req.qpn
            };
            psnMergeAndStorage.reqPipeInVec[idx].enq(preMergeReq);
        endrule
    end


    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        rule handleMergedBitmap;
            let tMaybe = allPacketPsnBitmapStorage.respPipeOutVec[idx].first;
            allPacketPsnBitmapStorage.respPipeOutVec[idx].deq;

            let t = fromMaybe(?, tMaybe);

            respPipeOutQueueVec[idx].enq(tagged Valid AutoAckGeneratorResp {
                qpnIdx              : t.rowAddr,
                needGenAck          : t.isShiftOutOfBoundary,
                needReportToHost    : t.isShiftWindow,
                oldBitmapEntry      : t.oldEntry,
                newBitmapEntry      : t.newEntry
            });
        endrule
    end




    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOutVec = respPipeOutVecInst;

    interface resetReqPipeIn = allPacketPsnBitmapStorage.resetReqPipeIn;
    interface resetRespPipeOut = allPacketPsnBitmapStorage.resetRespPipeOut;
endmodule
