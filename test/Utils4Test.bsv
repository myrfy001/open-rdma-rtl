import BuildVector :: *;
import ClientServer :: *;
import Cntrs :: *;
import FIFOF :: *;
import GetPut :: *;
import Randomizable :: *;
import Vector :: *;
import PAClib :: *;
import LFSR::*;

import DataTypes :: *;
import ConnectableF :: *;
import RdmaHeaders :: *;
import PrimUtils :: *;


interface CountDown;
    method Action decr();
    method int   _read();
endinterface

function Action normalExit();
    action
        $info("time=%0t: normal finished", $time);
        $finish(0);
    endaction
endfunction

module mkCountDown#(Integer maxValue)(CountDown);
    Reg#(Long) cycleNumReg <- mkReg(0);
    Count#(int) cnt <- mkCount(fromInteger(maxValue));

    rule countCycles;
        cycleNumReg <= cycleNumReg + 1;
    endrule

    method Action decr();
        cnt.decr(1);
        // $display("time=%0t: cycles=%0d, cmp cnt=%0d", $time, cycleNumReg, cnt);

        if (isZero(pack(cnt))) begin
            $info("time=%0t: normal finished after %0d cycles", $time, cycleNumReg);
            $finish(0);
        end
    endmethod

    method int _read() = cnt;
endmodule

module mkSimulationCycleLimitCounter#(Integer maxValue)(Long);
    Reg#(Long) cycleNumReg <- mkReg(0);

    rule countCycles;
        cycleNumReg <= cycleNumReg + 1;
        if (cycleNumReg == fromInteger(maxValue)) begin
            $info("time=%0t: normal finished after %0d cycles", $time, cycleNumReg);
            $finish(0);
        end
    endrule

    return cycleNumReg;
endmodule


module mkFunc2Pipe#(
    function tb func(ta inputVal), PipeOut#(ta) pipeIn
)(PipeOut#(tb));
    let resultPipeOut <- mkFn_to_Pipe(func, pipeIn); // No delay
    return resultPipeOut;
endmodule


// Random PipeOut related

module mkGenericRandomPipeOut(PipeOut#(anytype)) provisos(
        Bits#(anytype, tSz), Bounded#(anytype)
    );

    Randomize#(anytype) randomGen <- mkGenericRandomizer;
    FIFOF#(anytype) randomValQ <- mkFIFOF;

    Reg#(Bool) initializedReg <- mkReg(False);

    rule init if (!initializedReg);
        randomGen.cntrl.init;
        initializedReg <= True;
    endrule

    rule gen if (initializedReg);
        let val <- randomGen.next;
        randomValQ.enq(val);
    endrule

    return toPipeOut(randomValQ);
endmodule

module mkGenericRandomPipeOutVec(
        Vector#(vSz, PipeOut#(anytype))
    ) provisos(Bits#(anytype, tSz), Bounded#(anytype));

    PipeOut#(anytype) resultPipeOut <- mkGenericRandomPipeOut;
    Vector#(vSz, PipeOut#(anytype)) resultPipeOutVec <-
        mkForkVector(resultPipeOut);
    return resultPipeOutVec;
endmodule

module mkRandomValueInRangePipeOut#(
        // Both min and max are inclusive
        anytype min, anytype max
    )(Vector#(vSz, PipeOut#(anytype))) provisos(
        Bits#(anytype, tSz), Bounded#(anytype), FShow#(anytype), Ord#(anytype), Arith#(anytype)
    );

    Randomize#(anytype) randomVal <- mkConstrainedRandomizer(min, max);
    FIFOF#(anytype) randomValQ <- mkFIFOF;
    let resultPipeOutVec <- mkForkVector(toPipeOut(randomValQ));

    Reg#(Bool) initializedReg <- mkReg(False);

    rule init if (!initializedReg);
        immAssert(
            max >= min,
            "max >= min assertion @",
            $format(
                "max=", fshow(max), " should >= min=", fshow(min)
            )
        );
        randomVal.cntrl.init;
        initializedReg <= True;
        randomValQ.enq((min+max)/2);
    endrule

    rule gen if (initializedReg);
        let val <- randomVal.next;
        randomValQ.enq(val);
    endrule

    return resultPipeOutVec;
endmodule

module mkRandomLenPipeOut#(
        // Both min and max are inclusive
        Length minLength, Length maxLength
    )(PipeOut#(Length));

    Vector#(1, PipeOut#(Length)) resultVec <- mkRandomValueInRangePipeOut(
        minLength, maxLength
    );
    return resultVec[0];
