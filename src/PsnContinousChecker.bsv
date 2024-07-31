import Vector :: *;
import FIFOF :: *;

import PrimUtils :: *;
import DataTypes :: *;

import RdmaHeaders :: *;


import ConnectableF :: *;

typedef 128 BITMAP_BIT_WIDTH_PER_BANK;
typedef Bit#(BITMAP_BIT_WIDTH_PER_BANK) BitmapPerBank;

typedef TLog#(BITMAP_BIT_WIDTH_PER_BANK) BITMAP_BIT_INDEX_WIDTH;
typedef Bit#(BITMAP_BIT_INDEX_WIDTH) BitmapBitIdx;

typedef 4 BITMAP_BANK_NUM;
typedef TLog#(BITMAP_BANK_NUM) BITMAP_BANK_IDNEX_WIDTH;
typedef Bit#(BITMAP_BANK_IDNEX_WIDTH) BitmapBankIdx;

typedef TSub#(PSN_WIDTH, TAdd#(BITMAP_BIT_INDEX_WIDTH, BITMAP_BANK_IDNEX_WIDTH)) BITMAP_BANK_TAG_BIT_WIDTH;
typedef Bit#(BITMAP_BANK_TAG_BIT_WIDTH) BitmapBankTag;

typedef 4 CPSN_CHECKER_CHANNEL_NUM;

typedef struct {
    PSN psn;
    QPN qpn;
    Bool needAck;
} PsnContinousCheckerReq deriving(Bits, FShow);

typedef struct {
    QPN qpn;
    PSN cpsn;
    Maybe#(BitmapPerBank) evictedBitmapMaybe;
} PsnContinousCheckerResp deriving(Bits, FShow);

typedef struct {
    BitmapBankTag   tag;
    BitmapBankIdx   bankIdx;
    BitmapBitIdx    bitIdx;
} PsnAsBitmapIndex deriving(Bits, FShow);

interface PsnContinousCheckerAndAckAutoGen;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(PsnContinousCheckerReq)) reqPipeInVec;
    interface Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeOut#(PsnContinousCheckerResp)) respPipeOutVec;
endinterface


(* synthesize *)
module mkPsnContinousCheckerAndAckAutoGen(PsnContinousCheckerAndAckAutoGen);
    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeIn#(PsnContinousCheckerReq)) reqPipeInVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, PipeOut#(PsnContinousCheckerResp)) respPipeOutVecInst = newVector;
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(PsnContinousCheckerReq)) reqPipeInQueueVec <- replicateM(mkFIFOF);
    Vector#(CPSN_CHECKER_CHANNEL_NUM, FIFOF#(PsnContinousCheckerResp)) respPipeOutQueueVec <- replicateM(mkFIFOF);







    for (Integer idx = 0; idx < valueOf(CPSN_CHECKER_CHANNEL_NUM); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end
    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOutVec = respPipeOutVecInst;
endmodule


interface OneHotBankBitmapGen;
    interface PipeIn#(PSN) psnPipeIn;
    interface PipeOut#(BitmapPerBank) bitmapPipeOut;
endinterface

module mkOneHotBankBitmapGen(OneHotBankBitmapGen);
    FIFOF#(PSN) psnPipeInQ <- mkFIFOF;
    FIFOF#(BitmapPerBank) bitmapPipeOutQ <- mkFIFOF;

    rule doShift;
        let psn = psnPipeInQ.first;
        psnPipeInQ.deq;

        PsnAsBitmapIndex psnAsBitmapIndex = unpack(pack(psn));
        BitmapPerBank out = 1 << psnAsBitmapIndex.bitIdx;

        bitmapPipeOutQ.enq(out);
    endrule

    interface psnPipeIn = toPipeIn(psnPipeInQ);
    interface bitmapPipeOut = toPipeOut(bitmapPipeOutQ);
endmodule


// Must be 2^N
typedef 128 OOO_WINDOW_SIZE;
typedef 16  OOO_WINDOW_STRIDE;  


typedef Bit#(OOO_WINDOW_SIZE) OooWindowBitmap;




typedef struct {
    tData       data;
    tBoundary   leftBound;
} BitmapWindowStorageEntry#(type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr                                    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) entry;
} BitmapWindowStorageUpdateReq#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) oldEntry;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageUpdateResp#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageStageOneToTwoPipelineEntry#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) oldEntry;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageStageTwoToThreePipelineEntry#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr        rowAddr;
    Bool            isShiftWindow;
    Bool            isShiftOutOfBoundary;
    tShiftOffset    shiftAbsValue;
    BitmapWindowStorageEntry#(tData, tBoundary) oldEntry;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageStageThreeToFourPipelineEntry#(type tRowAddr, type tData, type tBoundary, type tShiftOffset) deriving(Bits, FShow);


