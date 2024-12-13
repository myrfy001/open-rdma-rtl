import FIFOF :: *;
import SpecialFIFOs :: *;
import ClientServer :: *;
import GetPut :: *;
import BasicDataTypes :: *;
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

function Bool workReqHasImmDt(WorkReqOpCode opcode);
    return case (opcode)
        IBV_WR_RDMA_WRITE_WITH_IMM,
        IBV_WR_SEND_WITH_IMM: True;
        default: False;
    endcase;
endfunction

function Bool workReqHasInv(WorkReqOpCode opcode);
    return opcode == IBV_WR_SEND_WITH_INV;
endfunction