endmodule

module mkRandomItemFromVec#(
    Vector#(vSz, anytype) items
)(PipeOut#(anytype)) provisos(
    Bits#(anytype, tSz),
    NumAlias#(TLog#(vSz), idxSz)
);
    UInt#(idxSz) maxIdx = fromInteger(valueOf(vSz) - 1);
    Vector#(1, PipeOut#(UInt#(idxSz))) vecIdxPipeOut <-
        mkRandomValueInRangePipeOut(0, maxIdx);
    let resultPipeOut <- mkFunc2Pipe(select(items), vecIdxPipeOut[0]);
    return resultPipeOut;
endmodule

module mkSynthesizableRng32#(Bit#(32) seed)(Get#(Bit#(32)));
    LFSR#(Bit#(32)) lfsr <- mkLFSR_32;
    FIFOF#(Bit#(32)) fi <- mkFIFOF;
    Reg#(Bool) starting <- mkReg(True) ;

    rule start (starting);
        starting <= False;
        lfsr.seed(seed);
    endrule
    
    rule run (!starting);
        fi.enq(lfsr.value);
        lfsr.next;
    endrule: run

    return toGet(fi);
endmodule

interface FixedLengthDateStreamRandomGen;
    interface PipeIn#(Length) reqPipeIn;
    interface PipeOut#(DataStream) streamPipeOut;
endinterface

module mkFixedLengthDateStreamRandomGen(FixedLengthDateStreamRandomGen);
    FIFOF#(Length) reqPipeInQ <- mkFIFOF;
    FIFOF#(DataStream) streamPipeOutQ <- mkFIFOF;

    PipeOut#(DATA) dataRandomGenPipeOut <- mkGenericRandomPipeOut;

    Reg#(Length) leftLenReg <- mkRegU;
    Reg#(Bool) isFirstReg <- mkReg(True);

    

    rule gen;
        let len = leftLenReg;
        Bool isFirst = False;
        Bool isLast = False;
        if (isFirstReg) begin
            len = reqPipeInQ.first;
            reqPipeInQ.deq;
            isFirst = True;
        end
        leftLenReg <= len - fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));

        let data = dataRandomGenPipeOut.first;
        dataRandomGenPipeOut.deq;

        BusBitNum tmpShiftCnt = 0;
        ByteIndexInBeat startByteIdx = 0;
        ByteEnBitNum byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));

        if (len <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH))) begin
            tmpShiftCnt = (fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - truncate(len)) * fromInteger(valueOf(BYTE_WIDTH));
            data = data << tmpShiftCnt;
            isLast = True;
            if (isFirst) begin
                ByteEnBitNum busWidth = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
                startByteIdx = truncate(busWidth) - truncate(len);
            end
            byteNum = truncate(len);
            isFirstReg <= True;
        end
        else begin
            isFirstReg <= False;
        end

        let ds = DataStream{
            data: data,
            byteNum: byteNum,
            startByteIdx: startByteIdx,
            isFirst: isFirst,
            isLast: isLast
        };
        streamPipeOutQ.enq(ds);
    endrule

    interface reqPipeIn = toPipeIn(reqPipeInQ);
    interface streamPipeOut = toPipeOut(streamPipeOutQ);
endmodule