import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import Utils4Test :: *;

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

    ForceKeepWideSignals#(Bit#(512), Bit#(128)) signalKeeper          <- mkForceKeepWideSignals; 

    DtldStreamConcator#(DATA, NUMERIC_TYPE_TWO) dut <- mkDtldStreamConcator;

    rule test;
        let randValue1 <- randSource1.get;
        
        dut.dataPipeIn.enq(unpack(truncate(randValue1)));
        dut.isLastStreamFlagPipeIn.enq(unpack(truncateLSB(randValue1)));
    endrule



    rule handleOutput;
        let out = dut.dataPipeOut.first;
        dut.dataPipeOut.deq;

        signalKeeper.bitsPipeIn.enq(zeroExtend(pack(out)));
        outReg <= zeroExtend({signalKeeper.out});
    endrule

    method getOutput = outReg;
endmodule