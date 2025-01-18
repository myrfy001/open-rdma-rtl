import FIFOF :: *;
import Connectable :: *;
import ConnectableF :: *;


interface PipeIoAdapterPipeInPeer#(type tData);
    method Action firstIn(tData dataIn);
    method Action notEmptyIn(Bool val);
    method Bool deqSignalOut;
endinterface


interface PipeInAdapter#(type tData);
    method tData first;
    method Action deq;
    method Bool notEmpty;
    interface PipeIoAdapterPipeInPeer#(tData) pipeInIfc;
endinterface


module mkPipeInAdapter(PipeInAdapter#(tData)) provisos (Bits#(tData, szData));

    Wire#(tData) dataWire <- mkWire;
    Wire#(Bool)  notEmptyWire <- mkWire;
    PulseWire deqSignalWire <- mkPulseWire;

    interface PipeIoAdapterPipeInPeer pipeInIfc;
        method Action firstIn(tData dataIn);
            dataWire <= dataIn;
        endmethod
        
        method Action notEmptyIn(Bool val);
            notEmptyWire <= val;
        endmethod

        method Bool deqSignalOut;
            return deqSignalWire;
        endmethod
    endinterface

    method tData first;
        return dataWire;
    endmethod

    method Action deq if (notEmptyWire);
        deqSignalWire.send;
    endmethod

    method Bool notEmpty;
        return notEmptyWire;
    endmethod
endmodule

instance Connectable#(PipeOut#(t), PipeIoAdapterPipeInPeer#(t));
    module mkConnection#(PipeOut#(t) fo, PipeIoAdapterPipeInPeer#(t) fi)(Empty);
        mkConnection(fo.first, fi.firstIn);
        mkConnection(fo.notEmpty, fi.notEmptyIn);
        rule handleDeq;
            if (fi.deqSignalOut) begin
                fo.deq;
            end
        endrule
    endmodule
endinstance


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
    interface PipeIoAdapterPipeInPeer#(Int#(32)) pi;
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