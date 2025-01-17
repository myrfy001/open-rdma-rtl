import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import Clocks :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import CsrRootConnector :: *;
import CsrAddress :: *;
import CsrFramework :: *;

import StreamDataTypes :: *;
import BasicDataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;
import AddressChunker :: *;
import EthernetTypes :: *;
import PayloadGenAndCon :: *;
import EthernetFrameIO :: *;
import StreamShifterG :: *;
import DtldStream :: *;
import QPContext :: *;
import IoChannels :: *;

typedef union tagged {
    IMM  Imm;
    RKEY RKey;
} ImmOrRKey deriving(Bits, FShow);

typedef struct {
    MSN msn;                                        // 16 bits
    WorkReqOpCode opcode;                           // 4  bits
    FlagsType#(WorkReqSendFlag) flags;              // 5  bits
    TypeQP qpType;                                  // 4  bits
    PSN psn;                                        // 24 bits
    PMTU pmtu;                                      // 3 bits
    IpAddr dqpIP;                                   // 32 bits
    EthMacAddr macAddr;                             // 48 bits
    ADDR   laddr;                                   // 64 bits
    LKEY   lkey;                                    // 32 bits
    ADDR raddr;                                     // 64 bits
    RKEY rkey;                                      // 32 bits
    Length len;                                     // 32 bits
    Length totalLen;                                // 32 bits
    QPN dqpn;                                       // 24 bits
    QPN sqpn;                                       // 24 bits
    Maybe#(Long) comp;                              // 65 bits
    Maybe#(Long) swap;                              // 65 bits
    Maybe#(ImmOrRKey) immDtOrInvRKey;               // 34 bits
    Maybe#(QPN) srqn; // for XRC                    // 25 bits
    Maybe#(QKEY) qkey; // for UD                    // 33 bits
    Bool isFirst;                                   // 1  bit
    Bool isLast;                                    // 1  bit
    Bool isRetry;                                   // 1  bit
    Bool enableEcn;                                 // 1  bit
} WorkQueueElem deriving(Bits, FShow);




function Maybe#(RdmaOpCode) genRdmaOpCode(WorkReqOpCode wrOpCode, Bool isFirst, Bool isLast);


    return case ({pack(isFirst), pack(isLast)})
        'b00:   case (wrOpCode)
                    IBV_WR_RDMA_WRITE:                  tagged Valid RDMA_WRITE_MIDDLE;
                    IBV_WR_RDMA_WRITE_WITH_IMM:         tagged Valid RDMA_WRITE_MIDDLE;
                    IBV_WR_SEND:                        tagged Valid SEND_MIDDLE;
                    IBV_WR_SEND_WITH_IMM:               tagged Valid SEND_MIDDLE;
                    IBV_WR_SEND_WITH_INV:               tagged Valid SEND_MIDDLE;
                    IBV_WR_RDMA_READ_RESP:              tagged Valid RDMA_READ_RESPONSE_MIDDLE;
                    default:                            tagged Invalid;
                endcase
        'b01:   case (wrOpCode)
                IBV_WR_RDMA_WRITE:                  tagged Valid RDMA_WRITE_LAST;
                IBV_WR_RDMA_WRITE_WITH_IMM:         tagged Valid RDMA_WRITE_LAST_WITH_IMMEDIATE;
                IBV_WR_SEND:                        tagged Valid SEND_LAST;
                IBV_WR_SEND_WITH_IMM:               tagged Valid SEND_LAST_WITH_IMMEDIATE;
                IBV_WR_SEND_WITH_INV:               tagged Valid SEND_LAST_WITH_INVALIDATE;
                IBV_WR_RDMA_READ_RESP:              tagged Valid RDMA_READ_RESPONSE_LAST;
                default:                            tagged Invalid;
            endcase
        'b10:   case (wrOpCode)
            IBV_WR_RDMA_WRITE:                  tagged Valid RDMA_WRITE_FIRST;
            IBV_WR_RDMA_WRITE_WITH_IMM:         tagged Valid RDMA_WRITE_FIRST;
            IBV_WR_SEND:                        tagged Valid SEND_FIRST;
            IBV_WR_SEND_WITH_IMM:               tagged Valid SEND_FIRST;
            IBV_WR_SEND_WITH_INV:               tagged Valid SEND_FIRST;
            IBV_WR_RDMA_READ_RESP:              tagged Valid RDMA_READ_RESPONSE_FIRST;
            default:                            tagged Invalid;
        endcase
        'b11:   case (wrOpCode)
            IBV_WR_RDMA_WRITE:                  tagged Valid RDMA_WRITE_ONLY;
            IBV_WR_RDMA_WRITE_WITH_IMM:         tagged Valid RDMA_WRITE_ONLY_WITH_IMMEDIATE;
            IBV_WR_SEND:                        tagged Valid SEND_ONLY;
            IBV_WR_SEND_WITH_IMM:               tagged Valid SEND_ONLY_WITH_IMMEDIATE;
            IBV_WR_SEND_WITH_INV:               tagged Valid SEND_ONLY_WITH_INVALIDATE;
            IBV_WR_RDMA_READ_RESP:              tagged Valid RDMA_READ_RESPONSE_ONLY;
            IBV_WR_RDMA_READ:                   tagged Valid RDMA_READ_REQUEST;
            IBV_WR_ATOMIC_CMP_AND_SWP:          tagged Valid COMPARE_SWAP;
            IBV_WR_ATOMIC_FETCH_AND_ADD:        tagged Valid FETCH_ADD;
            IBV_WR_RDMA_ACK:                    tagged Valid ACKNOWLEDGE;
            default:                            tagged Invalid;
        endcase
    endcase;
