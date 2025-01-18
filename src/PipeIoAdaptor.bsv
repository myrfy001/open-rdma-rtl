import FIFOF :: *;
import Connectable :: *;
import ConnectableF :: *;



interface TestA;
    interface PipeOut#(Int#(32)) po;
endinterface

module mkTestA(TestA);
    FIFOF#(Int#(32)) q <- mkFIFOF;
    Reg#(Int#(32)) dReg <- mkReg(0);
    Reg#(Bool) delayReg <- mkRegU;

    rule aaa;
        delayReg <= !delayReg;
        if (delayReg) begin
            q.enq(dReg);
            dReg <= dReg + 1;
        end
    endrule

    interface po = toPipeOut(q);
endmodule

interface TestB;
    interface PipeInNr#(Int#(32)) pi;
endinterface

module mkTestB(TestB);
    PipeInAdapter#(Int#(32)) ad <- mkPipeInAdapter;
    Reg#(Bool) delayReg <- mkRegU;
    rule handle;
        delayReg <= !delayReg;
        if (ad.notEmpty) begin
            let d = ad.first;
            $display("time=%0t, d=%d", $time, d);
            // if (delayReg) begin
                ad.deq;
            // end
        end
    endrule

    interface pi = ad.pipeInIfc;
endmodule

module mkTop(Empty);
    let mA <- mkTestA;
    let mB <- mkTestB;
    mkConnection(mA.po, mB.pi);
endmodule