import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 

import PrimUtils :: *;
import RdmaUtils :: *;
import Utils4Test :: *;
import EthernetTypes :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ConnectableF :: *;
import DtldStream :: *;


interface TestDtldStreamConcatorTimingTest;
    method Bit#(128) getOutput;
endinterface

(* synthesize *)
module mkTestDtldStreamConcatorTimingTest(TestDtldStreamConcatorTimingTest);
    Reg#(Bit#(128)) outReg <- mkReg(0);
    Reg#(Bit#(10)) stepCounterReg <- mkReg(0);
    Reg#(Bit#(2))  rotReg <- mkReg(0);


    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);

    TestDtldStreamConcatorTimingTest#(DATA, NUMERIC_TYPE_TWO) dut <- mkDtldStreamConcator;

    rule test;
        let randValue1 <- randSource1.get;

        
        signalKeeperForTxBusOutput.bitsPipeIn.enq(pack(testReg));
    endrule



    rule handleOutput;
        outReg <= zeroExtend({signalKeeperForTxBusOutput.out});
    endrule

    method getOutput = outReg;
endmodule