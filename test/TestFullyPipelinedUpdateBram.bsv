import PrimUtils :: *;
import Vector :: *;
import PAClib :: *;
import ClientServer :: *;
import GetPut :: *;

import Utils4Test :: *;
import BluerdmaConsts :: *;
import FullyPipelinedUpdateBram :: *;
import RdmaHeaders :: *;


function Bit#(144) mergeFuncBitOr(Bit#(144) oldData, Bit#(144) newData);
    let oldTag = oldData[15:0];
    let newTag = newData[15:0];
    if (oldTag == newTag) begin
        return {oldData[143:16] | newData[143:16], oldTag};
    end 
    else begin
        return newData;
    end
endfunction

(* doc = "testcase" *)
module mkTestFullyPipelinedUpdateBram(Empty);
    FullyPipelinedUpdateBram2#(Bit#(9), Bit#(2), Bit#(144)) instWithFourBank <- mkFullyPipelinedUpdateBram2(mergeFuncBitOr);

    // The following instance has a bankAddr type of `Bit#(0)`, which is of zero size, make sure it works.
    FullyPipelinedUpdateBram2#(Bit#(9), Bit#(0), Bit#(144)) instWithOneBank <- mkFullyPipelinedUpdateBram2(mergeFuncBitOr);

    let cycleCounter <- mkSimulationCycleLimitCounter(10000);

    Reg#(Bit#(9)) addrReg1 <- mkReg(0);
    Reg#(Long) lastEnqCycleReg <- mkReg(-1);

    Vector#(1, PipeOut#(Bit#(7))) oneHotRandomGen <-
        mkRandomValueInRangePipeOut(0, 127);

    rule checkFullyPipeline if (cycleCounter > 1); // random generator need one cycle to start.
        immAssert(
            cycleCounter - lastEnqCycleReg <= 1,
            "mkTestFullyPipelinedUpdateBram Error",
            $format("pipeline paused, cycleCounter=%d, lastEnqCycleReg=%d", cycleCounter, lastEnqCycleReg)
        );
    endrule

    rule testEnq;
        lastEnqCycleReg <= cycleCounter;

        let oneHotShift = oneHotRandomGen[0].first;
        let bankAddr = truncate(oneHotRandomGen[0].first);
        oneHotRandomGen[0].deq;

        Bit#(128) oneHot = 1 << oneHotShift;
        instWithOneBank.updateSrv.request.put(
            FullyPipelinedUpdateBramUpdateReq{
                generateResp: lsb(addrReg1) == 0,
                address:      addrReg1,
                bankAddress:  0,
                datain:       {oneHot, 16'h0}
            }
        );
        instWithFourBank.updateSrv.request.put(
            FullyPipelinedUpdateBramUpdateReq{
                generateResp: lsb(addrReg1) == 0,
                address:      addrReg1,
                bankAddress:  bankAddr,
                datain:       {oneHot, 16'h0}
            }
        );
        addrReg1 <= addrReg1 + 1;
    endrule

    rule fetchUpdateResp;
        let resp1 <- instWithOneBank.updateSrv.response.get;
        let resp2 <- instWithFourBank.updateSrv.response.get;
    endrule
endmodule

interface TestFullyPipelinedBackendTimingTest;
    method Bit#(144) _read;
endinterface

(*synthesize*)
module mkTestFullyPipelinedBackendTimingTest(TestFullyPipelinedBackendTimingTest);

    FullyPipelinedUpdateBram2#(Bit#(9), Bit#(2), Bit#(144)) instWithFourBank <- mkFullyPipelinedUpdateBram2(mergeFuncBitOr);

    // The following instance has a bankAddr type of `Bit#(0)`, which is of zero size, make sure it works.
    FullyPipelinedUpdateBram2#(Bit#(9), Bit#(0), Bit#(144)) instWithOneBank <- mkFullyPipelinedUpdateBram2(mergeFuncBitOr);

    Reg#(Bit#(9)) addrReg1 <- mkReg(0);

    Reg#(Bit#(144)) bitmapInputReg <- mkReg(123);
    Reg#(Bit#(144)) outputReg <- mkReg(0);


    rule testEnq;
        bitmapInputReg <= rotateBitsBy(bitmapInputReg, 2) ^ bitmapInputReg;
        let bankAddr = truncate(addrReg1);

        instWithOneBank.updateSrv.request.put(
            FullyPipelinedUpdateBramUpdateReq{
                generateResp: lsb(addrReg1) == 0,
                address:      addrReg1,
                bankAddress:  0,
                datain:       bitmapInputReg
            }
        );
        instWithFourBank.updateSrv.request.put(
            FullyPipelinedUpdateBramUpdateReq{
                generateResp: lsb(addrReg1) == 0,
                address:      addrReg1,
                bankAddress:  bankAddr,
                datain:       bitmapInputReg
            }
        );
        addrReg1 <= addrReg1 + 1;
    endrule

    rule fetchUpdateResp;
        let resp1 <- instWithOneBank.updateSrv.response.get;
        let resp2 <- instWithFourBank.updateSrv.response.get;
        outputReg <= resp1 ^ resp2;
    endrule

    method _read = outputReg;
endmodule