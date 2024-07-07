import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import DataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;
import AddressChunker :: *;
import EthernetTypes :: *;
import PayloadGenAndCon :: *;
import EthernetFrameIO :: *;
import StreamShifter :: *;


typedef union tagged {
    IMM  Imm;
    RKEY RKey;
} ImmOrRKey deriving(Bits, FShow);

typedef struct {
    PKEY pkey;                                      // 16 bits
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

function LETH genLETH(WorkQueueElem wqe, Length dlen);
    return LETH {
            va  : wqe.laddr,
            lkey: wqe.lkey,
            dlen: dlen
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
    return AETH {
        rsvd1: unpack(0),
        code : AETH_CODE_ACK,
        value: unpack(pack(AETH_ACK_VALUE_INVALID_CREDIT_CNT)),
        msn  : zeroExtend(wqe.pkey)
    };
endfunction

function NRETH genNRETH(WorkQueueElem wqe);
    // hardware only generate ACK, not NAK
    return unpack(0);
endfunction

function RdmaExtendHeaderBuffer buildRdmaExtendHeaderBuffer(tHeader header) provisos (
        Bits#(tHeader, szHeader),
        Add#(szHeader, a_, SizeOf#(RdmaExtendHeaderBuffer))
    );
    return zeroExtendLSB(pack(header));
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
                solicited: isOnlyReqPkt && solicited,
                migReq   : unpack(0),
                padCnt   : padCnt,
                tver     : unpack(0),
                pkey     : wqe.pkey,
                fecn     : unpack(0),
                becn     : unpack(0),
                resv6    : unpack(0),
                dqpn     : wqe.dqpn,
                ackReq   : isOnlyReqPkt && ackReq,
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
            let leth      = genLETH(wqe, dlen);
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
                        IBV_QPT_RC: tagged Valid buildRdmaExtendHeaderBuffer({ pack((reth)), pack((leth)) });
                        IBV_QPT_XRC_SEND: tagged Valid buildRdmaExtendHeaderBuffer({ pack((xrceth)), pack((reth)), pack((leth)) });
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
                        IBV_QPT_RC: tagged Valid buildRdmaExtendHeaderBuffer({ pack((aeth)), pack((nreth)) });
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
} GenPacketHeaderPipelineEntry deriving (Bits, FShow);

typedef struct {
    WorkQueueElem wqe;
    Bool hasPayload;
} GenEthernetPacketPipelineEntry deriving (Bits, FShow);

interface PacketGen;
    interface PipeIn#(WorkQueueElem) wqePipeIn;
    interface PipeOut#(EthernetNapBeatEntry) packetPipeOut;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface


module mkPacketGen(PacketGen);
    FIFOF#(WorkQueueElem) wqePipeInQ <- mkFIFOF;
    // FIFOF#(DataStream) packetPipeOutQ <- mkFIFOF;

    AddressChunkMetaCalculator#(
            ADDR, Length, PMTU, TAdd#(1, MAX_PMTU_WIDTH)
        ) wqeToPacketChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrByPMTU,
            devideLengthByPMTU,
            isAddrAndLengthLowerPartSumOverflowPMTU,
            getChunkSizeForPMTU
        );
    AddressChunker#(
            ADDR, Length, PMTU, TAdd#(1, MAX_PMTU_WIDTH)
        ) wqeToPacketChunker <- mkAddressChunker;
    mkConnection(wqeToPacketChunkMetaCalc.metaPipeOut, wqeToPacketChunker.requestPipeIn);

    AddressChunkMetaCalculator#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder, TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) packetToBeatChunkMetaCalc <- mkAddressChunkMetaCalculator(
            alignAddrForBeat,
            devideLengthForBeat,
            isAddrAndLengthLowerPartSumOverflowForBeat,
            getChunkSizeForBeat
        );
    AddressChunker#(
            ADDR, Length, BeatAddressChunkTypeDontCarePlaceHolder, TAdd#(1, BEAT_ALIGN_BIT_NUM)
        ) packetToBeatChunker <- mkAddressChunker;
    mkConnection(packetToBeatChunkMetaCalc.metaPipeOut, packetToBeatChunker.requestPipeIn);


    PayloadGenAndCon payloadGenAndCon <- mkPayloadGenAndCon;
    StreamShifter payloadStreamShifter <- mkBiDirectionStreamShifter;

    mkConnection(payloadGenAndCon.payloadGenStreamPipeOut, payloadStreamShifter.streamPipeIn);

    FIFOF#(DataStream) perPacketPayloadDataStreamQ <- mkFIFOF;

    EthernetPacketGenerator ethernetPacketGen <- mkEthernetPacketGenerator;
    mkConnection(toPipeOut(perPacketPayloadDataStreamQ), ethernetPacketGen.rdmaPayloadPipeIn);

    Reg#(PSN) psnReg <- mkRegU;

    

    // Pipeline Queues
    FIFOF#(GenPacketHeaderPipelineEntry) genPacketHeaderPipelineQ <- mkFIFOF;
    // FIFOF#(GenEthernetPacketPipelineEntry) genEthernetPacketPipelineQ <- mkFIFOF;
    
    rule sendChunkByRemoteAddrReqAndPayloadGenReq;
        let wqe = wqePipeInQ.first;
        wqePipeInQ.deq;

        Bool hasPayload = workReqNeedPayloadGen(wqe.opcode);
        if (hasPayload) begin
            let remoteAddrChunkReq = AddressChunkReq{
                startAddr: wqe.raddr,
                len: wqe.len,
                chunk: wqe.pmtu 
            };
            wqeToPacketChunkMetaCalc.requestPipeIn.enq(remoteAddrChunkReq);

            let payloadGenReq = PayloadGenReq{
                addr:  wqe.laddr,
                len: wqe.len
            };
            payloadGenAndCon.genReqPipeIn.enq(payloadGenReq);

            ByteIndexInBeat localAddrOffset = truncate(wqe.laddr);
            ByteIndexInBeat remoteAddrOffset = truncate(wqe.raddr);
            DataBusSignedShiftOffset localToRemoteAlignShiftOffset = zeroExtend(remoteAddrOffset) - zeroExtend(localAddrOffset);
            payloadStreamShifter.offsetPipeIn.enq(localToRemoteAlignShiftOffset);
        end

        

        let pipelineEntryOut = GenPacketHeaderPipelineEntry{
            wqe: wqe,
            hasPayload: hasPayload
        };
        genPacketHeaderPipelineQ.enq(pipelineEntryOut);

        $display(
            "time=%0t:", $time, toGreen(" mkPacketGen sendChunkByRemoteAddrReqAndPayloadGenReq"),
            toBlue(", wqe="), fshow(wqe),
            toBlue(", hasPayload="), fshow(hasPayload)
        );
    endrule

    rule genPacketHeader;
        let pipelineEntryIn = genPacketHeaderPipelineQ.first;
        let wqe = pipelineEntryIn.wqe;
        let hasPayload = pipelineEntryIn.hasPayload;

        // if the message doesn't have payload, then it is always a "Only" request
        Bool isFirst = wqe.isFirst;
        Bool isLast = wqe.isLast;

        let psn = psnReg;

        let ackReq = containWorkReqFlag(wqe.flags, IBV_SEND_SIGNALED);
        let solicited = containWorkReqFlag(wqe.flags, IBV_SEND_SOLICITED);

        let padCnt = 0;  // since payload is already aligned to remote address, no padding is needed.

        let remoteAddr = dontCareValue;
        let dlen = dontCareValue;

        UdpLength udpPayloadLen = fromInteger(valueOf(RDMA_FIXED_HEADER_BYTE_NUM));

        if (hasPayload) begin

            let packetInfo = wqeToPacketChunker.responsePipeOut.first;
            wqeToPacketChunker.responsePipeOut.deq;
        
            isFirst = isFirst && packetInfo.isFirst;
            isLast = isLast && packetInfo.isLast;
            
            if (packetInfo.isLast) begin
                genPacketHeaderPipelineQ.deq;
            end

            let packetToBeatChunkReq = AddressChunkReq{
                startAddr: packetInfo.startAddr,
                len: packetInfo.len,
                chunk: dontCareValue
            };
            packetToBeatChunkMetaCalc.requestPipeIn.enq(packetToBeatChunkReq);

            if (packetInfo.isFirst) begin
                psn = wqe.psn;
                psnReg <= psn + 1;
            end

            remoteAddr = packetInfo.startAddr;
            dlen = isFirst ? wqe.totalLen : packetInfo.len;

            ByteIndexInBeat paddingByteNumForRemoteAddressAlign = truncate(remoteAddr);

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


    
        let bthMaybe <- genRdmaBTH(wqe, isFirst, isLast, solicited, psn, padCnt, ackReq, remoteAddr, dlen);
        let extendHeaderBufferMaybe <- genRdmaExtendHeader(wqe, isFirst, isLast, remoteAddr, dlen);

        if (bthMaybe matches tagged Valid .bth &&& extendHeaderBufferMaybe matches tagged Valid .extendHeaderBuffer) begin
            let rdmaPacketMeta = RdmaSendPacketMeta {
                header: RdmaBthAndExtendHeader{
                    bth: bth,
                    rdmaExtendHeaderBuf: extendHeaderBuffer
                },
                hasPayload: pipelineEntryIn.hasPayload
            };
            ethernetPacketGen.rdmaPacketMetaPipeIn.enq(rdmaPacketMeta);
        end
        else begin
            immFail(
                "bthMaybe and extendHeaderBufferMaybe should not be Invalid", 
                $format("bthMaybe=", fshow(bthMaybe), ", extendHeaderBufferMaybe=", fshow(extendHeaderBufferMaybe))
            );
        end

        

        let macIpUdpMeta = ThinMacIpUdpMetaDataForSend{
            dstMacAddr: wqe.macAddr,
            ipDscp: 0,
            ipEcn: 0,
            dstIpAddr: wqe.dqpIP,
            srcPort: truncate(wqe.sqpn),
            dstPort: fromInteger(valueOf(UDP_PORT_RDMA)),
            udpPayloadLen: udpPayloadLen,
            ethType: fromInteger(valueOf(ETH_TYPE_IP))
        };
        ethernetPacketGen.macIpUdpMetaPipeIn.enq(macIpUdpMeta);


        $display(
            "time=%0t:", $time, toGreen(" mkPacketGen genPacketHeader"),
            toBlue(", bthMaybe="), fshow(bthMaybe),
            toBlue(", extendHeaderBufferMaybe="), fshow(extendHeaderBufferMaybe)
        );


        // let pipelineEntryOut = GenEthernetPacketPipelineEntry{
        //     wqe: pipelineEntryIn.wqe,
        //     hasPayload: pipelineEntryIn.hasPayload
        // };
        // genEthernetPacketReqPipelineQ.enq(pipelineEntryOut);
    endrule

    rule reSplitStream;
        // since the output of payloadGen is a single very long stream, we need to split it into
        // multi sub-stream according to packet boundary.

        let beatInfo = packetToBeatChunker.responsePipeOut.first;
        packetToBeatChunker.responsePipeOut.deq;

        let ds = payloadStreamShifter.streamPipeOut.first;
        payloadStreamShifter.streamPipeOut.deq;

        if (ds.isFirst) begin
            immAssert(
                beatInfo.isFirst,
                "when ds (the long datastream) is isFirst, the sub-packet should also be isFirst",
                $format("")
            );
        end

        if (ds.isLast) begin
            immAssert(
                beatInfo.isLast,
                "when ds (the long datastream) is isLast, the sub-packet should also be isLast",
                $format("")
            );
        end

        immAssert(
            truncate(beatInfo.len) == ds.byteNum,
            "the shifted payload stream's beat length should match the calculated beat length",
            $format("beatInfo=", fshow(beatInfo), ", ds=", fshow(ds))
        );

        ds.isFirst = beatInfo.isFirst;
        ds.isLast = beatInfo.isLast;

        perPacketPayloadDataStreamQ.enq(ds);


        $display(
            "time=%0t:", $time, toGreen(" mkPacketGen reSplitStream"),
            toBlue(", ds="), fshow(ds)
        );
    endrule


    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
        ethernetPacketGen.setLocalNetworkSettings(networkSettings);
    endmethod

    interface wqePipeIn = toPipeIn(wqePipeInQ);
    interface packetPipeOut = ethernetPacketGen.ethernetPacketPipeOut;
endmodule