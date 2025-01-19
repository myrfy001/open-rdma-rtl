import PAClib :: *;
import FIFOF :: *;
import Clocks :: *;

import Connectable :: *;


// re-export PAAClib's PipeOut
export PipeOut;

export PipeIn(..);
export PipeInNr(..);
export PipeInAdapter(..);
export mkPipeInAdapter;
export toPipeInNr;
export mkPipeInNrToPipeIn;
export GetF(..);
export PutF(..);
export ServerF(..);
export ClientF(..);
export ServerP(..);
export ClientP(..);
export f_FIFOF_to_PipeIn;
export f_UGFIFOF_to_PipeIn;
export f_UGFIFOF_to_PipeOut;
export f_Sync_FIFOF_to_FIFOF;
export f_Sync_FIFOF_to_PipeIn;
export f_Sync_FIFOF_to_PipeOut;
export toPipeOut;
export toPipeIn;
export toPipeOutSync;
export toPipeInSync;
export ugToPipeOut;
export ugToPipeIn;
export Connectable;


interface PipeIn#(type tData);
    method Action enq(tData data);
    method Bool notFull;
endinterface

// Nr means not registered, which directly pass through
interface PipeInNr#(type tData);
    method Action firstIn(tData dataIn);
    method Action notEmptyIn(Bool val);
    method Bool deqSignalOut;
endinterface

interface GetF#(type tData);
    method Bool ready;
    method ActionValue#(tData) get;
endinterface

interface PutF#(type tData);
    method Bool ready;
    method Action put(tData value);
endinterface

interface ServerF#(type tReq, type tResp);
    interface PutF#(tReq) request;
    interface GetF#(tResp) response;
endinterface

interface ClientF#(type tReq, type tResp);
    interface GetF#(tReq) request;
    interface PutF#(tResp) response;
endinterface

interface ServerP#(type tReq, type tResp);
    interface PipeIn#(tReq) request;
    interface PipeOut#(tResp) response;
endinterface

interface ClientP#(type tReq, type tResp);
    interface PipeOut#(tReq) request;
    interface PipeIn#(tResp) response;
endinterface

function PipeIn#(tData) f_FIFOF_to_PipeIn(FIFOF#(tData) fifof);
    return (interface PipeIn;
               method Action enq (tData data);
                  fifof.enq(data);
               endmethod
               method Bool notFull;
                  return fifof.notFull;
               endmethod
            endinterface);
endfunction

function PipeIn#(tData) f_UGFIFOF_to_PipeIn(FIFOF#(tData) fifof);
    return (interface PipeIn;
               method Action enq (tData data) if (fifof.notFull);
                  fifof.enq(data);
               endmethod
               method Bool notFull;
                  return fifof.notFull;
               endmethod
            endinterface);
endfunction

function PipeOut #(tData)  f_UGFIFOF_to_PipeOut  (FIFOF #(tData) fifof);
    return (interface PipeOut;
               method tData first if (fifof.notEmpty);
                  return fifof.first;
               endmethod
               method Action deq if (fifof.notEmpty);
                  fifof.deq;
               endmethod
               method Bool notEmpty;
                  return fifof.notEmpty;
               endmethod
            endinterface);
 endfunction

 function FIFOF#(tData) f_Sync_FIFOF_to_FIFOF(SyncFIFOIfc#(tData) syncFifo);
    return (interface FIFOF;
                method enq = syncFifo.enq;
                method notFull = syncFifo.notFull;
                method first = syncFifo.first;
                method deq = syncFifo.deq;
                method notEmpty = syncFifo.notEmpty;

                method Action clear;
                    $display("clear not supported on sync fifo converted FIFOF interface");
                    $finish(1);
                endmethod
            endinterface);
endfunction

 function PipeIn#(tData) f_Sync_FIFOF_to_PipeIn(SyncFIFOIfc#(tData) syncFifo);
    return (interface PipeIn;
                method enq = syncFifo.enq;
                method notFull = syncFifo.notFull;
            endinterface);