endfunction

function XRCETH genXRCETH(WorkQueueElem wqe);
    return XRCETH {
            srqn: unwrapMaybe(wqe.srqn),
            rsvd: unpack(0)
        };
        
endfunction

function DETH genDETH(WorkQueueElem wqe);
    return  DETH {
            qkey: unwrapMaybe(wqe.qkey),
            sqpn: wqe.sqpn,
            rsvd: unpack(0)
        };
        
endfunction

function RETH genRETH(
    WorkReqOpCode wrOpCode, ADDR raddr, RKEY rkey, Length dlen
);
    return RETH {
            va  : raddr,
            rkey: rkey,
            dlen: dlen
        };
endfunction

function RRETH genRRETH(WorkQueueElem wqe);
    return RRETH {
            va  : wqe.laddr,
            lkey: wqe.lkey
        };
endfunction

// TODO: check fetch add needs both swap and comp?
function AtomicEth genAtomicEth(WorkQueueElem wqe);
    if (wqe.swap matches tagged Valid .swap &&& wqe.comp matches tagged Valid .comp) begin
        return AtomicEth {
                va  : wqe.raddr,
                rkey: wqe.rkey,
                swap: swap,
                comp: comp
            };
    end
    else begin
        return ?;
    end
endfunction

function ImmDt genImmDt(WorkQueueElem wqe);

    if (
        wqe.immDtOrInvRKey matches tagged Valid .immDtOrInvRKey &&&
        immDtOrInvRKey     matches tagged Imm   .immDt
    ) begin
        return ImmDt {
            data: immDt
        };
    end
    else begin
        return ?;
    end

endfunction

function IETH genIETH(WorkQueueElem wqe);
    if (
        wqe.immDtOrInvRKey matches tagged Valid .immDtOrInvRKey &&&
        immDtOrInvRKey     matches tagged RKey  .rkey2Inv       &&&
        wqe.opcode == IBV_WR_SEND_WITH_INV
    ) begin
        return IETH {
            rkey: rkey2Inv
        };
    end
    else begin
        return ?;
    end
endfunction

function AETH genAETH(WorkQueueElem wqe);
    return ?;
    // return AETH {
    //     rsvd1: unpack(0),
    //     code : AETH_CODE_ACK,
    //     value: unpack(pack(AETH_ACK_VALUE_INVALID_CREDIT_CNT)),
    //     msn  : zeroExtend(wqe.pkey)
    // };
endfunction

function NRETH genNRETH(WorkQueueElem wqe);
    // hardware only generate ACK, not NAK
    return unpack(0);
endfunction