typedef struct {
    tRowAddr    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) entry;
} BitmapWindowStorageInternalForwardEntry#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

interface BitmapWindowStorage#(type tRowAddr, type tData, type tBoundary, numeric type szStride);
    interface Vector#(NUMERIC_TYPE_TWO, PipeIn#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary))) reqPipeInVec;
    interface Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(BitmapWindowStorageUpdateResp#(tRowAddr, tData, tBoundary)))) respPipeOutVec;
endinterface

module mkBitmapWindowStorage(BitmapWindowStorage#(tRowAddr, tData, tBoundary, szStride)) provisos (
        Bits#(tRowAddr, szRowAddr),
        Bits#(tData, szData),
        Bitwise#(tData),
        Bits#(tBoundary, szBoundary),
        Bounded#(tRowAddr),
        Eq#(tRowAddr),
        Arith#(tBoundary),
        Bitwise#(tBoundary),
        Ord#(tBoundary),
        NumAlias#(TLog#(TDiv#(szData, szStride)), szShiftOffset),
        Alias#(Bit#(szShiftOffset), tShiftOffset),
        Add#(a__, szShiftOffset, szBoundary),
        Add#(b__, szShiftOffset, TLog#(szData))
    );
    Vector#(NUMERIC_TYPE_TWO, PipeIn#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary))) reqPipeInVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, PipeOut#(Maybe#(BitmapWindowStorageUpdateResp#(tRowAddr, tData, tBoundary)))) respPipeOutVecInst = newVector;

    Vector#(NUMERIC_TYPE_TWO, FIFOF#(BitmapWindowStorageUpdateReq#(tRowAddr, tData, tBoundary))) reqPipeInQueueVec <- replicateM(mkFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageUpdateResp#(tRowAddr, tData, tBoundary)))) respPipeOutQueueVec <- replicateM(mkFIFOF);

    Vector#(NUMERIC_TYPE_TWO, Vector#(NUMERIC_TYPE_TWO, AutoInferBram#(tRowAddr, BitmapWindowStorageEntry#(tData, tBoundary)))) storage <- replicateM(replicateM(mkAutoInferBramWithRwBypassLogicUG));


    // Forward Registers
    Vector#(NUMERIC_TYPE_TWO, Reg#(Maybe#(BitmapWindowStorageInternalForwardEntry#(tRowAddr, tData, tBoundary)))) forwardRegVec <- replicateM(mkReg(tagged Invalid));

    // Pipeline Queues
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageStageOneToTwoPipelineEntry#(tRowAddr, tData, tBoundary)))) stageOneToTwoPipelineQueueVec <- replicateM(mkLFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageStageTwoToThreePipelineEntry#(tRowAddr, tData, tBoundary)))) stageTwoToThreePipelineQueueVec <- replicateM(mkLFIFOF);
    Vector#(NUMERIC_TYPE_TWO, FIFOF#(Maybe#(BitmapWindowStorageStageThreeToFourPipelineEntry#(tRowAddr, tData, tBoundary, tShiftOffset)))) stageThreeToFourPipelineQueueVec <- replicateM(mkLFIFOF);

    function Integer getSelfIdx(Integer idx) = idx;
    function Integer getOtherIdx(Integer idx) = 1 - idx;


    // Pipeline Stage One
    rule sendBramQueryReq;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            if (reqPipeInQueueVec[idx].notEmpty) begin
                let req = reqPipeInQueueVec[idx].first;
                reqPipeInQueueVec[idx].deq;
                storage[selfChannelIdx][0].putReadReq(req.rowAddr);
                storage[otherChannelIdx][1].putReadReq(req.rowAddr);

                let pipelineEntryOut = BitmapWindowStorageStageOneToTwoPipelineEntry {
                    rowAddr: req.rowAddr,
                    newEntry: req.entry
                };
                stageOneToTwoPipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
            end
            else begin
                stageOneToTwoPipelineQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Pipeline Stage Two
    rule getBramQueryRespAndPreMergeThem;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = stageOneToTwoPipelineQueueVec[selfChannelIdx].first;
            stageOneToTwoPipelineQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin
                let selfResp <- storage[selfChannelIdx][0].getReadResp;
                let otherResp <- storage[otherChannelIdx][1].getReadResp;

                let delta = selfResp.leftBound - otherResp.leftBound;

                // if delta is non-negative, means `selfResp` is newer or equal to `otherResp`, so choose `selfResp`.
                let selectedResp = msb(delta) == 0 ? selfResp : otherResp;

                let pipelineEntryOut = BitmapWindowStorageStageTwoToThreePipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    oldEntry: selectedResp,
                    newEntry: pipelineEntryIn.newEntry
                };
                stageTwoToThreePipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
            end
            else begin
                stageTwoToThreePipelineQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Pipeline Stage Three
    rule doNewOldPreMerge;
        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = stageTwoToThreePipelineQueueVec[selfChannelIdx].first;
            stageTwoToThreePipelineQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin

                let newestAlreadyExistEntry = pipelineEntryIn.oldEntry;

                // if forward path has valid data, then use the forwarded data.
                // Since the request for the same rowAddr can't occur in two channel at the same time, if any channel has 
                // forwarded data, just use it.
                if (forwardRegVec[0] matches tagged Valid .forwardedEntry) begin
                    if (forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                        newestAlreadyExistEntry = forwardedEntry.entry;
                    end
                end
                else if (forwardRegVec[1] matches tagged Valid .forwardedEntry) begin
                    if (forwardedEntry.rowAddr == pipelineEntryIn.rowAddr) begin
                        newestAlreadyExistEntry = forwardedEntry.entry;
                    end
                end

                tBoundary boundaryDelta = pipelineEntryIn.newEntry.leftBound - newestAlreadyExistEntry.leftBound;
                tBoundary boundaryDeltaAbs = getAbsValue(boundaryDelta);


                let isShiftWindow = msb(boundaryDelta) == 0;

                let outOfBoundary = boundaryDeltaAbs >= fromInteger(valueOf(TDiv#(szData, szStride)));


                let pipelineEntryOut = BitmapWindowStorageStageThreeToFourPipelineEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    oldEntry: newestAlreadyExistEntry,
                    newEntry: pipelineEntryIn.newEntry,
                    isShiftWindow: isShiftWindow,
                    isShiftOutOfBoundary: outOfBoundary,
                    shiftAbsValue: unpack(truncate(pack(boundaryDeltaAbs)))
                };

                stageThreeToFourPipelineQueueVec[selfChannelIdx].enq(tagged Valid pipelineEntryOut);
            end
            else begin
                stageThreeToFourPipelineQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule

    // Pipeline Stage Four
    rule doMerge;

        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
            let selfChannelIdx = getSelfIdx(idx);
            let otherChannelIdx = getOtherIdx(idx);

            let pipelineEntryInMaybe = stageThreeToFourPipelineQueueVec[selfChannelIdx].first;
            stageThreeToFourPipelineQueueVec[selfChannelIdx].deq;

            if (pipelineEntryInMaybe matches tagged Valid .pipelineEntryIn) begin
                let alreadyExistEntry = pipelineEntryIn.oldEntry;
                let newEntry = pipelineEntryIn.newEntry;

                if (pipelineEntryIn.isShiftWindow) begin
                    alreadyExistEntry.leftBound = newEntry.leftBound;
                end
                else begin
                    newEntry.leftBound = alreadyExistEntry.leftBound;
                end

                if (pipelineEntryIn.isShiftOutOfBoundary) begin
                    if (pipelineEntryIn.isShiftWindow) begin
                        alreadyExistEntry.data = unpack(0);
                    end
                    else begin 
                        newEntry.data = unpack(0);
                    end
                end
                else begin
                    Bit#(TLog#(szData)) bitShiftCnt = zeroExtend(pipelineEntryIn.shiftAbsValue) << valueOf(TLog#(szStride));
                    if (pipelineEntryIn.isShiftWindow) begin
                        alreadyExistEntry.data = alreadyExistEntry.data >> bitShiftCnt;
                    end
                    else begin 
                        newEntry.data = newEntry.data >> bitShiftCnt;
                    end
                end

                newEntry.data = newEntry.data | alreadyExistEntry.data;

                let forwardEntry = BitmapWindowStorageInternalForwardEntry {
                    rowAddr: pipelineEntryIn.rowAddr,
                    entry: newEntry
                };
                forwardRegVec[selfChannelIdx] <= tagged Valid forwardEntry;

                let resp = BitmapWindowStorageUpdateResp {
                    rowAddr: pipelineEntryIn.rowAddr,
                    oldEntry: pipelineEntryIn.oldEntry,
                    newEntry: newEntry
                };
                respPipeOutQueueVec[selfChannelIdx].enq(tagged Valid resp);
            end
            else begin
                forwardRegVec[selfChannelIdx] <= tagged Invalid;
                respPipeOutQueueVec[selfChannelIdx].enq(tagged Invalid);
            end
        end
    endrule







    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_TWO); idx = idx + 1) begin
        reqPipeInVecInst[idx] = toPipeIn(reqPipeInQueueVec[idx]);
        respPipeOutVecInst[idx] = toPipeOut(respPipeOutQueueVec[idx]);
    end

    interface reqPipeInVec = reqPipeInVecInst;
    interface respPipeOutVec = respPipeOutVecInst;
endmodule
