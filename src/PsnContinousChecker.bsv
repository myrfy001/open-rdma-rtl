import Vector :: *;
import BuildVector :: *;
import FIFOF :: *;
import ConfigReg :: * ;

import PrimUtils :: *;
import BasicDataTypes :: *;

import RdmaHeaders :: *;
import PrioritySearchBuffer :: *;


import ConnectableF :: *;


typedef TSub#(PSN_WIDTH, TLog#(ACK_WINDOW_STRIDE)) PSN_MERGE_WINDOW_BOUNDARY_WIDTH;
typedef Bit#(PSN_MERGE_WINDOW_BOUNDARY_WIDTH) PsnMergeWindowBoundary;
typedef Bit#(TLog#(ACK_BITMAP_WIDTH)) PsnMergeWindowBitOffset;

typedef struct {
    tData                               data;
    tBoundary                           leftBound;
    KeyQP                               qpnKeyPart;
} BitmapWindowStorageEntry#(type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    QPN                                    qpn;
    PSN                                    psn;
} BitmapWindowStorageUpdateReq deriving(Bits, FShow);

typedef struct {
    tRowAddr                                    rowAddr;
    Bool                                        isShiftWindow;
    Bool                                        isShiftOutOfBoundary;
    tData                                       windowShiftedOutData;
    BitmapWindowStorageEntry#(tData, tBoundary) oldEntry;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageUpdateResp#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
    Bool isReset;
} BitmapWindowStorageStageOneToTwoPipelineEntry#(type tRowAddr, type tData, type tBoundary) deriving(Bits, FShow);

typedef struct {
    tRowAddr        rowAddr;
    BitmapWindowStorageEntry#(tData, tBoundary) newEntry;
} BitmapWindowStorageStageTwoToThreePipelineEntry#(type tRowAddr, type tData, type tBoundary, type tShiftOffset) deriving(Bits, FShow);



interface BitmapWindowStorage#(type tRowAddr, type tData, type tBoundary, numeric type szStride);
    interface PipeInB0#(BitmapWindowStorageUpdateReq) reqPipeIn;
    interface PipeOut#(BitmapWindowStorageUpdateResp#(tRowAddr, tData, tBoundary)) respPipeOut;
    
    interface PipeIn#(tRowAddr)                                         readOnlyReqPipeIn;
    interface PipeOut#(BitmapWindowStorageEntry#(tData, tBoundary))     readOnlyRespPipeOut;

    interface PipeIn#(tRowAddr) resetReqPipeIn;
    // interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface

module mkBitmapWindowStorage(BitmapWindowStorage#(tRowAddr, tData, tBoundary, szStride)) provisos (
        Bits#(tRowAddr, szRowAddr),
        Bits#(tData, szData),
        Bitwise#(tData),
        Literal#(tData),
        Bits#(tBoundary, szBoundary),
        Bounded#(tRowAddr),
        Literal#(tRowAddr),
        Eq#(tRowAddr),
        Arith#(tBoundary),
        Bitwise#(tBoundary),
        Ord#(tBoundary),
        Eq#(tBoundary),
        NumAlias#(TLog#(TDiv#(szData, szStride)), szShiftOffset),
        NumAlias#(TAdd#(1, szShiftOffset), szWideShiftOffset),
        Alias#(Bit#(szShiftOffset), tShiftOffset),
        Alias#(Bit#(szWideShiftOffset), tWideShiftOffset),
        Add#(a__, szShiftOffset, szBoundary),
        Add#(b__, szShiftOffset, TLog#(szData)),
        Add#(c__, szWideShiftOffset, szBoundary),
        Add#(d__, szWideShiftOffset, TLog#(szData)),
        FShow#(BitmapWindowStorageUpdateReq),
        Add#(f__, szBoundary, TLog#(szData)),
        Add#(e__, TLog#(szStride), SizeOf#(PSN)),
        Add#(szBoundary, g__, SizeOf#(PSN)),
        FShow#(tRowAddr),
        FShow#(BitmapWindowStorageEntry#(tData, tBoundary)),
        Add#(h__, QP_INDEX_WIDTH, szRowAddr)
    );

    PipeInAdapterB0#(BitmapWindowStorageUpdateReq) reqPipeInQueue <- mkPipeInAdapterB0;
    FIFOF#(BitmapWindowStorageUpdateResp#(tRowAddr, tData, tBoundary)) respPipeOutQueue <- mkFIFOF;

    FIFOF#(tRowAddr)                                        readOnlyReqPipeInQueue <- mkLFIFOF;
    FIFOF#(BitmapWindowStorageEntry#(tData, tBoundary))     readOnlyRespPipeOutQueue <- mkFIFOF;

    Vector#(NUMERIC_TYPE_TWO, AutoInferBram#(tRowAddr, BitmapWindowStorageEntry#(tData, tBoundary))) storage = newVector;
    storage[0] <- mkAutoInferBramUG(True, "init_bram_psn_merge_storage_ch0.bin");
    storage[1] <- mkAutoInferBramUG(True, "init_bram_psn_merge_storage_ch0.bin");


    // Pipeline Queues
    FIFOF#(BitmapWindowStorageStageOneToTwoPipelineEntry#(tRowAddr, tData, tBoundary)) stageOneToTwoPipelineQueue <- mkLFIFOF;
    FIFOF#(BitmapWindowStorageStageTwoToThreePipelineEntry#(tRowAddr, tData, tBoundary, tShiftOffset)) stageTwoToThreePipelineQueue <- mkLFIFOF;

    FIFOF#(void) readOnlyRespPipelineQueue <- mkLFIFOF;

    FIFOF#(tRowAddr) resetReqPipeInQ <- mkLFIFOF;

    PrioritySearchBuffer#(NUMERIC_TYPE_SIX, tRowAddr, BitmapWindowStorageEntry#(tData, tBoundary)) storageForwardBuffer <- mkPrioritySearchBuffer(valueOf(NUMERIC_TYPE_SIX));

    // rule printDebugInfo0;
    //     if (!respPipeOutQueueVec[0].notFull) $display("time=%0t, ", $time, "FullQueue: mkBitmapWindowStorage respPipeOutQueueVec[0]");
    //     if (!respPipeOutQueueVec[1].notFull) $display("time=%0t, ", $time, "FullQueue: mkBitmapWindowStorage respPipeOutQueueVec[1]");
    // endrule


    // Merge Pipeline Stage One
    rule sendBramQueryReqAndGenOneHotBitmap;
        if (reqPipeInQueue.notEmpty) begin
            let req = reqPipeInQueue.first;
            reqPipeInQueue.deq;

            tRowAddr rowAddr = unpack(zeroExtend(pack(getIndexQP(req.qpn))));
            storage[0].putReadReq(rowAddr);

            tBoundary leftBound = unpack(truncateLSB(req.psn));
            Bit#(TLog#(szStride)) offsetInStride = truncate(req.psn);
            tData bitmap = unpack(swapEndianBit(1 << offsetInStride));

            let pipelineEntryOut = BitmapWindowStorageStageOneToTwoPipelineEntry {
                rowAddr: rowAddr,
                newEntry: BitmapWindowStorageEntry{
                    leftBound: leftBound,
                    data: bitmap,
                    qpnKeyPart: getKeyQP(req.qpn)
                },
                isReset: False
            };
            stageOneToTwoPipelineQueue.enq(pipelineEntryOut);
        end
        else if (resetReqPipeInQ.notEmpty) begin
            resetReqPipeInQ.deq;
            let resetValue = BitmapWindowStorageEntry{
                leftBound: -1,
                data: -1,
                qpnKeyPart: 0
            };
            let pipelineEntryOut = BitmapWindowStorageStageOneToTwoPipelineEntry {
                rowAddr: resetReqPipeInQ.first,
                newEntry: resetValue,
                isReset: True
            };
            stageOneToTwoPipelineQueue.enq(pipelineEntryOut);
        end
        
        // $display("time=%0t", $time, "mkBitmapWindowStorage 1 sendBramQueryReq", 
        //         ", pipelineEntryIn=", fshow(pipelineEntryIn)
        // );
  

    endrule

    // Merge Pipeline Stage Two
    rule getBramQueryRespAndMergeThem;

        let pipelineEntryIn = stageOneToTwoPipelineQueue.first;
        stageOneToTwoPipelineQueue.deq;

        let entryFromBram <- storage[0].getReadResp;
        let entryFromForwardCacheMaybe <- storageForwardBuffer.search(pipelineEntryIn.rowAddr);

        let newestAlreadyExistEntry = entryFromBram;
        if (entryFromForwardCacheMaybe matches tagged Valid .entryFromForwardCache) begin
            newestAlreadyExistEntry = entryFromForwardCache;
        end

        let oldEntry = newestAlreadyExistEntry;

        tBoundary boundaryDelta = pipelineEntryIn.newEntry.leftBound - newestAlreadyExistEntry.leftBound;
        tBoundary boundaryDeltaAbs = getAbsValue(boundaryDelta);
        let isShiftWindow = boundaryDelta > 0;

        let newEntry = pipelineEntryIn.newEntry;
        tData windowShiftedOutData = -1;

        let isShiftOutOfBoundary = boundaryDeltaAbs > fromInteger(valueOf(TDiv#(szData, szStride)));

        if (isShiftWindow) begin
            newestAlreadyExistEntry.leftBound = newEntry.leftBound;
        end
        else begin
            newEntry.leftBound = newestAlreadyExistEntry.leftBound;
        end


        Bit#(TLog#(szData)) bitShiftCnt = zeroExtend(pack(boundaryDeltaAbs)) << valueOf(TLog#(szStride));
        tData allOneData = unpack(-1);
        if (isShiftOutOfBoundary) begin
            newestAlreadyExistEntry.data = unpack(0);
            windowShiftedOutData = unpack(0);
        end
        else if (isShiftWindow) begin
            let tmpToShift = {pack(newestAlreadyExistEntry.data), pack(allOneData)};
            tmpToShift = tmpToShift >> bitShiftCnt;
            newestAlreadyExistEntry.data = unpack(truncateLSB(tmpToShift));
            windowShiftedOutData = unpack(truncate(tmpToShift));
        end
        else begin 
            newEntry.data = newEntry.data >> bitShiftCnt;
        end


        newEntry.data = newEntry.data | newestAlreadyExistEntry.data;
        
        if (!pipelineEntryIn.isReset) begin
            let resp = BitmapWindowStorageUpdateResp {
                rowAddr                 : pipelineEntryIn.rowAddr,
                oldEntry                : oldEntry,
                windowShiftedOutData    : windowShiftedOutData,
                isShiftOutOfBoundary    : isShiftOutOfBoundary,
                isShiftWindow           : isShiftWindow,
                newEntry                : newEntry
            };
            respPipeOutQueue.enq(resp);
        end

        let bramWriteBackReq = BitmapWindowStorageStageTwoToThreePipelineEntry {
            rowAddr : pipelineEntryIn.rowAddr,
            newEntry: newEntry
        };
        stageTwoToThreePipelineQueue.enq(bramWriteBackReq);
        storageForwardBuffer.enq(pipelineEntryIn.rowAddr, newEntry);
    endrule

    // Merge Pipeline Stage Three
    rule doBramWriteBack;
        let writeBackReq = stageTwoToThreePipelineQueue.first;
        stageTwoToThreePipelineQueue.deq;

        storage[0].write(writeBackReq.rowAddr, writeBackReq.newEntry);
        storage[1].write(writeBackReq.rowAddr, writeBackReq.newEntry);

        // $display("time=%0t", $time, "mkBitmapWindowStorage 3 doBramWriteBack", 
        //         ", writeBackReq=", fshow(writeBackReq)
        // );
    endrule

    rule handleReadOnlyReq;
        let addr = readOnlyReqPipeInQueue.first;
        readOnlyReqPipeInQueue.deq;
        storage[1].putReadReq(addr);
        readOnlyRespPipelineQueue.enq(unpack(0));
    endrule

    rule handleReadOnlyResp;
        readOnlyRespPipelineQueue.deq;
        let resp <- storage[1].getReadResp;
        readOnlyRespPipeOutQueue.enq(resp);
    endrule

    interface reqPipeIn = toPipeInB0(reqPipeInQueue);
    interface respPipeOut = toPipeOut(respPipeOutQueue);

    interface readOnlyReqPipeIn     = toPipeIn(readOnlyReqPipeInQueue);
    interface readOnlyRespPipeOut   = toPipeOut(readOnlyRespPipeOutQueue);

    interface resetReqPipeIn = toPipeIn(resetReqPipeInQ);
endmodule



typedef struct {
    tRowAddr    rowAddr;
    tReq        reqData;
} AtomicUpdateStorageUpdateReq#(type tRowAddr, type tReq) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    tData       oldValue;
    tData       newValue;
} AtomicUpdateStorageUpdateResp#(type tRowAddr, type tData) deriving(Bits, FShow);

typedef struct {
    tData       data;
} AtomicUpdateStorageEntry#(type tData) deriving(Bits, FShow);

typedef struct {
    tRowAddr    rowAddr;
    tReq        reqData;
    Bool        isReset;
} AtomicUpdateStorageStageOneToTwoPipelineEntry#(type tRowAddr, type tReq) deriving(Bits, FShow);


typedef struct {
    tRowAddr                            rowAddr;
    AtomicUpdateStorageEntry#(tData)    newEntry;
} AtomicUpdateStorageStageTwoToThreePipelineEntry#(type tRowAddr, type tData) deriving(Bits, FShow);


interface AtomicUpdateStorage#(type tRowAddr, type tData, type tReq);
    interface PipeIn#(AtomicUpdateStorageUpdateReq#(tRowAddr, tReq)) reqPipeIn;
    interface PipeOut#(AtomicUpdateStorageUpdateResp#(tRowAddr, tData)) respPipeOut;
    
    interface PipeIn#(tRowAddr) readOnlyReqPipeIn;
    interface PipeOut#(tData)   readOnlyRespPipeOut;

    interface PipeIn#(tRowAddr) resetReqPipeIn;
    // interface PipeOut#(Bit#(0)) resetRespPipeOut;
endinterface

module mkAtomicUpdateStorage#(
        function tData updateFunc(tData oldVal, tReq reqVal),
        String initRamFileBaseName
    )(AtomicUpdateStorage#(tRowAddr, tData, tReq)) provisos (
        Bits#(tRowAddr, szRowAddr),
        Bits#(tData, szData),
        Bits#(tReq, szReq),
        Bounded#(tRowAddr),
        Literal#(tRowAddr),
        Eq#(tRowAddr),
        FShow#(AtomicUpdateStorageUpdateReq#(tRowAddr, tReq)),
        FShow#(AtomicUpdateStorageEntry#(tData))
    );

    FIFOF#(AtomicUpdateStorageUpdateReq#(tRowAddr, tReq)) reqPipeInQueue <- mkLFIFOF;
    FIFOF#(AtomicUpdateStorageUpdateResp#(tRowAddr, tData)) respPipeOutQueue <- mkFIFOF;

    FIFOF#(tRowAddr) readOnlyReqPipeInQueue    <- mkLFIFOF;
    FIFOF#(tData)    readOnlyRespPipeOutQueue  <- mkFIFOF;


    Vector#(NUMERIC_TYPE_TWO, AutoInferBram#(tRowAddr, AtomicUpdateStorageEntry#(tData))) storage = newVector;
    storage[0] <- mkAutoInferBramUG(True, initRamFileBaseName + "_ch0.bin");
    storage[1] <- mkAutoInferBramUG(True, initRamFileBaseName + "_ch0.bin");
    
    
    PrioritySearchBuffer#(NUMERIC_TYPE_SIX, tRowAddr, AtomicUpdateStorageEntry#(tData)) storageForwardBuffer <- mkPrioritySearchBuffer(valueOf(NUMERIC_TYPE_SIX));

    // Pipeline Queues

    FIFOF#(AtomicUpdateStorageStageOneToTwoPipelineEntry#(tRowAddr, tReq)) stageOneToTwoPipelineQueue <- mkLFIFOF;
    FIFOF#(AtomicUpdateStorageStageTwoToThreePipelineEntry#(tRowAddr, tData)) stageTwoToThreePipelineQueue <- mkLFIFOF;
    FIFOF#(void) readOnlyRespPipelineQueue <- mkLFIFOF;


    FIFOF#(tRowAddr) resetReqPipeInQ <- mkLFIFOF;

    // Merge Pipeline Stage One
    rule sendBramQueryReq;
        
        if (reqPipeInQueue.notEmpty) begin
            let pipelineEntryIn = reqPipeInQueue.first;
            reqPipeInQueue.deq;

            storage[0].putReadReq(pipelineEntryIn.rowAddr);

            let pipelineEntryOut = AtomicUpdateStorageStageOneToTwoPipelineEntry {
                rowAddr     : pipelineEntryIn.rowAddr,
                reqData     : pipelineEntryIn.reqData,
                isReset     : False
            };
            stageOneToTwoPipelineQueue.enq(pipelineEntryOut);
            
            // $display("time=%0t", $time, "mkAtomicUpdateStorage 1 sendBramQueryReq", 
            //         ", pipelineEntryIn=", fshow(pipelineEntryIn)
            // );
        end
        else if (resetReqPipeInQ.notEmpty) begin
            resetReqPipeInQ.deq;
            let resetValue = 0;
            let pipelineEntryOut = AtomicUpdateStorageStageOneToTwoPipelineEntry {
                rowAddr: resetReqPipeInQ.first,
                reqData: unpack(resetValue),
                isReset: True
            };
            stageOneToTwoPipelineQueue.enq(pipelineEntryOut);
        end
    endrule

    // // Merge Pipeline Stage Two
    // rule getBramQueryRespAndMergeThem;

    //     let pipelineEntryIn = stageOneToTwoPipelineQueue.first;
    //     stageOneToTwoPipelineQueue.deq;

    //     let entryFromBram <- storage[0].getReadResp;
    //     let entryFromForwardCacheMaybe <- storageForwardBuffer.search(pipelineEntryIn.rowAddr);

    //     let newestAlreadyExistEntry = entryFromBram;
    //     if (entryFromForwardCacheMaybe matches tagged Valid .entryFromForwardCache) begin
    //         newestAlreadyExistEntry = entryFromForwardCache;
    //     end
    //     let oldEntry = newestAlreadyExistEntry;

    //     let newEntry = newestAlreadyExistEntry;
    //     newEntry.data = updateFunc(newestAlreadyExistEntry.data, pipelineEntryIn.reqData);
                
    //     if (!pipelineEntryIn.isReset) begin
    //         let resp = AtomicUpdateStorageUpdateResp {
    //             rowAddr : pipelineEntryIn.rowAddr,
    //             oldValue: oldEntry.data,
    //             newValue: newEntry.data
    //         };
    //         respPipeOutQueue.enq(resp);
    //     end

    //     let bramWriteBackReq = AtomicUpdateStorageStageTwoToThreePipelineEntry {
    //         rowAddr: pipelineEntryIn.rowAddr,
    //         newEntry: newEntry
    //     };
    //     stageTwoToThreePipelineQueue.enq(bramWriteBackReq);
    //     storageForwardBuffer.enq(pipelineEntryIn.rowAddr, newEntry);

    //     // $display("time=%0t", $time, "mkAtomicUpdateStorage 2 doMerge", 
    //     //         ", pipelineEntryIn=", fshow(pipelineEntryIn),
    //     //         ", resp=", fshow(resp)
    //     // ); 

    // endrule

    // // Merge Pipeline Stage Three
    // rule doBramWriteBack;

    //     let writeBackReq = stageTwoToThreePipelineQueue.first;
    //     stageTwoToThreePipelineQueue.deq;

    //     storage[0].write(writeBackReq.rowAddr, writeBackReq.newEntry);
    //     storage[1].write(writeBackReq.rowAddr, writeBackReq.newEntry);
        
    //     // $display("time=%0t", $time, "mkAtomicUpdateStorage 3 doBramWriteBack", 
    //     //         ", writeBackReq=", fshow(writeBackReq)
    //     // );
    // endrule

    
    rule handleReadOnlyReq;
        let addr = readOnlyReqPipeInQueue.first;
        readOnlyReqPipeInQueue.deq;
        storage[1].putReadReq(addr);
        readOnlyRespPipelineQueue.enq(unpack(0));
    endrule

    rule handleReadOnlyResp;
        readOnlyRespPipelineQueue.deq;
        let resp <- storage[1].getReadResp;
        readOnlyRespPipeOutQueue.enq(resp.data);
    endrule

    interface reqPipeIn = toPipeIn(reqPipeInQueue);
    interface respPipeOut = toPipeOut(respPipeOutQueue);

    interface readOnlyReqPipeIn     = toPipeIn(readOnlyReqPipeInQueue);
    interface readOnlyRespPipeOut   = toPipeOut(readOnlyRespPipeOutQueue);

    interface resetReqPipeIn = toPipeIn(resetReqPipeInQ);
endmodule