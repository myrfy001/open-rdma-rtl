import FIFOF :: *;
import SpecialFIFOs :: *;
import ClientServer :: *;
import GetPut :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import Vector :: *;
import BRAM :: *;
import Printf:: *;
import Clocks :: *;

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



module mkSyncFifoToFifoF#(SyncFIFOIfc#(tData) syncFifo)(FIFOF#(tData)) provisos(Bits#(tData, szData));
    method deq = syncFifo.deq;
    method enq = syncFifo.enq;
    method first = syncFifo.first;
    method notEmpty = syncFifo.notEmpty;
    method notFull = syncFifo.notFull;

    method Action clear;
        immFail("not supported", $format(""));
    endmethod
endmodule

typedef enum {
    QueuedClientServerQueueTypeNormal = 0,
    QueuedClientServerQueueTypeBypass = 1,
    QueuedClientServerQueueTypePipeline = 2,
    QueuedClientServerQueueTypeSync = 3
} QueuedClientServerQueueType deriving(Bits, Eq);

module mkFifofByType#(Integer depth, QueuedClientServerQueueType typ, Clock srcClk, Clock dstClk, Reset srcRst)(FIFOF#(tData)) provisos(Bits#(tData, szData));
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
    else if (typ == QueuedClientServerQueueTypeSync) begin
        SyncFIFOIfc#(tData) syncQ <- mkSyncFIFO(depth, srcClk, srcRst, dstClk);
        q <- mkSyncFifoToFifoF(syncQ);
    end
    return q;
endmodule


interface QueuedClient#(type t_req, type t_resp);
    interface Client#(t_req, t_resp) clt;
    method Action putReq(t_req req);
    method Bool canPutReq;

    method ActionValue#(t_resp) getResp();
    method Bool hasResp;
endinterface


module mkSizedQueuedClient#(
        String name, 
        Integer reqDepth, 
        Integer respDepth, 
        QueuedClientServerQueueType reqType,
        QueuedClientServerQueueType respType,
        Clock srcClk,
        Clock dstClk,
        Reset srcRst
    )(QueuedClient#(t_req, t_resp)) provisos (
        Bits#(t_req, sz_req),
        Bits#(t_resp, sz_resp)
    );
    
    FIFOF#(t_req) reqQ <- mkFifofByType(reqDepth, reqType, srcClk, dstClk, srcRst);
    FIFOF#(t_resp) respQ <- mkFifofByType(respDepth, respType, srcClk, dstClk, srcRst);

    // rule debug;
    //     if (!reqQ.notFull) begin
    //         $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkQueuedClient ", fshow(name) , " reqQ");
    //     end
    //     if (!respQ.notFull) begin
    //         $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkQueuedClient ", fshow(name) , " respQ");
    //     end
    // endrule

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
    let curClk <- exposeCurrentClock;
    let curRst <- exposeCurrentReset;
    let t <- mkSizedQueuedClient(name, 2, 2, QueuedClientServerQueueTypeNormal, QueuedClientServerQueueTypeNormal, curClk, curClk, curRst);
    return t;
endmodule


interface QueuedServer#(type t_req, type t_resp);
    interface Server#(t_req, t_resp) srv;

    method ActionValue#(t_req) getReq();
    method Bool hasReq;

    method Action putResp(t_resp resp);
    method Bool canPutResp;
endinterface

module mkSizedQueuedServer#(String name, 
        Integer reqDepth,
        Integer respDepth, 
        QueuedClientServerQueueType reqType, 
        QueuedClientServerQueueType respType,
        Clock srcClk,
        Clock dstClk,
        Reset srcRst
    )(QueuedServer#(t_req, t_resp)) provisos (
        Bits#(t_req, sz_req),
        Bits#(t_resp, sz_resp)
    );

    FIFOF#(t_req) reqQ <- mkFifofByType(reqDepth, reqType, srcClk, dstClk, srcRst);
    FIFOF#(t_resp) respQ <- mkFifofByType(respDepth, respType, srcClk, dstClk, srcRst);

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
    let curClk <- exposeCurrentClock;
    let curRst <- exposeCurrentReset;
    let t <- mkSizedQueuedServer(name, 2, 2, QueuedClientServerQueueTypeNormal, QueuedClientServerQueueTypeNormal, curClk, curClk, curRst);
    return t;
