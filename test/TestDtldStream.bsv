import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;
import StmtFSM :: * ;

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




typedef Bit#(10) SpliterSubStreamAlignBlockCnt;

interface TestDtldStreamSpliterTimingTest;
    method Bit#(128) getOutput;
endinterface

(* synthesize *)
module mkTestDtldStreamSpliterTimingTest(TestDtldStreamSpliterTimingTest);
    Reg#(Bit#(128)) outReg <- mkReg(0);
    Reg#(Bit#(10)) stepCounterReg <- mkReg(0);
    Reg#(Bit#(2))  rotReg <- mkReg(0);


    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);

    ForceKeepWideSignals#(Bit#(512), Bit#(128)) signalKeeper          <- mkForceKeepWideSignals; 

    DtldStreamSplitor#(DATA, SpliterSubStreamAlignBlockCnt, NUMERIC_TYPE_TWO) dut <- mkDtldStreamSplitor;

    rule test;
        let randValue1 <- randSource1.get;
        
        dut.dataPipeIn.enq(unpack(truncate(randValue1)));
        dut.streamAlignBlockCountPipeIn.enq(unpack(truncateLSB(randValue1)));
    endrule



    rule handleOutput;
        let out = dut.dataPipeOut.first;
        dut.dataPipeOut.deq;

        signalKeeper.bitsPipeIn.enq(zeroExtend(pack(out)));
        outReg <= zeroExtend({signalKeeper.out});
    endrule

    method getOutput = outReg;
endmodule



module mkTestDtldStreamSpliter(Empty);
   
    DtldStreamSplitor#(DATA, SpliterSubStreamAlignBlockCnt, NUMERIC_TYPE_TWO) dut <- mkDtldStreamSplitor;

    Stmt injectProc = (seq
        $display("11111111");
        dut.streamAlignBlockCountPipeIn.enq(2);
        $display("2222222");
        dut.streamAlignBlockCountPipeIn.enq(9);
        $display("333333333");
        dut.dataPipeIn.enq(DtldStreamData{
            data: 256'h9999999A_8888888A_777777A_6666666A_5555555A_4444444A_3333333A_2222222A,
            byteNum: 32,
            startByteIdx: 0,
            isFirst: True,
            isLast: False
        });
        dut.dataPipeIn.enq(DtldStreamData{
            data: 256'h9999999B_8888888B_777777B_6666666B_5555555B_4444444B_3333333B_2222222B,
            byteNum: 32,
            startByteIdx: 0,
            isFirst: False,
            isLast: False
        });
        dut.dataPipeIn.enq(DtldStreamData{
            data: 256'h9999999C_8888888C_777777C_6666666C_5555555C_4444444C_3333333C_2222222C,
            byteNum: 32,
            startByteIdx: 0,
            isFirst: False,
            isLast: True
        });
    endseq);


    Stmt checkProc = (seq
        action
            $display("aaaa=", fshow(dut.dataPipeOut.first));
            dut.dataPipeOut.deq;
        endaction
        action
            $display("aaaa=", fshow(dut.dataPipeOut.first));
            dut.dataPipeOut.deq;
        endaction
        action
            $display("aaaa=", fshow(dut.dataPipeOut.first));
            dut.dataPipeOut.deq;
        endaction
    endseq);

    FSM injectFSM <- mkFSM(injectProc);
    FSM checkFSM  <- mkFSM(checkProc);
    
    Reg#(Bool) goingReg <- mkReg(False);

    rule start (!goingReg);
        goingReg <= True;
        injectFSM.start;
        checkFSM.start;
    endrule
endmodule