import GetPut :: *;
import ClientServer :: *;
import FIFOF :: *;

import PrimUtils :: *;
import Utils4Test :: *;

import SdpBramWrapper :: *;
import Randomizable :: * ;

interface TestSdpBramWrapperTimingTest;
    method Bit#(144) _read;
endinterface

// (*synthesize*)
// module mkTestSdpBramWrapperTimingTest(TestSdpBramWrapperTimingTest);
//     SdpBram#(Bit#(9), Bit#(144)) bram <- mkSdpBram;

//     Reg#(Bit#(9)) addrReg <- mkReg(0);
//     Reg#(Bit#(144)) dataReg <- mkReg(0);
//     Reg#(Bit#(144)) outReg <- mkReg(0);

//     rule testWriteAndReadReq;
//         addrReg <= addrReg + 1;
//         dataReg <= dataReg + 1;
//         let x = truncate(dataReg) | addrReg;
//         if (lsb(addrReg) == 1) begin
//             bram.write.put(tuple2(x, dataReg));
//             bram.readSrv.request.put(x);
//         end 
//     endrule

//     rule testReadResp;
//         let resp <- bram.readSrv.response.get;
//         outReg <= resp;
//     endrule

//     method _read = outReg;
// endmodule

interface TestSdpBramWrapperConflictReadWriteTest;
    (* always_ready *)
    method Bit#(144) lastError;

    (* always_ready *)
    method Bit#(8) zeroErrorCnt;

    (* always_ready *)
    method Bit#(8) oneErrorCnt;

endinterface

