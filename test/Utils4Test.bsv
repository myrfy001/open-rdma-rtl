import BuildVector :: *;
import ClientServer :: *;
import Cntrs :: *;
import FIFOF :: *;
import GetPut :: *;
import Randomizable :: *;
import Vector :: *;
import PAClib :: *;
import LFSR::*;

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