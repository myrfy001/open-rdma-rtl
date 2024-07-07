import FIFOF :: *;
import SpecialFIFOs :: *;
import ClientServer :: *;
import GetPut :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import Vector :: *;
import BRAM :: *;
import Printf:: *;

import PAClib :: *;
import PrimUtils :: *;
import Settings :: *;

function Maybe#(TransType) qpType2TransType(TypeQP qpt);
    return case (qpt)
        IBV_QPT_RC        : tagged Valid TRANS_TYPE_RC;
        IBV_QPT_UC        : tagged Valid TRANS_TYPE_UC;
        IBV_QPT_UD        : tagged Valid TRANS_TYPE_UD;
        IBV_QPT_XRC_RECV  ,
        IBV_QPT_XRC_SEND  : tagged Valid TRANS_TYPE_XRC;
        default           : tagged Invalid;
    endcase;
endfunction

function Bool containWorkReqFlag(
    FlagsType#(WorkReqSendFlag) flags, WorkReqSendFlag flag
);
    return containEnum(flags, flag);
    // return !isZero(pack(flags & enum2Flag(flag)));
endfunction


function Bit#(width) swapEndianByte(Bit#(width) data) provisos(Mul#(8, byteNum, width));
    Vector#(byteNum, Bit#(BYTE_WIDTH)) dataVec = unpack(data);
    return pack(reverse(dataVec));
endfunction

function Bit#(width) swapEndianBit(Bit#(width) data) provisos(Mul#(1, byteNum, width));
    Vector#(byteNum, Bit#(1)) dataVec = unpack(data);
    return pack(reverse(dataVec));
endfunction


function DataStream reverseStream(DataStream st);
    st.data = swapEndianByte(st.data);
    return st;
endfunction

function DataStreamEn reverseStreamEnAndData(DataStreamEn st);
    st.data = swapEndianByte(st.data);
    st.byteEn = swapEndianBit(st.byteEn);
    return st;
endfunction

function DataStreamEn reverseStreamEnOnly(DataStreamEn st);
    st.byteEn = swapEndianBit(st.byteEn);
    return st;
endfunction


typedef enum {
    QueuedClientServerQueueTypeNormal = 0,
    QueuedClientServerQueueTypeBypass = 1,
    QueuedClientServerQueueTypePipeline = 2
} QueuedClientServerQueueType deriving(Bits, Eq);

interface QueuedClient#(type t_req, type t_resp);
    interface Client#(t_req, t_resp) clt;
    method Action putReq(t_req req);
    method Bool canPutReq;

    method ActionValue#(t_resp) getResp();
    method Bool hasResp;
endinterface


module mkFifofByType#(Integer depth, QueuedClientServerQueueType typ)(FIFOF#(tData)) provisos(Bits#(tData, szData));
    FIFOF#(tData) q;
    if (typ == QueuedClientServerQueueTypeNormal) begin
        q <- mkSizedFIFOF(depth);
    end
    else if (typ == QueuedClientServerQueueTypeBypass) begin
        q <- mkSizedBypassFIFOF(depth);
    end
    else if (typ == QueuedClientServerQueueTypePipeline) begin
        q <- mkLFIFOF;
    end
    return q;
endmodule

module mkSizedQueuedClient#(String name, Integer reqDepth, Integer respDepth, QueuedClientServerQueueType reqType, QueuedClientServerQueueType respType)(QueuedClient#(t_req, t_resp)) provisos (
    Bits#(t_req, sz_req),
    Bits#(t_resp, sz_resp)
);
    
    FIFOF#(t_req) reqQ <- mkFifofByType(reqDepth, reqType);
    FIFOF#(t_resp) respQ <- mkFifofByType(respDepth, respType);

    rule debug;
        if (!reqQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkQueuedClient ", fshow(name) , " reqQ");
        end
        if (!respQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkQueuedClient ", fshow(name) , " respQ");
        end
    endrule

    interface Client clt;
        interface Get request;
            method ActionValue#(t_req) get();
                reqQ.deq;
                return reqQ.first;
            endmethod
        endinterface
        interface Put response;
            method Action put(t_resp resp);
                respQ.enq(resp);
            endmethod
        endinterface
    endinterface

    method Action putReq(t_req req);
        reqQ.enq(req);
    endmethod

    method Bool canPutReq = reqQ.notFull;

    method ActionValue#(t_resp) getResp();
        respQ.deq;
        return respQ.first;
    endmethod

    method Bool hasResp = respQ.notEmpty;
endmodule

module mkQueuedClient#(String name)(QueuedClient#(t_req, t_resp)) provisos (
    Bits#(t_req, sz_req),
    Bits#(t_resp, sz_resp)
);
    let t <- mkSizedQueuedClient(name, 2, 2, QueuedClientServerQueueTypeNormal, QueuedClientServerQueueTypeNormal);
    return t;
endmodule


interface QueuedServer#(type t_req, type t_resp);
    interface Server#(t_req, t_resp) srv;

    method ActionValue#(t_req) getReq();
    method Bool hasReq;

    method Action putResp(t_resp resp);
    method Bool canPutResp;
endinterface

module mkSizedQueuedServer#(String name, Integer reqDepth, Integer respDepth, QueuedClientServerQueueType reqType, QueuedClientServerQueueType respType)(QueuedServer#(t_req, t_resp)) provisos (
    Bits#(t_req, sz_req),
    Bits#(t_resp, sz_resp)
);

    FIFOF#(t_req) reqQ <- mkFifofByType(reqDepth, reqType);
    FIFOF#(t_resp) respQ <- mkFifofByType(respDepth, respType);

    rule debug;
        if (!reqQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkQueuedServer ", fshow(name) , " reqQ");
        end
        if (!respQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkQueuedServer ", fshow(name) , " respQ");
        end
    endrule

    interface Server srv;
        interface Get response;
            method ActionValue#(t_resp) get();
                respQ.deq;
                return respQ.first;
            endmethod
        endinterface
        interface Put request;
            method Action put(t_req req);
                reqQ.enq(req);
            endmethod
        endinterface
    endinterface

    method Action putResp(t_resp resp);
        respQ.enq(resp);
    endmethod

    method Bool canPutResp = respQ.notFull;

    method ActionValue#(t_req) getReq();
        reqQ.deq;
        return reqQ.first;
    endmethod

    method Bool hasReq = reqQ.notEmpty;

endmodule


module mkQueuedServer#(String name)(QueuedServer#(t_req, t_resp)) provisos (
    Bits#(t_req, sz_req),
    Bits#(t_resp, sz_resp)
);
     
    let t <- mkSizedQueuedServer(name, 2, 2, QueuedClientServerQueueTypeNormal, QueuedClientServerQueueTypeNormal);
    return t;
endmodule

function tData getAbsValue(tData a) provisos(Arith#(tData), Bitwise#(tData));
    return msb(a) == 0 ? a : (~a) + 1;
endfunction