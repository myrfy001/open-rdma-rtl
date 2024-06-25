import Connectable :: *;
import FIFOF :: *;

import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DataTypes :: *;


interface StreamShifter;
    interface PipeIn#(DataBusSignedShiftOffset) offsetPipeIn;
    interface PipeIn#(DataStream) streamPipeIn;
    interface PipeOut#(DataStream) streamPipeOut;
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
    DataStream ds;
    DataBusShiftOffset offset;
} BiDirectionStreamShifterPipelineEntry deriving(FShow, Eq, Bits);


// ========== IMPORTANT! =======================
// Must ensure the first beat is RIGHT aligned.
// =============================================
(* synthesize *)
module mkBiDirectionStreamShifter(StreamShifter);
    FIFOF#(DataBusSignedShiftOffset) offsetPipeInQ <- mkFIFOF;
    FIFOF#(DataStream) streamPipeInQ <- mkFIFOF;
    FIFOF#(DataStream) streamPipeOutQ <- mkFIFOF;

    FIFOF#(BiDirectionStreamShifterPipelineEntry) leftShiftPipeQ <- mkFIFOF;
    FIFOF#(BiDirectionStreamShifterPipelineEntry) rightShiftPipeQ <- mkFIFOF;

    Reg#(BiDirectionStreamShifterPipelineEntry) leftShiftPrevDataReg <- mkRegU;
    Reg#(BiDirectionStreamShifterLeftShiftState) leftShiftStateReg <- mkReg(BiDirectionStreamShifterLeftShiftStateIdle);

    Reg#(BiDirectionStreamShifterPipelineEntry) rightShiftPrevDataReg <- mkRegU;
    Reg#(BiDirectionStreamShifterRightShiftState) rightShiftStateReg <- mkReg(BiDirectionStreamShifterRightShiftStateOutputBeat);


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

        if (isShiftRight) begin
            rightShiftPipeQ.enq(shiftEntry);
        end
        else begin
            immAssert(absOffset != 0, "The offset should not be zero, left shift path does not handle 0 offset, 0 offset should be handled by right shift path", $format(""));
            leftShiftPipeQ.enq(shiftEntry);
        end
        // $display(
        //     "time=%0t:", $time, " decideDirection",
        //     ", offset=", fshow(offset),
        //     ", ds=", fshow(ds)
        // );
    endrule
    
    (* conflict_free = "shiftLeftIdle, \
                        shiftLeftOptput, \
                        shiftLeftOptputExtra, \
                        shiftRightOptput, \
                        shiftRightOptputExtra" *)
    rule shiftLeftIdle if (leftShiftStateReg == BiDirectionStreamShifterLeftShiftStateIdle);
        let pipelineEntry = leftShiftPipeQ.first;
        leftShiftPipeQ.deq;
        leftShiftPrevDataReg <= pipelineEntry;

        immAssert(pipelineEntry.ds.isFirst, "this rule is only for first beat", $format(""));

        if (pipelineEntry.ds.isLast) begin
            // only have one beat, no need to concat other beat
            pipelineEntry.ds.data = pipelineEntry.ds.data << {pipelineEntry.offset, 3'h0};
            pipelineEntry.ds.startByteIdx = pipelineEntry.ds.startByteIdx + pipelineEntry.offset;
            streamPipeOutQ.enq(pipelineEntry.ds);
            // $display(
            //     "time=%0t:", $time, " shiftLeftIdle forward single beat data",
            //     ", pipelineEntry=", fshow(pipelineEntry)
            // );
        end
        else begin
            leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateOutputBeat;
        end
        // $display(
        //     "time=%0t:", $time, " shiftLeftIdle",
        //     ", pipelineEntry=", fshow(pipelineEntry)
        // );
    endrule

    rule shiftLeftOptput if (leftShiftStateReg == BiDirectionStreamShifterLeftShiftStateOutputBeat);
        let pipelineEntry = leftShiftPipeQ.first;
        leftShiftPipeQ.deq;

        DATA outputData = truncateLSB({leftShiftPrevDataReg.ds.data, pipelineEntry.ds.data} << {leftShiftPrevDataReg.offset, 3'h0});

        ByteEnBitNum byteNum = leftShiftPrevDataReg.ds.byteNum;
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
                byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
                immAssert(
                    !isFirst && !isLast,
                    "this branch must output middle beat, but isFirst or isLast is True",
                    $format("isFirst=", fshow(isFirst), "isLast=", fshow(isLast))
                );
            end
        end


        let startByteIdx = isFirst ? ( inputBeatCanFitInOutputBeat ? pipelineEntry.offset - truncate(pipelineEntry.ds.byteNum) : 0 ) : 0;
 
        let outDs = DataStream {
            data: outputData,
            byteNum: byteNum,
            startByteIdx: startByteIdx, 
            isFirst: isFirst,
            isLast: isLast
        };

        if (pipelineEntry.ds.isLast && !isLast) begin
            leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateOutputExtraBeat;
        end
        else if (isLast) begin
            leftShiftStateReg <= BiDirectionStreamShifterLeftShiftStateIdle;
        end
        streamPipeOutQ.enq(outDs);
        leftShiftPrevDataReg <= pipelineEntry;

        // $display(
        //     "time=%0t:", $time, " shiftLeftOptput",
        //     ", pipelineEntry=", fshow(pipelineEntry),
        //     ", leftShiftPrevDataReg=", fshow(leftShiftPrevDataReg),
        //     ", outDs=", fshow(outDs)
        // );

    endrule

    rule shiftLeftOptputExtra if (leftShiftStateReg == BiDirectionStreamShifterLeftShiftStateOutputExtraBeat);
        DATA outputData = truncateLSB(leftShiftPrevDataReg.ds.data << {leftShiftPrevDataReg.offset, 3'h0});
        let outDs = DataStream {
            data: outputData,
            byteNum: leftShiftPrevDataReg.ds.byteNum - zeroExtend(leftShiftPrevDataReg.offset),
            startByteIdx: 0,
            isFirst: False,
            isLast: True
        };
        streamPipeOutQ.enq(outDs);

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
        //     ", leftShiftPrevDataReg=", fshow(leftShiftPrevDataReg),
        //     ", outDs=", fshow(outDs)
        // );
    endrule


    rule shiftRightOptput if (rightShiftStateReg == BiDirectionStreamShifterRightShiftStateOutputBeat);
        let pipelineEntry = rightShiftPipeQ.first;
        rightShiftPipeQ.deq;
        rightShiftPrevDataReg <= pipelineEntry;
        DATA outputData = pipelineEntry.ds.isFirst ?
             pipelineEntry.ds.data >> {pipelineEntry.offset, 3'h0} : 
             truncate({rightShiftPrevDataReg.ds.data, pipelineEntry.ds.data} >> {pipelineEntry.offset, 3'h0});
        

        let inputBeatCanFitInOutputBeatForNonOnlyBeat = (
            pipelineEntry.ds.byteNum + unpack(zeroExtend(pipelineEntry.offset)) <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)));

        let inputBeatCanFitInOutputBeatForOnlyBeat = (zeroExtend(pipelineEntry.ds.startByteIdx) >= pipelineEntry.offset);
        
        let isOnlyBeat = pipelineEntry.ds.isFirst && pipelineEntry.ds.isLast;
        let isFirst = pipelineEntry.ds.isFirst;
        let isLast = isOnlyBeat ? inputBeatCanFitInOutputBeatForOnlyBeat : inputBeatCanFitInOutputBeatForNonOnlyBeat && pipelineEntry.ds.isLast;
        
        let shiftWillChangeByteNum = pipelineEntry.ds.startByteIdx < pipelineEntry.offset;

        ByteEnBitNum byteNum;
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
                byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
                immAssert(
                    !isFirst && !isLast,
                    "this branch must output middle beat, but isFirst or isLast is True",
                    $format("isFirst=", fshow(isFirst), "isLast=", fshow(isLast))
                );
            end
        end
        let startByteIdx = shiftWillChangeByteNum ? 0 : pipelineEntry.ds.startByteIdx - zeroExtend(pipelineEntry.offset);

        let outDs = DataStream {
            data: outputData,
            byteNum: byteNum,
            startByteIdx: startByteIdx,
            isFirst: isFirst,
            isLast: isLast
        };
        streamPipeOutQ.enq(outDs);

        if ((pipelineEntry.ds.isLast && !inputBeatCanFitInOutputBeatForNonOnlyBeat) || (isOnlyBeat && !inputBeatCanFitInOutputBeatForOnlyBeat)) begin
            rightShiftStateReg <= BiDirectionStreamShifterRightShiftStateOutputExtraBeat;
        end
        $display(
            "time=%0t:", $time, " shiftRightOptput",
            ", pipelineEntry=", fshow(pipelineEntry),
            ", rightShiftPrevDataReg=", fshow(leftShiftPrevDataReg),
            ", outDs=", fshow(outDs)
        );
    endrule


    rule shiftRightOptputExtra if (rightShiftStateReg == BiDirectionStreamShifterRightShiftStateOutputExtraBeat);
        DATA zeroData = unpack(0);
        DATA outputData = truncate({rightShiftPrevDataReg.ds.data, zeroData} >> {rightShiftPrevDataReg.offset, 3'h0});

        ByteEnBitNum byteNum = rightShiftPrevDataReg.ds.isFirst ? (
            zeroExtend(rightShiftPrevDataReg.offset) - zeroExtend(rightShiftPrevDataReg.ds.startByteIdx)
        ) : ( zeroExtend(rightShiftPrevDataReg.offset) - (fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - rightShiftPrevDataReg.ds.byteNum));

        let outDs = DataStream {
            data: outputData,
            byteNum: byteNum,
            startByteIdx: 0,
            isFirst: False,
            isLast: True
        };
        streamPipeOutQ.enq(outDs);

        rightShiftStateReg <= BiDirectionStreamShifterRightShiftStateOutputBeat;
        $display(
            "time=%0t:", $time, " shiftRightOptputExtra",
            ", rightShiftPrevDataReg=", fshow(rightShiftPrevDataReg),
            ", outDs=", fshow(outDs)
        );
    endrule

    interface offsetPipeIn  = toPipeIn(offsetPipeInQ);
    interface streamPipeIn  = toPipeIn(streamPipeInQ);
    interface streamPipeOut = toPipeOut(streamPipeOutQ);
endmodule
