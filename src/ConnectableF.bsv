import PAClib :: *;

// re-export PAAClib's PipeOut
export PipeOut;

export PipeIn;
export GetF;
export PutF;
export ServerF;
export ClientF;
export ServerP;
export ClientP;


interface PipeIn#(type tData);
    method Action enq(tData data);
    method Bool notEmpty;
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