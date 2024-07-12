import PAClib :: *;
import FIFOF :: *;
import Connectable :: *;

// re-export PAAClib's PipeOut
export PipeOut;

export PipeIn(..);
export GetF(..);
export PutF(..);
export ServerF(..);
export ClientF(..);
export ServerP(..);
export ClientP(..);
export f_FIFOF_to_PipeIn;
export f_UGFIFOF_to_PipeIn;
export f_UGFIFOF_to_PipeOut;
export Connectable;


interface PipeIn#(type tData);
    method Action enq(tData data);
    method Bool notFull;
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

// interface PipeIn2PipeOut#(type tData);
//     interface PipeIn#(tData) pipeIn;
//     interface PipeOut#(tData) pipeOut;
// endinterface

// module mkPipelinePipeIn2PipeOut(PipeIn2PipeOut#(tData)) provisos (Bits#(tData, szData));

//     Wire#(tData) dataWire <- mkWire;

//     interface PipeIn#(tData) pipeIn;
//         method Action enq(tData data);
//         method Bool notFull;
//     endinterface

//     interface PipeOut#(tData) pipeOut;
//         method tData first;
//         method Action deq;
//         method Bool notEmpty;
//     endinterface
// endmodule