function ActionValue#(Maybe#(BTH)) genRdmaBTH(
        WorkQueueElem wqe, Bool isFirst, Bool isLast, Bool solicited, PSN psn, PAD padCnt,
        Bool ackReq, ADDR remoteAddr, Length dlen
    );

    return actionvalue
        let maybeTrans  = qpType2TransType(wqe.qpType);
        let maybeOpCode = genRdmaOpCode(wqe.opcode, isFirst, isLast);

        let isOnlyReqPkt = isFirst && isLast;

        if (
            maybeTrans  matches tagged Valid .trans  &&&
            maybeOpCode matches tagged Valid .opcode
        ) begin
            let bth = BTH {
                trans    : trans,
                opcode   : opcode,
                solicited: solicited,
                isRetry  : wqe.isRetry,
                padCnt   : padCnt,
                tver     : unpack(0),
                msn      : wqe.msn,
                fecn     : unpack(0),
                becn     : unpack(0),
                resv6    : unpack(0),
                dqpn     : wqe.dqpn,
                ackReq   : ackReq,
                resv7    : unpack(0),
                psn      : psn
            };
            return tagged Valid bth;
        end
        else begin
            return tagged Invalid;
        end
    endactionvalue;
endfunction

function ActionValue#(Maybe#(RdmaExtendHeaderBuffer)) genRdmaExtendHeader(
        WorkQueueElem wqe, Bool isFirst, Bool isLast, ADDR remoteAddr, Length dlen
    );
    return actionvalue
        let maybeTrans  = qpType2TransType(wqe.qpType);
        let maybeOpCode = genRdmaOpCode(wqe.opcode, isFirst, isLast);

        let isOnlyReqPkt = isFirst && isLast;

        if (
            maybeTrans  matches tagged Valid .trans  &&&
            maybeOpCode matches tagged Valid .opcode
        ) begin
            let xrceth    = genXRCETH(wqe);
            let deth      = genDETH(wqe);
            let reth      = genRETH(wqe.opcode, remoteAddr, wqe.rkey, dlen);
            let rreth     = genRRETH(wqe);
            let atomicEth = genAtomicEth(wqe);
            let immDt     = genImmDt(wqe);
            let ieth      = genIETH(wqe);
            let aeth      = genAETH(wqe);
            let nreth     = genNRETH(wqe);

            case (wqe.opcode)
                IBV_WR_RDMA_WRITE: begin
                    return case (wqe.qpType)
                        IBV_QPT_RC,
                        IBV_QPT_UC: tagged Valid buildRdmaExtendHeaderBuffer({ pack((reth)) });
                        IBV_QPT_XRC_SEND: tagged Valid buildRdmaExtendHeaderBuffer({ pack((xrceth)), pack((reth)) });
                        default: tagged Invalid;
                    endcase;
                end
                IBV_WR_RDMA_WRITE_WITH_IMM: begin
                    return case (wqe.qpType)
                        IBV_QPT_RC,
                        IBV_QPT_UC: tagged Valid (
                            isLast ?
                                buildRdmaExtendHeaderBuffer({ pack((reth)), pack((immDt))}) :
                                buildRdmaExtendHeaderBuffer({ pack((reth))})
                        );
                        IBV_QPT_XRC_SEND: tagged Valid (
                            isLast ?
                                buildRdmaExtendHeaderBuffer({ pack((xrceth)), pack((reth)), pack((immDt)) }) :
                                buildRdmaExtendHeaderBuffer({ pack((xrceth)), pack((reth)) })
                        );
                        default: tagged Invalid;
                    endcase;
                end
                IBV_WR_SEND: begin
                    return case (wqe.qpType)
                        IBV_QPT_RC,
                        IBV_QPT_UC: tagged Valid buildRdmaExtendHeaderBuffer(1'b0);
                        IBV_QPT_UD: tagged Valid buildRdmaExtendHeaderBuffer({ pack((deth)) });
                        IBV_QPT_XRC_SEND: tagged Valid buildRdmaExtendHeaderBuffer({ pack((xrceth)) });
                        default: tagged Invalid;
                    endcase;
                end
                IBV_WR_SEND_WITH_IMM: begin
                    if (wqe.qpType == IBV_QPT_UD) begin
                        immAssert(
                            isLast,
                            "UD always has only pkt, so isLast must be True",
                            $format("")
                        );
                    end

                    return case (wqe.qpType)
                        IBV_QPT_RC,
                        IBV_QPT_UC: tagged Valid (
                            isLast ?
                                buildRdmaExtendHeaderBuffer({ pack((immDt)) }) :
                                buildRdmaExtendHeaderBuffer(1'b0)
                        );
                        // UD always has only pkt, so isLast always True
                        IBV_QPT_UD: tagged Valid buildRdmaExtendHeaderBuffer({ pack((deth)), pack((immDt)) });
                        IBV_QPT_XRC_SEND: tagged Valid (
                            isLast ?
                                buildRdmaExtendHeaderBuffer({ pack((xrceth)), pack((immDt)) }) :
                                buildRdmaExtendHeaderBuffer({ pack((xrceth)) })
                        );
                        default: tagged Invalid;
                    endcase;
                end
                IBV_WR_SEND_WITH_INV: begin
                    return case (wqe.qpType)
                        IBV_QPT_RC: tagged Valid (
                            isLast ?
                                buildRdmaExtendHeaderBuffer({ pack((ieth)) }) :
                                buildRdmaExtendHeaderBuffer(1'b0)
                        );
                        IBV_QPT_XRC_SEND: tagged Valid (
                            isLast ?
                                buildRdmaExtendHeaderBuffer({ pack((xrceth)), pack((ieth)) }) :
                                buildRdmaExtendHeaderBuffer({ pack((xrceth)) })
                        );
                        default: tagged Invalid;
                    endcase;
                end
                IBV_WR_RDMA_READ: begin
                    return case (wqe.qpType)
                        IBV_QPT_RC: tagged Valid buildRdmaExtendHeaderBuffer({ pack((reth)), pack((rreth)) });
                        IBV_QPT_XRC_SEND: tagged Valid buildRdmaExtendHeaderBuffer({ pack((xrceth)), pack((reth)), pack((rreth)) });
                        default: tagged Invalid;
                    endcase;
                end
                IBV_WR_ATOMIC_CMP_AND_SWP  ,
                IBV_WR_ATOMIC_FETCH_AND_ADD: begin
                    return case (wqe.qpType)
                        IBV_QPT_RC: tagged Valid buildRdmaExtendHeaderBuffer({ pack((atomicEth)) });
                        IBV_QPT_XRC_SEND: tagged Valid buildRdmaExtendHeaderBuffer({ pack((xrceth)), pack((atomicEth)) });
                        default: tagged Invalid;
                    endcase;
                end
                IBV_WR_RDMA_READ_RESP: begin
                    return case (wqe.qpType)
                        IBV_QPT_RC      ,
                        IBV_QPT_XRC_SEND,
                        IBV_QPT_XRC_RECV: tagged Valid buildRdmaExtendHeaderBuffer({ pack((reth)) });
                        default         : tagged Invalid;
                    endcase;
                end
                IBV_WR_RDMA_ACK: begin
                    return case (wqe.qpType)
                        IBV_QPT_RC      : tagged Valid buildRdmaExtendHeaderBuffer({ pack((aeth)) });
                        default         : tagged Invalid;
                    endcase;
                end
                default: return tagged Invalid;
            endcase
        end
        else begin
            return tagged Invalid;
        end
    endactionvalue;
endfunction


function Bool workReqNeedPayloadGen(WorkReqOpCode opcode);
    return case (opcode)
        IBV_WR_RDMA_WRITE         ,
        IBV_WR_RDMA_WRITE_WITH_IMM,
        IBV_WR_SEND               ,
        IBV_WR_SEND_WITH_IMM      ,
        IBV_WR_SEND_WITH_INV      ,
        IBV_WR_RDMA_READ_RESP     : True;
        default                   : False;
    endcase;
endfunction



typedef struct {
    WorkQueueElem wqe;
    Bool hasPayload;
} GenPacketHeaderStep1PipelineEntry deriving (Bits, FShow);

typedef struct {
    WorkQueueElem wqe;
    Bool hasPayload;
    Bool isFirstPacket;
    Bool isLastPacket;
    Bool solicited;
    PSN psn;
    Bool ackReq;
    ADDR remoteAddr;
    Length dlen;
    UdpLength udpPayloadLen;
    Length truncatedStreamSplitEndAddrForAlignCalc;
} GenPacketHeaderStep2PipelineEntry deriving (Bits, FShow);


typedef struct {
    WorkQueueElem wqe;
    Bool hasPayload;
} SendChunkByRemoteAddrReqAndPayloadGenReqPipelineEntry deriving (Bits, FShow);

typedef TDiv#(MAX_PMTU, BYTE_CNT_PER_DWOED)   PACKET_GEN_AND_PARSE_MAX_DWORD_CNT_PER_PACKET;
typedef TAdd#(1, TLog#( PACKET_GEN_AND_PARSE_MAX_DWORD_CNT_PER_PACKET))     PACKET_GEN_AND_PARSE_MAX_DWORD_CNT_PER_PACKET_WIDTH;
typedef Bit#( PACKET_GEN_AND_PARSE_MAX_DWORD_CNT_PER_PACKET_WIDTH)         AlignBlockCntInPmtu;

interface PacketGen;
    interface PipeIn#(WorkQueueElem) wqePipeIn;
    interface PipeOut#(IoChannelEthDataStream) packetPipeOut;

    interface Client#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryClt;

    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 

    interface PipeOut#(PayloadGenReq) genReqPipeOut;
    interface PipeIn#(DataStream) genRespPipeIn;
endinterface

(* synthesize *)
module mkPacketGen(PacketGen);

    FIFOF#(WorkQueueElem)       wqePipeInQ      <- mkLFIFOF;
    FIFOF#(PayloadGenReq)       genReqPipeOutQ  <- mkLFIFOF;
    FIFOF#(DataStream)          genRespPipeInQ  <- mkLFIFOF;

    AddressChunker#(ADDR, Length, ChunkAlignLogValue) wqeToPacketChunker <- mkAddressChunker;


    StreamShifterG#(DATA) payloadStreamShifter <- mkBiDirectionStreamShifterLsbRightG;
    mkConnection(toPipeOut(genRespPipeInQ), payloadStreamShifter.streamPipeIn);

    DtldStreamSplitor#(DATA, AlignBlockCntInPmtu, LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE) payloadSplitor <- mkDtldStreamSplitor;
    mkConnection(payloadStreamShifter.streamPipeOut, payloadSplitor.dataPipeIn);

    FIFOF#(DataStream) perPacketPayloadDataStreamQ <- mkLFIFOF;

    EthernetPacketGenerator ethernetPacketGen <- mkEthernetPacketGenerator;
    mkConnection(toPipeOut(perPacketPayloadDataStreamQ), ethernetPacketGen.rdmaPayloadPipeIn);

    Reg#(PSN) psnReg <- mkRegU;

    QueuedClient#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryCltInst <- mkQueuedClient("mrTableQueryCltInst");

    // Pipeline Queues
    FIFOF#(SendChunkByRemoteAddrReqAndPayloadGenReqPipelineEntry) sendChunkByRemoteAddrReqAndPayloadGenReqPipelineQ <- mkSizedFIFOF(4);
    FIFOF#(GenPacketHeaderStep1PipelineEntry) genPacketHeaderStep1PipelineQ <- mkSizedFIFOF(4);
    FIFOF#(GenPacketHeaderStep2PipelineEntry) genPacketHeaderStep2PipelineQ <- mkLFIFOF;
    
    rule debugRule;
        if (!sendChunkByRemoteAddrReqAndPayloadGenReqPipelineQ.notFull) $display("time=%0t, ", $time, "FullQueue: sendChunkByRemoteAddrReqAndPayloadGenReqPipelineQ");
        if (!genPacketHeaderStep1PipelineQ.notFull) $display("time=%0t, ", $time, "FullQueue: genPacketHeaderStep1PipelineQ");
        if (!genPacketHeaderStep2PipelineQ.notFull) $display("time=%0t, ", $time, "FullQueue: genPacketHeaderStep2PipelineQ");

    endrule
    
    rule queryMrTable;
        let wqe = wqePipeInQ.first;
        wqePipeInQ.deq;
        Bool isZeroPayload = isZeroR(wqe.len);
        Bool hasPayload = workReqNeedPayloadGen(wqe.opcode) && !isZeroPayload;

        if (hasPayload) begin
            let mrTableQueryReq = MrTableQueryReq{
                idx: lkey2IndexMR(wqe.lkey)
            };
            mrTableQueryCltInst.putReq(mrTableQueryReq);
        end
        

        let pipelineEntryOut = SendChunkByRemoteAddrReqAndPayloadGenReqPipelineEntry{
            wqe: wqe,
            hasPayload: hasPayload
        };
        sendChunkByRemoteAddrReqAndPayloadGenReqPipelineQ.enq(pipelineEntryOut);

        $display(
            "time=%0t:", $time, toGreen(" mkPacketGen queryMrTable"),
            toBlue(", wqe="), fshow(wqe),
            toBlue(", hasPayload="), fshow(hasPayload)
        );
    endrule

    rule sendChunkByRemoteAddrReqAndPayloadGenReq;
        let pipelineEntryIn = sendChunkByRemoteAddrReqAndPayloadGenReqPipelineQ.first;
        sendChunkByRemoteAddrReqAndPayloadGenReqPipelineQ.deq;

        let wqe = pipelineEntryIn.wqe;
        let hasPayload = pipelineEntryIn.hasPayload;

        
        if (hasPayload) begin
            let remoteAddrChunkReq = AddressChunkReq{
                startAddr: wqe.raddr,
                len: wqe.len,
                chunk: getPmtuSizeByPmtuEnum(wqe.pmtu)
            };
            wqeToPacketChunker.requestPipeIn.enq(remoteAddrChunkReq);


            let mrTableMaybe <- mrTableQueryCltInst.getResp;
            immAssert(
                isValid(mrTableMaybe),
                "mrTable must be valid here.",
                $format("wqe=", fshow(wqe))
            );

            // TODO: if we have enough resource on FPGA, we should check mrTable is valid on hardware, discard and report the WQE to software if not.
            let mrTable = fromMaybe(?, mrTableMaybe);

            let payloadGenReq = PayloadGenReq{
                addr:  wqe.laddr,
                len: wqe.len,
                baseVA: mrTable.baseVA,
                pgtOffset: mrTable.pgtOffset
            };
            genReqPipeOutQ.enq(payloadGenReq);

            ByteIdxInDword localAddrOffset = truncate(wqe.laddr);
            ByteIdxInDword remoteAddrOffset = truncate(wqe.raddr);
            DataBusSignedShiftOffset localToRemoteAlignShiftOffset = zeroExtend(localAddrOffset) - zeroExtend(remoteAddrOffset);
            payloadStreamShifter.offsetPipeIn.enq(localToRemoteAlignShiftOffset);
        end


        let pipelineEntryOut = GenPacketHeaderStep1PipelineEntry{
            wqe: wqe,
            hasPayload: hasPayload
        };
        genPacketHeaderStep1PipelineQ.enq(pipelineEntryOut);

        $display(
            "time=%0t:", $time, toGreen(" mkPacketGen sendChunkByRemoteAddrReqAndPayloadGenReq"),
            toBlue(", wqe="), fshow(wqe),
            toBlue(", hasPayload="), fshow(hasPayload)
        );
    endrule

    rule genPacketHeaderStep1;
        let pipelineEntryIn = genPacketHeaderStep1PipelineQ.first;
        let wqe = pipelineEntryIn.wqe;
        let hasPayload = pipelineEntryIn.hasPayload;

        // if the message doesn't have payload, then it is always a "Only" request
        Bool isFirstPacket = wqe.isFirst;
        Bool isLastPacket = wqe.isLast;

        let psn = psnReg;

        let ackReq = containWorkReqFlag(wqe.flags, IBV_SEND_SIGNALED);
        let solicited = containWorkReqFlag(wqe.flags, IBV_SEND_SOLICITED);

        let remoteAddr = dontCareValue;
        let dlen = dontCareValue;

        Length truncatedStreamSplitEndAddrForAlignCalc = dontCareValue;

        UdpLength udpPayloadLen = fromInteger(valueOf(RDMA_FIXED_HEADER_BYTE_NUM));

        let packetInfo = ?;
        if (hasPayload) begin

            packetInfo = wqeToPacketChunker.responsePipeOut.first;
            wqeToPacketChunker.responsePipeOut.deq;

            truncatedStreamSplitEndAddrForAlignCalc = truncate(packetInfo.startAddr + zeroExtend(packetInfo.len - 1));
        
            isFirstPacket = isFirstPacket && packetInfo.isFirst;
            isLastPacket = isLastPacket && packetInfo.isLast;
            
            if (packetInfo.isLast) begin
                genPacketHeaderStep1PipelineQ.deq;
            end

            let packetToBeatChunkReq = AddressChunkReq{
                startAddr: packetInfo.startAddr,
                len: packetInfo.len,
                chunk: dontCareValue
            };

            if (packetInfo.isFirst) begin
                psn = wqe.psn;
                psnReg <= psn + 1;
            end
            else begin
                psnReg <= psn + 1;
            end

            remoteAddr = packetInfo.startAddr;
            dlen = isFirstPacket ? wqe.totalLen : packetInfo.len;

            ByteIdxInDword paddingByteNumForRemoteAddressAlign = truncate(remoteAddr);
            udpPayloadLen = udpPayloadLen + truncate(packetInfo.len) + zeroExtend(paddingByteNumForRemoteAddressAlign);

        end
        else begin
            immAssert(
                wqe.isFirst && wqe.isLast,
                "if the message doesn't have payload, then it is always a \"Only\" request",
                $format("wqe=", fshow(wqe))
            );
            psn = wqe.psn;
        end

        let pipelineEntryOut = GenPacketHeaderStep2PipelineEntry{
            wqe: wqe,
            hasPayload: hasPayload,
            isFirstPacket: isFirstPacket,
            isLastPacket: isLastPacket,
            solicited: solicited,
            psn: psn,
            ackReq: ackReq,
            remoteAddr: remoteAddr,
            dlen: dlen,
            udpPayloadLen: udpPayloadLen,
            truncatedStreamSplitEndAddrForAlignCalc: truncatedStreamSplitEndAddrForAlignCalc
        };
        genPacketHeaderStep2PipelineQ.enq(pipelineEntryOut);
        $display(
            "time=%0t:", $time, toGreen(" mkPacketGen genPacketHeaderStep1"),
            toBlue(", pipelineEntryIn="), fshow(pipelineEntryIn),
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut),
            toBlue(", packetInfo="), hasPayload ? fshow(packetInfo) : fshow("No payload")
        );
    endrule

    rule genPacketHeaderStep2;

        let pipelineEntryIn = genPacketHeaderStep2PipelineQ.first;
        genPacketHeaderStep2PipelineQ.deq;
        let wqe = pipelineEntryIn.wqe;
        let hasPayload = pipelineEntryIn.hasPayload;
        let isFirstPacket = pipelineEntryIn.isFirstPacket;
        let isLastPacket = pipelineEntryIn.isLastPacket;
        let solicited = pipelineEntryIn.solicited;
        let psn = pipelineEntryIn.psn;
        let ackReq = pipelineEntryIn.ackReq;
        let remoteAddr = pipelineEntryIn.remoteAddr;
        let dlen = pipelineEntryIn.dlen;
        let udpPayloadLen = pipelineEntryIn.udpPayloadLen;
        Length truncatedStreamSplitStartAddr = truncate(pipelineEntryIn.remoteAddr);
        Length truncatedStreamSplitEndAddrForAlignCalc = pipelineEntryIn.truncatedStreamSplitEndAddrForAlignCalc;

        let padCnt = 0;  // since payload is already aligned to remote address, no padding is needed.

        let bthMaybe <- genRdmaBTH(wqe, isFirstPacket, isLastPacket, solicited, psn, padCnt, ackReq, remoteAddr, dlen);
        let extendHeaderBufferMaybe <- genRdmaExtendHeader(wqe, isFirstPacket, isLastPacket, remoteAddr, dlen);

        if (bthMaybe matches tagged Valid .bth &&& extendHeaderBufferMaybe matches tagged Valid .extendHeaderBuffer) begin
            let rdmaPacketMeta = RdmaSendPacketMeta {
                header: RdmaBthAndExtendHeader{
                    bth: bth,
                    rdmaExtendHeaderBuf: extendHeaderBuffer
                },
                hasPayload: hasPayload
            };
            ethernetPacketGen.rdmaPacketMetaPipeIn.enq(rdmaPacketMeta);
        end
        else begin
            immFail(
                "bthMaybe and extendHeaderBufferMaybe should not be Invalid", 
                $format("bthMaybe=", fshow(bthMaybe), ", extendHeaderBufferMaybe=", fshow(extendHeaderBufferMaybe))
            );
        end

        if (hasPayload) begin
            AlignBlockCntInPmtu alignBlockCntForStreamSplit = truncate( 
                    (truncatedStreamSplitEndAddrForAlignCalc >> valueOf(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE)) - 
                    (truncatedStreamSplitStartAddr >> valueOf(LOG_OF_DATA_STREAM_ALIGN_BLOCK_SIZE))
                ) + 1;
            payloadSplitor.streamAlignBlockCountPipeIn.enq(alignBlockCntForStreamSplit);
        end

        let macIpUdpMeta = ThinMacIpUdpMetaDataForSend{
            dstMacAddr: wqe.macAddr,
            ipDscp: 0,
            ipEcn: wqe.enableEcn ? pack(IpHeaderEcnFlagEnabled) : pack(IpHeaderEcnFlagNotEnabled),
            dstIpAddr: wqe.dqpIP,
            srcPort: truncate(wqe.sqpn),
            dstPort: fromInteger(valueOf(UDP_PORT_RDMA)),
            udpPayloadLen: udpPayloadLen,
            ethType: fromInteger(valueOf(ETH_TYPE_IP))
        };
        ethernetPacketGen.macIpUdpMetaPipeIn.enq(macIpUdpMeta);


        // $display(
        //     "time=%0t:", $time, toGreen(" mkPacketGen genPacketHeader"),
        //     toBlue(", bthMaybe="), fshow(bthMaybe),
        //     toBlue(", extendHeaderBufferMaybe="), fshow(extendHeaderBufferMaybe)
        // );


        // let pipelineEntryOut = GenEthernetPacketPipelineEntry{
        //     wqe: pipelineEntryIn.wqe,
        //     hasPayload: pipelineEntryIn.hasPayload
        // };
        // genEthernetPacketReqPipelineQ.enq(pipelineEntryOut);
    endrule

    rule forwardSplitStream;
        // since the output of payloadGen is a single very long stream, we need to split it into
        // multi sub-stream according to packet boundary.

        let ds = payloadSplitor.dataPipeOut.first;
        payloadSplitor.dataPipeOut.deq;
        perPacketPayloadDataStreamQ.enq(ds);

        $display(
            "time=%0t:", $time, toGreen(" mkPacketGen forwardSplitStream"),
            toBlue(", ds="), fshow(ds)
        );
    endrule


    method setLocalNetworkSettings = ethernetPacketGen.setLocalNetworkSettings; 

    interface wqePipeIn = toPipeIn(wqePipeInQ);
    interface packetPipeOut = ethernetPacketGen.ethernetPacketPipeOut;
    interface mrTableQueryClt = mrTableQueryCltInst.clt;
    interface genReqPipeOut = toPipeOut(genReqPipeOutQ);
    interface genRespPipeIn = toPipeIn(genRespPipeInQ);
endmodule


interface PacketParse;
    interface BlueRdmaCsrUpStreamPort                   csrUpStreamPort;

    interface PipeIn#(IoChannelEthDataStream)           ethernetFramePipeIn;
    interface PipeOut#(ThinMacIpUdpMetaDataForRecv)     rdmaMacIpUdpMetaPipeOut;
    interface PipeOut#(RdmaRecvPacketMeta)              rdmaPacketMetaPipeOut;
    interface PipeOut#(RdmaRecvPacketTailMeta)          rdmaPacketTailMetaPipeOut;
    interface PipeOut#(DataStream)                      rdmaPayloadPipeOut;
    interface PipeOut#(DataStream)                      otherRawPacketPipeOut;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface

(* synthesize *)
module mkPacketParse(PacketParse);

    InputPacketClassifier inputPacketClassifier <- mkInputPacketClassifier;
    RdmaMetaAndPayloadExtractor rdmaHeaderExtractor <- mkRdmaMetaAndPayloadExtractor;

    mkConnection(inputPacketClassifier.rdmaRawPacketPipeOut, rdmaHeaderExtractor.ethPipeIn);

    interface csrUpStreamPort           = inputPacketClassifier.csrUpStreamPort;
    interface ethernetFramePipeIn       = inputPacketClassifier.ethRawPacketPipeIn;
    interface rdmaMacIpUdpMetaPipeOut   = inputPacketClassifier.rdmaMacIpUdpMetaPipeOut;
    interface rdmaPacketMetaPipeOut     = rdmaHeaderExtractor.rdmaPacketMetaPipeOut;
    interface rdmaPacketTailMetaPipeOut = rdmaHeaderExtractor.rdmaPacketTailMetaPipeOut;
    interface rdmaPayloadPipeOut        = rdmaHeaderExtractor.rdmaPayloadPipeOut;
    interface otherRawPacketPipeOut     = inputPacketClassifier.otherRawPacketPipeOut;

    method setLocalNetworkSettings      = inputPacketClassifier.setLocalNetworkSettings; 
endmodule

