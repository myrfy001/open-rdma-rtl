import GetPut :: *;
import ClientServer :: *;

import SdpBramWrapper :: *;

interface TestSdpBramWrapperTimingTest;
    method Bit#(144) _read;
endinterface

(*synthesize*)
module mkTestSdpBramWrapperTimingTest(TestSdpBramWrapperTimingTest);
    SdpBram#(Bit#(9), Bit#(144)) bram <- mkSdpBram;

    Reg#(Bit#(9)) addrReg <- mkReg(0);
    Reg#(Bit#(144)) dataReg <- mkReg(0);
    Reg#(Bit#(144)) outReg <- mkReg(0);

    rule testWriteAndReadReq;
        addrReg <= addrReg + 1;
        dataReg <= dataReg + 1;
        let x = truncate(dataReg) | addrReg;
        if (lsb(addrReg) == 1) begin
            bram.write.put(tuple2(x, dataReg));
            bram.readSrv.request.put(x);
        end 
    endrule

    rule testReadResp;
        let resp <- bram.readSrv.response.get;
        outReg <= resp;
    endrule

    method _read = outReg;
endmodule