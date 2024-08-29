import Connectable :: *;
import FIFOF :: *;

import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DataTypes :: *;

typedef struct {
    tData              data;
    tByteNum           byteNum;
    tByteIdx           startByteIdx;
    Bool               isFirst;
    Bool               isLast;
} StreamShifterStream#(type tData, type tByteNum, type tByteIdx) deriving (FShow, Bits);

interface StreamShifter#(type tData, type tByteNum, type tByteIdx);
    interface PipeIn#(tByteNum) offsetPipeIn;
    interface PipeIn#(StreamShifterStream#(tData, tByteNum, tByteIdx)) streamPipeIn;
    interface PipeOut#(StreamShifterStream#(tData, tByteNum, tByteIdx)) streamPipeOut;
endinterface


typedef enum {
    BiDirectionStreamShifterLeftShiftStateIdle=0,
    BiDirectionStreamShifterLeftShiftStateOutputBeat=1,
    BiDirectionStreamShifterLeftShiftStateOutputExtraBeat=2
} BiDirectionStreamShifterLeftShiftState deriving(FShow, Eq, Bits);

typedef enum {
    BiDirectionStreamShifterRightShiftStateOutputBeat=0,
    BiDirectionStreamShifterRightShiftStateOutputExtraBeat=1
} BiDirectionStreamShifterRightShiftState deriving(FShow, Eq, Bits);

typedef struct {
    tDataStream ds;
    tByteIdx offset;
} BiDirectionStreamShifterPipelineEntry#(type tDataStream, type tByteIdx) deriving(FShow, Eq, Bits);

typedef struct {
    tByteNum           byteNum;
    tByteIdx           startByteIdx;
    Bool               isFirst;
    Bool               isLast;
} DataStreamMeta#(type tByteNum, type tByteIdx) deriving(FShow, Eq, Bits);

typedef struct {
    Tuple2#(tData, tData)                   concatData;
    tByteIdx                                offset;
    DataStreamMeta#(tByteNum, tByteIdx)     meta;
} ShiftIntermediateData#(type tData, type tByteNum, type tByteIdx) deriving(FShow, Eq, Bits);