endmodule

function tData getAbsValue(tData a) provisos(Arith#(tData), Bitwise#(tData));
    return msb(a) == 0 ? a : (~a) + 1;
endfunction

interface Server2Client#(type tReq, type tResp);
    interface Server#(tReq, tResp) srv;
    interface Client#(tReq, tResp) clt;
endinterface

module mkServer2ClientSignleBeat(Server2Client#(tReq, tResp)) provisos (
        Bits#(tReq, szReq),
        Bits#(tResp, szResp)
    );

    Wire#(tReq) reqWire <- mkWire;
    Wire#(tResp) respWire <- mkWire;

    interface Server srv;
        interface Put request;
            method Action put(tReq req);
                reqWire <= req;
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(tResp) get;
                return respWire;
            endmethod
        endinterface
    endinterface

    interface Client clt;
        interface Put response;
            method Action put(tResp resp);
                respWire <= resp;
            endmethod
        endinterface

        interface Get request;
            method ActionValue#(tReq) get;
                return reqWire;
            endmethod
        endinterface
    endinterface

endmodule

// suppose LKey == RKey
function IndexMR   lkey2IndexMR(LKEY lkey)   = unpack(truncateLSB(lkey));
function IndexMR   rkey2IndexMR(RKEY rkey)   = unpack(truncateLSB(rkey));
function KeyPartMR lkey2KeyPartMR(LKEY lkey) = unpack(truncate(lkey));
function KeyPartMR rkey2KeyPartMR(RKEY rkey) = unpack(truncate(rkey));


function Bool isRecvPacketStatusNormal(RdmaRecvPacketStatus status);
    return msb(pack(status)) == 0;
endfunction

function Bool rdmaRespNeedDmaWrite(RdmaOpCode opcode);
    return case (opcode)
        RDMA_READ_RESPONSE_FIRST ,
        RDMA_READ_RESPONSE_MIDDLE,
        RDMA_READ_RESPONSE_LAST  ,
        RDMA_READ_RESPONSE_ONLY  ,
        ATOMIC_ACKNOWLEDGE       : True;
        default                  : False;
    endcase;
endfunction

function Bool rdmaReqNeedDmaWrite(RdmaOpCode opcode);
    return case (opcode)
        SEND_FIRST                    ,
        SEND_MIDDLE                   ,
        SEND_LAST                     ,
        SEND_LAST_WITH_IMMEDIATE      ,
        SEND_ONLY                     ,
        SEND_ONLY_WITH_IMMEDIATE      ,
        RDMA_WRITE_FIRST              ,
        RDMA_WRITE_MIDDLE             ,
        RDMA_WRITE_LAST               ,
        RDMA_WRITE_ONLY               ,
        RDMA_WRITE_LAST_WITH_IMMEDIATE,
        RDMA_WRITE_ONLY_WITH_IMMEDIATE: True;
        default                       : False;
    endcase;
endfunction

function Bool isSendReqRdmaOpCode(RdmaOpCode opcode);
    return case (opcode)
        SEND_FIRST               ,
        SEND_MIDDLE              ,
        SEND_LAST                ,
        SEND_LAST_WITH_IMMEDIATE ,
        SEND_ONLY                ,
        SEND_ONLY_WITH_IMMEDIATE ,
        SEND_LAST_WITH_INVALIDATE,
        SEND_ONLY_WITH_INVALIDATE: True;
        default                  : False;
    endcase;
endfunction

function Bool isWriteReqRdmaOpCode(RdmaOpCode opcode);
    return case (opcode)
        RDMA_WRITE_FIRST              ,
        RDMA_WRITE_MIDDLE             ,
        RDMA_WRITE_LAST               ,
        RDMA_WRITE_LAST_WITH_IMMEDIATE,
        RDMA_WRITE_ONLY               ,
        RDMA_WRITE_ONLY_WITH_IMMEDIATE: True;
        default                       : False;
    endcase;
endfunction

function Bool isReadReqRdmaOpCode(RdmaOpCode opcode);
    return opcode == RDMA_READ_REQUEST;
endfunction

function Bool isAtomicReqRdmaOpCode(RdmaOpCode opcode);
    return case (opcode)
        COMPARE_SWAP,
        FETCH_ADD   : True;
        default     : False;
    endcase;
endfunction

function Bool isReadRespRdmaOpCode(RdmaOpCode opcode);
    return case (opcode)
        RDMA_READ_RESPONSE_FIRST ,
        RDMA_READ_RESPONSE_MIDDLE,
        RDMA_READ_RESPONSE_LAST  ,
        RDMA_READ_RESPONSE_ONLY  : True;
        default                  : False;
    endcase;
endfunction

function Bool isFirstRdmaOpCode(RdmaOpCode opcode);
    return case (opcode)
        SEND_FIRST              ,
        RDMA_WRITE_FIRST        ,
        RDMA_READ_RESPONSE_FIRST: True;

        default                 : False;
    endcase;
endfunction

function Bool isOnlyRdmaOpCode(RdmaOpCode opcode);
    return case (opcode)
        SEND_ONLY                     ,
        SEND_ONLY_WITH_IMMEDIATE      ,
        SEND_ONLY_WITH_INVALIDATE     ,

        RDMA_WRITE_ONLY               ,
        RDMA_WRITE_ONLY_WITH_IMMEDIATE,

        RDMA_READ_REQUEST             ,
        COMPARE_SWAP                  ,
        FETCH_ADD                     ,

        RDMA_READ_RESPONSE_ONLY       ,

        ACKNOWLEDGE                   ,
        ATOMIC_ACKNOWLEDGE            : True;

        default                       : False;
    endcase;
endfunction

function Bool isFirstOrOnlyRdmaOpCode(RdmaOpCode opcode);
    return isFirstRdmaOpCode(opcode) || isOnlyRdmaOpCode(opcode);
endfunction

function RETH extractPriRETH(RdmaExtendHeaderBuffer extendHeaderBuffer, TransType transType);
    let reth = case (transType)
        TRANS_TYPE_XRC: unpack(extendHeaderBuffer[
            valueOf(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) - valueOf(XRCETH_WIDTH) -1 :
            valueOf(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) - valueOf(XRCETH_WIDTH) - valueOf(RETH_WIDTH)
        ]);
        default: unpack(extendHeaderBuffer[
            valueOf(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) -1 :
            valueOf(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) - valueOf(RETH_WIDTH)
        ]);
    endcase;
    return reth;
endfunction

function RETH extractSecRETH(RdmaExtendHeaderBuffer extendHeaderBuffer, TransType transType, RdmaOpCode opcode);
    let reth = case (transType)
        TRANS_TYPE_XRC: unpack(extendHeaderBuffer[
            valueOf(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) - valueOf(XRCETH_WIDTH) -1 :
            valueOf(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) - valueOf(XRCETH_WIDTH) - valueOf(RETH_WIDTH)
        ]);
        default: begin
            case (opcode)
                RDMA_READ_REQUEST:
                    unpack(extendHeaderBuffer[
                        valueOf(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) - valueOf(RETH_WIDTH) -1 :
                        valueOf(RDMA_EXTEND_HEADER_BUFFER_BIT_WIDTH) - valueOf(RETH_WIDTH) - valueOf(RETH_WIDTH)
                    ]);
                default: unpack(0);  // error("Opcode does not support secondary RETH");
            endcase
        end
    endcase;
    return reth;
endfunction


function Bool containAccessTypeFlag(
    FlagsType#(MemAccessTypeFlag) flags, MemAccessTypeFlag flag
);
    return containEnum(flags, flag);
    // return !isZero(pack(flags & enum2Flag(flag)));
endfunction