(*synthesize*)
(* doc = "testcase" *)
module mkTestSdpBramWrapperConflictReadWriteTest(TestSdpBramWrapperConflictReadWriteTest);

    // For this test, the write address is linear increase, while read address is a random value.
    // so, in the same cycle, there maybe chance that two port read and write the same address.
    // The write value is controlled by the msb of a 11-bit counter, the lower 10 bits is used as address.
    // So, the underlying BRAM will be flashed to all 0s, and then all 1s, then all 0s, and repeat forever.
    // This makes the content in the BRAM predictable, making the checker works easier.

    SdpBram#(Bit#(144)) bram <- mkSdpBram;

    Reg#(Bit#(10)) addrWriteReg <- mkReg(0);
    let addrReadRng <- mkSynthesizableRng32(11);

    FIFOF#(Bool) checkerExpectedResultQ <- mkSizedFIFOF(8);
    Reg#(Bit#(8)) readZeroErrorCntReg <- mkReg(0);
    Reg#(Bit#(8)) readOneErrorCntReg <- mkReg(0);

    Reg#(Bit#(144)) lastErrorReg <- mkReg(0);

    Reg#(Bool) errorOccuredReg <- mkReg(False); 
    Reg#(Bit#(10)) exitCounterReg <- mkReg(0);

    Reg#(Bit#(144)) constZeroReg <- mkReg(0);
    Reg#(Bit#(144)) constOneReg <- mkReg(-1);
    
    FIFOF#(Tuple4#(Bool, Bool, Bool, Bit#(144))) resultCheckQ1 <- mkFIFOF;
    FIFOF#(Tuple4#(Bool, Bool, Bool, Bit#(144))) resultCheckQ2 <- mkFIFOF;
    FIFOF#(Tuple4#(Bool, Bool, Bool, Bit#(144))) resultCheckQ3 <- mkFIFOF;

    // use a non constant Reg to trick the backend tool to not optmise those 144 signals into 2 signal.
    rule keepCosnstReg if (exitCounterReg == -1);
        constZeroReg <= ~constZeroReg;
        constOneReg <= ~constOneReg;
    endrule
    
    rule testWriteAndReadReq;
        addrWriteReg <= addrWriteReg + 1;
        Bit#(9) writeAddr = truncate(addrWriteReg);
        let rawAddrRead <- addrReadRng.get;
        Bit#(9) readAddr = truncate(rawAddrRead);
        Bool writeOne = msb(addrWriteReg) == 1;

        AcxBram72kAddr ra = zeroExtend(readAddr);
        AcxBram72kAddr wa = zeroExtend(writeAddr);
        
        bram.write.put(tuple2(wa, writeOne ? constOneReg : constZeroReg));
        bram.readSrv.request.put(ra);
        // $display("read req @ %0t", $time);

        Bool expectedOne = ?;
        if (readAddr > writeAddr) begin
            // then the content in the BRAM should be different from the current write value
            expectedOne = !writeOne;
        end
        else begin
            // the content in the BRAM should be the updated value
            expectedOne = writeOne;
        end
        checkerExpectedResultQ.enq(expectedOne);
    endrule

    rule testReadRespStep1 if (exitCounterReg != -1);
        // $display("read resp @ %0t", $time);
        Bit#(144) resp <- bram.readSrv.response.get;
        let expectedOne = checkerExpectedResultQ.first;
        checkerExpectedResultQ.deq;
        
        let expectOneNotMartch = resp[47:0] != constOneReg[47:0];
        let expectZeroNotMartch = resp[47:0] != constZeroReg[47:0];
        resultCheckQ1.enq(tuple4(expectedOne, expectOneNotMartch, expectZeroNotMartch, resp));
    endrule

    rule testReadRespStep2 if (exitCounterReg != -1);
        let {expectedOne, expectOneNotMartch, expectZeroNotMartch, resp} = resultCheckQ1.first;
        resultCheckQ1.deq;
        
        expectOneNotMartch = (resp[95:48] != constOneReg[95:48]) || expectOneNotMartch;
        expectZeroNotMartch = (resp[95:48] != constZeroReg[95:48]) || expectZeroNotMartch;
        resultCheckQ2.enq(tuple4(expectedOne, expectOneNotMartch, expectZeroNotMartch, resp));
    endrule

    rule testReadRespStep3 if (exitCounterReg != -1);
        let {expectedOne, expectOneNotMartch, expectZeroNotMartch, resp} = resultCheckQ2.first;
        resultCheckQ2.deq;
        
        expectOneNotMartch = (resp[143:96] != constOneReg[143:96]) || expectOneNotMartch;
        expectZeroNotMartch = (resp[143:96] != constZeroReg[143:96]) || expectZeroNotMartch;
        resultCheckQ3.enq(tuple4(expectedOne, expectOneNotMartch, expectZeroNotMartch, resp));
    endrule

    rule testReadRespStep4 if (exitCounterReg != -1);

        let {expectedOne, expectOneNotMartch, expectZeroNotMartch, resp} = resultCheckQ3.first;
        resultCheckQ3.deq;
        // The content of the BRAM is random in first 512 beat.
        if (exitCounterReg >= 512) begin
            if (expectedOne && expectOneNotMartch) begin
                readOneErrorCntReg <= readOneErrorCntReg + 1;
                lastErrorReg <= resp;
                errorOccuredReg <= True;
                $display("time=%t", $time, "Error, expect all ones");
            end 
            else if (!expectedOne && expectZeroNotMartch) begin
                readZeroErrorCntReg <= readZeroErrorCntReg + 1;
                lastErrorReg <= resp;
                errorOccuredReg <= True;
                $display("time=%t", $time, "Error, expect all zeros");
            end
        end
        if (genVerilog && exitCounterReg == -2) begin
            // in generate verilog mode, keep hardware always running, so skip stop condition.
            exitCounterReg <= 0;
        end
        else begin
            exitCounterReg <= exitCounterReg + 1;
        end
        
    endrule

    rule checkSimEnd;
        if (genC) begin
            if (exitCounterReg == -1) begin
                if (errorOccuredReg) begin
                    immFail("mkTestSdpBramWrapperConflictReadWriteTest", $format(""));
                end
                else begin
                    $display("Pass");
                    $finish;
                end
            end
        end
    endrule

    method lastError = lastErrorReg;

    method zeroErrorCnt = readZeroErrorCntReg;

    method oneErrorCnt = readOneErrorCntReg;
endmodule