// ========== IMPORTANT! =======================
// Must ensure the first beat is RIGHT aligned.
// =============================================
module mkBiDirectionStreamShifter(StreamShifter#(tData, tByteNum, tByteIdx)) provisos (
        Bits#(tData, szData),
        NumAlias#(TDiv#(szData, BYTE_WIDTH), szDataInByte),
        NumAlias#(TLog#(szDataInByte), szByteIdx),
        NumAlias#(TAdd#(1, szByteIdx), szByteNum),
        Alias#(Bit#(szByteIdx), tByteIdx),
        Alias#(Bit#(szByteNum), tByteNum),
        Alias#(StreamShifterStream#(tData, tByteNum, tByteIdx), tDataStream),
        Alias#(BiDirectionStreamShifterPipelineEntry#(tDataStream, tByteIdx), tBiDirectionStreamShifterPipelineEntry),
        Alias#(ShiftIntermediateData#(tData, tByteNum, tByteIdx), tShiftIntermediateData),
        NumAlias#(TSub#(TLog#(szData), 2), szShiftOffsetForLowerPartShift),
        NumAlias#(TLog#(szData), szShiftOffsetForHigherPartShift),
        Add#(a__, szByteIdx, szShiftOffsetForLowerPartShift),
        FShow#(tData),
        FShow#(tBiDirectionStreamShifterPipelineEntry)
    );
    FIFOF#(tByteNum) offsetPipeInQ <- mkFIFOF;
    FIFOF#(tDataStream) streamPipeInQ <- mkFIFOF;
    FIFOF#(tDataStream) streamPipeOutQ <- mkFIFOF;


    FIFOF#(tBiDirectionStreamShifterPipelineEntry) leftShiftPipeQ <- mkFIFOF;
    FIFOF#(tBiDirectionStreamShifterPipelineEntry) rightShiftPipeQ <- mkFIFOF;

    FIFOF#(tShiftIntermediateData) doLeftShiftPipeQ <- mkFIFOF;
    FIFOF#(tShiftIntermediateData) doLeftShiftPipeQ2 <- mkFIFOF;
    FIFOF#(tDataStream) leftShiftResultQ <- mkFIFOF;
    FIFOF#(tShiftIntermediateData) doRightShiftPipeQ <- mkFIFOF;
    FIFOF#(tShiftIntermediateData) doRightShiftPipeQ2 <- mkFIFOF;
    FIFOF#(tDataStream) rightShiftResultQ <- mkFIFOF;

    FIFOF#(Bool) keepOrderQ <- mkSizedFIFOF(4);

    Reg#(tBiDirectionStreamShifterPipelineEntry) leftShiftPrevDataReg <- mkRegU;
    Reg#(BiDirectionStreamShifterLeftShiftState) leftShiftStateReg <- mkReg(BiDirectionStreamShifterLeftShiftStateIdle);

    Reg#(tBiDirectionStreamShifterPipelineEntry) rightShiftPrevDataReg <- mkRegU;
    Reg#(BiDirectionStreamShifterRightShiftState) rightShiftStateReg <- mkReg(BiDirectionStreamShifterRightShiftStateOutputBeat);

    tData zeroData = unpack(0);

    if (valueOf(szByteIdx) > 2) begin
        rule doLeftShift1;
            let req = doLeftShiftPipeQ.first;
            doLeftShiftPipeQ.deq;
            // only shift by higher 2 bits
            Bit#(szShiftOffsetForHigherPartShift) shiftCnt = 0;
            shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-1] = req.offset[valueOf(szByteIdx)-1];
            shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-2] = req.offset[valueOf(szByteIdx)-2];
            req.concatData = unpack(pack(req.concatData) << shiftCnt);
            doLeftShiftPipeQ2.enq(req);
        endrule

        rule doLeftShift2;
            let req = doLeftShiftPipeQ2.first;
            doLeftShiftPipeQ2.deq;

            // only shift by lower bits
            Bit#(szShiftOffsetForLowerPartShift) shiftCnt = unpack(zeroExtend(pack(req.offset)));
            shiftCnt = shiftCnt << 3; // convert byte offset to bit offset
            tData outputData = unpack(truncateLSB(pack(req.concatData) << shiftCnt));  
            leftShiftResultQ.enq(StreamShifterStream{
                data: outputData,
                byteNum: req.meta.byteNum,
                startByteIdx: req.meta.startByteIdx,
                isFirst: req.meta.isFirst,
                isLast: req.meta.isLast
            });
        endrule
    end
    else begin
        rule doPanic1;
            immFail("not support too narrow DataStream", $format(""));
        endrule
    end

    if (valueOf(szByteIdx) > 2) begin
        rule doRightShift;
            let req = doRightShiftPipeQ.first;
            doRightShiftPipeQ.deq;
            // only shift by higher 2 bits
            Bit#(szShiftOffsetForHigherPartShift) shiftCnt = 0;
            shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-1] = req.offset[valueOf(szByteIdx)-1];
            shiftCnt[valueOf(szShiftOffsetForHigherPartShift)-2] = req.offset[valueOf(szByteIdx)-2];
            req.concatData = unpack(pack(req.concatData) >> shiftCnt); 
            doRightShiftPipeQ2.enq(req);
        endrule

        rule doRightShift2;
            let req = doRightShiftPipeQ2.first;
            doRightShiftPipeQ2.deq;
            // only shift by lower bits
            Bit#(szShiftOffsetForLowerPartShift) shiftCnt = unpack(zeroExtend(pack(req.offset)));
            shiftCnt = shiftCnt << 3; // convert byte offset to bit offset
            tData outputData = unpack(truncate(pack(req.concatData) >> shiftCnt)); 
            rightShiftResultQ.enq(StreamShifterStream{
                data: outputData,
                byteNum: req.meta.byteNum,
                startByteIdx: req.meta.startByteIdx,
                isFirst: req.meta.isFirst,
                isLast: req.meta.isLast
            });
        endrule
    end
    else begin
        rule doPanic2;
            immFail("not support too narrow DataStream", $format(""));
        endrule
    end

    rule doFinalOutput;
        let isShiftRight = keepOrderQ.first;
        if (isShiftRight) begin
            streamPipeOutQ.enq(rightShiftResultQ.first);
            rightShiftResultQ.deq;
            if (rightShiftResultQ.first.isLast) begin
                keepOrderQ.deq;
            end
        end
        else begin
            streamPipeOutQ.enq(leftShiftResultQ.first);
            leftShiftResultQ.deq;
            if (leftShiftResultQ.first.isLast) begin
                keepOrderQ.deq;
            end
        end
    endrule

    rule decideDirection;
        let offset = offsetPipeInQ.first;
        let ds = streamPipeInQ.first;
        streamPipeInQ.deq;
        if (ds.isLast) begin
            offsetPipeInQ.deq;
        end

        // positive number means shift right and negative means shift left
        let isNegativeOffset = msb(offset) == 1;
        let isShiftRight = !isNegativeOffset;
        let absOffset = getAbsValue(offset);

        let shiftEntry = BiDirectionStreamShifterPipelineEntry{
            ds: ds,
            offset: truncate(absOffset)
        };

        if (ds.isFirst) begin
            keepOrderQ.enq(isShiftRight);
        end

        if (isShiftRight) begin
            rightShiftPipeQ.enq(shiftEntry);
        end
        else begin
            immAssert(absOffset != 0, "The offset should not be zero, left shift path does not handle 0 offset, 0 offset should be handled by right shift path", $format(""));
            leftShiftPipeQ.enq(shiftEntry);
        end
        // $display(
        //     "time=%0t: ", $time, toGreen("decideDirection"),
        //     toBlue(", offset="), fshow(offset),
        //     toBlue(", ds="), fshow(ds)
        // );
    endrule
    
    // (* conflict_free = "shiftLeftIdle, \
    //                     shiftLeftOptput, \
    //                     shiftLeftOptputExtra, \
    //                     shiftRightOptput, \
    //                     shiftRightOptputExtra" *)
    rule shiftLeftIdle if (leftShiftStateReg == BiDirectionStreamShifterLeftShiftStateIdle);
        let pipelineEntry = leftShiftPipeQ.first;
        leftShiftPipeQ.deq;
        leftShiftPrevDataReg <= pipelineEntry;

        immAssert(pipelineEntry.ds.isFirst, "this rule is only for first beat", $format(""));

        if (pipelineEntry.ds.isLast) begin
            // only have one beat, no need to concat other beat
            let interShiftData = ShiftIntermediateData{
                concatData: tuple2(pipelineEntry.ds.data, zeroData),
                offset: pipelineEntry.offset,
                meta: DataStreamMeta{
                    byteNum: pipelineEntry.ds.byteNum,
                    startByteIdx: pipelineEntry.ds.startByteIdx + pipelineEntry.offset,
                    isFirst: pipelineEntry.ds.isFirst,
                    isLast: pipelineEntry.ds.isLast
                }
            };
            doLeftShiftPipeQ.enq(interShiftData);
            // $display(
            //     "time=%0t: ", $time, toGreen("shiftLeftIdle forward single beat data"),
            //     toBlue(", pipelineEntry="), fshow(pipelineEntry)
            // );
        end
        else begin
            leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateOutputBeat;
        end
        // $display(
        //     "time=%0t: ", $time, toGreen("shiftLeftIdle"),
        //     toBlue(", pipelineEntry="), fshow(pipelineEntry)
        // );
    endrule

    rule shiftLeftOptput if (leftShiftStateReg == BiDirectionStreamShifterLeftShiftStateOutputBeat);
        let pipelineEntry = leftShiftPipeQ.first;
        leftShiftPipeQ.deq;

        tByteNum byteNum = leftShiftPrevDataReg.ds.byteNum;
        let inputBeatCanFitInOutputBeat = (pipelineEntry.ds.byteNum <= unpack(zeroExtend(leftShiftPrevDataReg.offset)));
        let isFirst = leftShiftPrevDataReg.ds.isFirst;
        let isLast = inputBeatCanFitInOutputBeat && pipelineEntry.ds.isLast;
        if (inputBeatCanFitInOutputBeat) begin
            if (leftShiftPrevDataReg.ds.isFirst) begin
                byteNum = byteNum + pipelineEntry.ds.byteNum;
            end
            else begin
                byteNum = byteNum + pipelineEntry.ds.byteNum - zeroExtend(pipelineEntry.offset);
            end
            
            immAssert(
                pipelineEntry.ds.isLast,
                "Since the inputBeatCanFitInOutputBeat is True, the new input beat must be last beat",
                $format("pipelineEntry=", fshow(pipelineEntry), "leftShiftPrevDataReg=", fshow(leftShiftPrevDataReg))
            );
        end
        else begin
            if (isFirst) begin
                byteNum = byteNum + zeroExtend(leftShiftPrevDataReg.offset);
            end
            else begin
                byteNum = fromInteger(valueOf(szDataInByte));
                immAssert(
                    !isFirst && !isLast,
                    "this branch must output middle beat, but isFirst or isLast is True",
                    $format("isFirst=", fshow(isFirst), "isLast=", fshow(isLast))
                );
            end
        end


        let startByteIdx = isFirst ? ( inputBeatCanFitInOutputBeat ? pipelineEntry.offset - truncate(pipelineEntry.ds.byteNum) : 0 ) : 0;

        let interShiftData = ShiftIntermediateData{
            concatData: tuple2(leftShiftPrevDataReg.ds.data, pipelineEntry.ds.data),
            offset: leftShiftPrevDataReg.offset,
            meta: DataStreamMeta{
                byteNum: byteNum,
                startByteIdx: startByteIdx,
                isFirst: isFirst,
                isLast: isLast
            }
        };
        doLeftShiftPipeQ.enq(interShiftData);

        if (pipelineEntry.ds.isLast && !isLast) begin
            leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateOutputExtraBeat;
        end
        else if (isLast) begin
            leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateIdle;
        end
        
        leftShiftPrevDataReg <= pipelineEntry;

        // $display(
        //     "time=%0t:", $time, " shiftLeftOptput",
        //     toBlue(", pipelineEntry="), fshow(pipelineEntry),
        //     toBlue(", leftShiftPrevDataReg="), fshow(leftShiftPrevDataReg),
        //     toBlue(", interShiftData="), fshow(interShiftData)
        // );

    endrule

    rule shiftLeftOptputExtra if (leftShiftStateReg == BiDirectionStreamShifterLeftShiftStateOutputExtraBeat);

        let interShiftData = ShiftIntermediateData{
            concatData: tuple2(leftShiftPrevDataReg.ds.data, zeroData),
            offset: leftShiftPrevDataReg.offset,
            meta: DataStreamMeta{
                byteNum: leftShiftPrevDataReg.ds.byteNum - zeroExtend(leftShiftPrevDataReg.offset),
                startByteIdx: 0,
                isFirst: False,
                isLast: True
            }
        };
        doLeftShiftPipeQ.enq(interShiftData);


        if (leftShiftPipeQ.notEmpty) begin 
            let pipelineEntry = leftShiftPipeQ.first;
            leftShiftPrevDataReg <= pipelineEntry;
            if (pipelineEntry.ds.isFirst && pipelineEntry.ds.isLast) begin
                // only have one beat, no need to concat other beat
                leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateIdle;
            end
            else begin
                leftShiftPipeQ.deq;
                leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateOutputBeat;
            end
        end
        else begin
            leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateIdle;
        end
        // $display(
        //     "time=%0t:", $time, " shiftLeftOptputExtra",
        //     toBlue(", leftShiftPrevDataReg="), fshow(leftShiftPrevDataReg),
        //     toBlue(", interShiftData="), fshow(interShiftData)
        // );
    endrule


    rule shiftRightOptput if (rightShiftStateReg == BiDirectionStreamShifterRightShiftStateOutputBeat);
        let pipelineEntry = rightShiftPipeQ.first;
        rightShiftPipeQ.deq;
        rightShiftPrevDataReg <= pipelineEntry;     

        let inputBeatCanFitInOutputBeatForNonOnlyBeat = (
            pipelineEntry.ds.byteNum + unpack(zeroExtend(pipelineEntry.offset)) <= fromInteger(valueOf(szDataInByte)));

        let inputBeatCanFitInOutputBeatForOnlyBeat = (zeroExtend(pipelineEntry.ds.startByteIdx) >= pipelineEntry.offset);
        
        let isOnlyBeat = pipelineEntry.ds.isFirst && pipelineEntry.ds.isLast;
        let isFirst = pipelineEntry.ds.isFirst;
        let isLast = isOnlyBeat ? inputBeatCanFitInOutputBeatForOnlyBeat : inputBeatCanFitInOutputBeatForNonOnlyBeat && pipelineEntry.ds.isLast;
        
        let shiftWillChangeByteNum = pipelineEntry.ds.startByteIdx < pipelineEntry.offset;

        tByteNum byteNum;
        if (isFirst) begin
            if (shiftWillChangeByteNum) begin
                byteNum = pipelineEntry.ds.byteNum + zeroExtend(pipelineEntry.ds.startByteIdx) - zeroExtend(pipelineEntry.offset);
            end
            else begin
                byteNum = pipelineEntry.ds.byteNum;
            end
        end
        else begin
            if (isLast) begin
                byteNum = pipelineEntry.ds.byteNum + zeroExtend(pipelineEntry.offset);
            end
            else begin
                byteNum = fromInteger(valueOf(szDataInByte));
                immAssert(
                    !isFirst && !isLast,
                    "this branch must output middle beat, but isFirst or isLast is True",
                    $format("isFirst=", fshow(isFirst), "isLast=", fshow(isLast))
                );
            end
        end
        let startByteIdx = shiftWillChangeByteNum ? 0 : pipelineEntry.ds.startByteIdx - zeroExtend(pipelineEntry.offset);

        let interShiftData = ShiftIntermediateData{
            concatData: pipelineEntry.ds.isFirst ? tuple2(zeroData, pipelineEntry.ds.data) : tuple2(rightShiftPrevDataReg.ds.data, pipelineEntry.ds.data),
            offset: pipelineEntry.offset,
            meta: DataStreamMeta{
                byteNum: byteNum,
                startByteIdx: startByteIdx,
                isFirst: isFirst,
                isLast: isLast
            }
        };
        doRightShiftPipeQ.enq(interShiftData);

        if ((pipelineEntry.ds.isLast && !inputBeatCanFitInOutputBeatForNonOnlyBeat) || (isOnlyBeat && !inputBeatCanFitInOutputBeatForOnlyBeat)) begin
            rightShiftStateReg <= BiDirectionStreamShifterRightShiftStateOutputExtraBeat;
        end
        // $display(
        //     "time=%0t: ", $time, toGreen("shiftRightOptput"),
        //     toBlue(", pipelineEntry="), fshow(pipelineEntry),
        //     toBlue(", rightShiftPrevDataReg="), fshow(leftShiftPrevDataReg),
        //     toBlue(", interShiftData="), fshow(interShiftData)
        // );
    endrule


    rule shiftRightOptputExtra if (rightShiftStateReg == BiDirectionStreamShifterRightShiftStateOutputExtraBeat);

        tByteNum byteNum = rightShiftPrevDataReg.ds.isFirst ? (
            zeroExtend(rightShiftPrevDataReg.offset) - zeroExtend(rightShiftPrevDataReg.ds.startByteIdx)
        ) : ( zeroExtend(rightShiftPrevDataReg.offset) - (fromInteger(valueOf(szDataInByte)) - rightShiftPrevDataReg.ds.byteNum));

        let interShiftData = ShiftIntermediateData{
            concatData: tuple2(rightShiftPrevDataReg.ds.data, zeroData),
            offset: rightShiftPrevDataReg.offset,
            meta: DataStreamMeta{
                byteNum: byteNum,
                startByteIdx: 0,
                isFirst: False,
                isLast: True
            }
        };
        doRightShiftPipeQ.enq(interShiftData);

        rightShiftStateReg <= BiDirectionStreamShifterRightShiftStateOutputBeat;
        // $display(
        //     "time=%0t: ", $time, toGreen("shiftRightOptputExtra"),
        //     toBlue(", rightShiftPrevDataReg="), fshow(rightShiftPrevDataReg),
        //     toBlue(", interShiftData="), fshow(interShiftData)
        // );
    endrule

    interface offsetPipeIn  = toPipeIn(offsetPipeInQ);
    interface streamPipeIn  = toPipeIn(streamPipeInQ);
    interface streamPipeOut = toPipeOut(streamPipeOutQ);
endmodule