endfunction

function PipeOut#(tData) f_Sync_FIFOF_to_PipeOut(SyncFIFOIfc#(tData) syncFifo);
    return (interface PipeOut;      
                method first = syncFifo.first;
                method deq = syncFifo.deq;
                method notEmpty = syncFifo.notEmpty;
            endinterface);
endfunction



instance Connectable#(PipeOut#(t), PipeIn#(t));
    module mkConnection#(PipeOut#(t) fo, PipeIn#(t) fi)(Empty);
        rule connect;
            fi.enq(fo.first);
            fo.deq;
        endrule
    endmodule
endinstance

instance Connectable#(PipeIn#(t), PipeOut#(t));
    module mkConnection#(PipeIn#(t) fi, PipeOut#(t) fo)(Empty);
        rule connect;
            fi.enq(fo.first);
            fo.deq;
        endrule
    endmodule
endinstance

// PipeOut related

function PipeOut#(anytype) toPipeOut(FIFOF#(anytype) queue);
    return f_FIFOF_to_PipeOut(queue);
endfunction

function PipeIn#(anytype) toPipeIn(FIFOF#(anytype) queue);
    return f_FIFOF_to_PipeIn(queue);
endfunction

function PipeOut#(anytype) toPipeOutSync(SyncFIFOIfc#(anytype) queue);
    return f_Sync_FIFOF_to_PipeOut(queue);
endfunction

function PipeIn#(anytype) toPipeInSync(SyncFIFOIfc#(anytype) queue);
    return f_Sync_FIFOF_to_PipeIn(queue);
endfunction

function PipeOut#(anytype) ugToPipeOut(FIFOF#(anytype) queue);
    return f_UGFIFOF_to_PipeOut(queue);
endfunction

function PipeIn#(anytype) ugToPipeIn(FIFOF#(anytype) queue);
    return f_UGFIFOF_to_PipeIn(queue);
endfunction


interface PipeInAdapter#(type tData);
    method tData first;
    method Action deq;
    method Bool notEmpty;
    interface PipeInNr#(tData) pipeInIfc;
endinterface


module mkPipeInAdapter(PipeInAdapter#(tData)) provisos (Bits#(tData, szData));

    Wire#(tData) dataWire <- mkWire;
    Wire#(Bool)  notEmptyWire <- mkWire;
    PulseWire deqSignalWire <- mkPulseWire;

    interface PipeInNr pipeInIfc;
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

    method tData first if (notEmptyWire);
        return dataWire;
    endmethod

    method Action deq if (notEmptyWire);
        deqSignalWire.send;
    endmethod

    method Bool notEmpty;
        return notEmptyWire;
    endmethod
endmodule

instance Connectable#(PipeOut#(t), PipeInNr#(t));
    module mkConnection#(PipeOut#(t) fo, PipeInNr#(t) fi)(Empty);
        mkConnection(fo.first, fi.firstIn);
        mkConnection(fo.notEmpty, fi.notEmptyIn);
        rule handleDeq;
            if (fi.deqSignalOut) begin
                fo.deq;
            end
        endrule
    endmodule
endinstance

instance Connectable#(PipeInNr#(t), PipeOut#(t));
    module mkConnection#(PipeInNr#(t) fi, PipeOut#(t) fo)(Empty);
        mkConnection(fo, fi);
    endmodule
endinstance

function PipeInNr#(anytype) toPipeInNr(PipeInAdapter#(anytype) queue);
    return queue.pipeInIfc;
endfunction

module mkPipeInNrToPipeIn#(PipeInNr#(tData) pipeInNr, Integer bufferDepth)(PipeIn#(tData)) provisos(Bits#(tData, szData));
    FIFOF#(tData) innerQ <- mkSizedFIFOF(bufferDepth);
    mkConnection(toPipeOut(innerQ), pipeInNr);
    return toPipeIn(innerQ);
endmodule