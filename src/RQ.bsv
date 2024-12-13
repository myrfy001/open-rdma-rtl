import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import Clocks :: *;


import ConnectableF :: *;
import RdmaUtils :: *;
import PrimUtils :: *;

import BasicDataTypes :: *;
import Settings :: *;
import RdmaHeaders :: *;
import RdmaHeaders :: *;
import NapWrapper :: *;
import AddressChunker :: *;
import EthernetTypes :: *;
import PayloadGenAndCon :: *;
import EthernetFrameIO :: *;
import StreamShifter :: *;
import QPContext :: *;
import PacketGenAndParse :: *;

typedef Bit#(TAdd#(1, SizeOf#(Length))) TruncatedAddrForMrBoundCheck;

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    Bool isFirstPacket;
} CheckQpcAndMrTablePipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    Bool isMrLowerAddrBoundOk;
    PktFragNum zerobasedExpectedPayloadBeatNum;
    Length packetLen;
    TruncatedAddrForMrBoundCheck deltaLen;
} CheckMrTableStep2PipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    Bool isMrLowerAddrBoundOk;
    PktFragNum zerobasedExpectedPayloadBeatNum;
    Length packetLen;
    TruncatedAddrForMrBoundCheck deltaLen;
} CheckMrTableStep3PipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    PktFragNum zerobasedExpectedPayloadBeatNum;
    Length packetLen;
} IssuePayloadConReqOrDiscardPipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isZeroPayload;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    PktFragNum zerobasedExpectedPayloadBeatNum;
    Length packetLen;
} HandleConRespPipelineEntry deriving(Bits, FShow);





interface RQ;
    interface Client#(ReadReqQPC, Maybe#(EntryQPC)) qpcQueryClt; 
    interface Client#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryClt;

    interface PipeIn#(EthernetNapBeatEntry) ethernetFramePipeIn;
    interface PipeOut#(DataStream) otherRawPacketPipeOut;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 

    interface PipeOut#(PayloadConReq) payloadConReqPipeOut;
    interface PipeOut#(DataStream) payloadConStreamPipeOut;
    interface PipeIn#(Bool) payloadConRespPipeIn;
endinterface

// FIXME: handle illegal packet length. don't trust length or other meta extracted from header. 
//        only trust what you have really received.
//        And for packet that isn't normal, make sure all related queues are dequeued. otherwise deadlock.
(* synthesize *)
module mkRQ#(
        Clock clkEthNap, 
        Reset rstEthNap,
        Clock clkQpcMrPgtSrv, 
        Reset rstQpcMrPgtSrv
    )(RQ);

    PacketParse packetParser <- mkPacketParse(clocked_by clkEthNap, reset_by rstEthNap);
    FIFOF#(DataStream) payloadStorage <- mkSizedFIFOF(valueOf(MAX_PAYLOAD_STORAGE_CAPACITY_PER_RQ), clocked_by clkEthNap, reset_by rstEthNap);
    SyncFIFOIfc#(ThinMacIpUdpMetaDataForRecv) peerMetaStorage <- mkSyncFIFOToCC(valueOf(MAX_PEER_META_STORAGE_CAPACITY_PER_RQ), clkEthNap, rstEthNap);
    mkConnection(packetParser.rdmaPayloadPipeOut, toPipeIn(payloadStorage), clocked_by clkEthNap, reset_by rstEthNap);
    mkConnection(packetParser.rdmaMacIpUdpMetaPipeOut, toPipeInSync(peerMetaStorage), clocked_by clkEthNap, reset_by rstEthNap);

    QueuedClient#(ReadReqQPC, Maybe#(EntryQPC)) qpcQueryCltInst <- mkSyncQueuedClient("qpcQueryCltInst", clkQpcMrPgtSrv, rstQpcMrPgtSrv);
    QueuedClient#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryCltInst <- mkSyncQueuedClient("mrTableQueryCltInst", clkQpcMrPgtSrv, rstQpcMrPgtSrv);

    SyncFIFOIfc#(PayloadConReq) conReqPipeOutQ <- mkSyncFIFOFromCC(valueOf(QUEUE_DEPTH_4), clkEthNap);
    SyncFIFOIfc#(Bool) conRespPipeInQ <- mkSyncFIFOToCC(valueOf(QUEUE_DEPTH_4), clkEthNap, rstEthNap);

    // invalid request payload filter related
    SyncFIFOIfc#(Bool) filterCmdSyncQ <-  mkSyncFIFOFromCC(valueOf(QUEUE_DEPTH_4), clkEthNap);
    FIFOF#(DataStream) filteredDataStreamForConsumeQ <- mkFIFOF(clocked_by clkEthNap, reset_by rstEthNap);

    // Clock domain convert queues
    SyncFIFOIfc#(RdmaRecvPacketMeta) rdmaPacketMetaPipeOutSyncQ <- mkSyncFIFOToCC(valueOf(QUEUE_DEPTH_4), clkEthNap, rstEthNap);
    SyncFIFOIfc#(RdmaRecvPacketTailMeta) rdmaPacketTailMetaPipeOutSyncQ <- mkSyncFIFOToCC(valueOf(QUEUE_DEPTH_4), clkEthNap, rstEthNap);

    mkConnection(packetParser.rdmaPacketMetaPipeOut, toPipeInSync(rdmaPacketMetaPipeOutSyncQ), clocked_by clkEthNap, reset_by rstEthNap);
    mkConnection(packetParser.rdmaPacketTailMetaPipeOut, toPipeInSync(rdmaPacketTailMetaPipeOutSyncQ), clocked_by clkEthNap, reset_by rstEthNap);

    // Pipeline Queues
    FIFOF#(CheckQpcAndMrTablePipelineEntry) checkQpcAndMrTablePipeQ <- mkSizedFIFOF(4);
    FIFOF#(CheckMrTableStep2PipelineEntry) checkMrTableStep2PipeQ <- mkSizedFIFOF(2);
    FIFOF#(CheckMrTableStep3PipelineEntry) checkMrTableStep3PipeQ <- mkSizedFIFOF(2);
    FIFOF#(IssuePayloadConReqOrDiscardPipelineEntry) issuePayloadConReqOrDiscardPipeQ <- mkSizedFIFOF(2);
    // For a 4096 PMTU packet followed by all packet that without payload. When consuming a big packet, all small packets has to waiting in the queue
    FIFOF#(HandleConRespPipelineEntry) handleConRespPipeQ <- mkSizedFIFOF(valueOf(TDiv#(TDiv#(MAX_PMTU, DATA_BUS_BYTE_WIDTH), RDMA_PACKET_HEADER_BETA_CNT)));

    rule printDebugInfo;
        if (!checkQpcAndMrTablePipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ checkQpcAndMrTablePipeQ");
        if (!checkMrTableStep2PipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ checkMrTableStep2PipeQ");
        if (!checkMrTableStep3PipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ checkMrTableStep3PipeQ");
        if (!issuePayloadConReqOrDiscardPipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ issuePayloadConReqOrDiscardPipeQ");
        if (!handleConRespPipeQ.notFull) $display("time=%0t, ", $time, "FullQueue: mkRQ handleConRespPipeQ");
    endrule


    rule sendQpcQueryReqAndSomeSimpleParse;
        let rdmaPacketMeta = rdmaPacketMetaPipeOutSyncQ.first;
        rdmaPacketMetaPipeOutSyncQ.deq;
        let bth = rdmaPacketMeta.header.bth;
        let reth = extractPriRETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans);

        let qpcQueryResp = ReadReqQPC{
            qpn: bth.dqpn
        };
        qpcQueryCltInst.putReq(qpcQueryResp);


        let isRespNeedDMAWrite  = rdmaRespNeedDmaWrite(bth.opcode);
        let isReqNeedDMAWrite   = rdmaReqNeedDmaWrite(bth.opcode);
        let isZeroPayload       = isZeroR(reth.dlen);
        let isNeedQueryMrTable  = isRespNeedDMAWrite || isReqNeedDMAWrite;
        let isFirstPacket       = isFirstRdmaOpCode(bth.opcode);


        if (isNeedQueryMrTable) begin
            let mrTableQueryReq = MrTableQueryReq{
                idx: rkey2IndexMR(reth.rkey)
            };
            mrTableQueryCltInst.putReq(mrTableQueryReq);
        end

        let pipelineEntryOut = CheckQpcAndMrTablePipelineEntry{
            rdmaPacketMeta: rdmaPacketMeta,
            packetStatus: RdmaRecvPacketStatusNormal,
            isNeedQueryMrTable: isNeedQueryMrTable,
            isZeroPayload: isZeroPayload,
            isFirstPacket: isFirstPacket
        };
        checkQpcAndMrTablePipeQ.enq(pipelineEntryOut);

        $display(
            "time=%0t:", $time, toGreen(" mkRQ sendQpcQueryReqAndSomeSimpleParse"),
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut)
        );
    endrule

    rule checkQpcAndMrTable;
        let pipelineEntryIn = checkQpcAndMrTablePipeQ.first;
        checkQpcAndMrTablePipeQ.deq;

        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let bth = rdmaPacketMeta.header.bth;
        let reth = extractPriRETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans);
        let packetStatus = pipelineEntryIn.packetStatus;
        let isNeedQueryMrTable = pipelineEntryIn.isNeedQueryMrTable;
        let isFirstPacket = pipelineEntryIn.isFirstPacket;
        let isZeroPayload = pipelineEntryIn.isZeroPayload;

        let isSendReq            = isSendReqRdmaOpCode(bth.opcode);
        let isWriteReq           = isWriteReqRdmaOpCode(bth.opcode);
        let isReadReq            = isReadReqRdmaOpCode(bth.opcode);
        let isAtomicReq          = isAtomicReqRdmaOpCode(bth.opcode);
        let isReadResp           = isReadRespRdmaOpCode(bth.opcode);
        
        Bool                            isQpKeyCheckPass            = False;
        Bool                            isQpAccCheckPass            = False; 
        Bool                            isMrKeyCheckPass            = False;
        Bool                            isMrAccCheckPass            = False; 
        Bool                            isMrLowerAddrBoundOk        = False;
        MemRegionTableEntry             mrEntryUnwraped             = ?;
        PktFragNum                      zerobasedExpectedPayloadBeatNum      = ?;
        Length                          packetLen                   = ?;
        TruncatedAddrForMrBoundCheck    deltaLen                    = ?;

        let qpcMaybe <- qpcQueryCltInst.getResp;
        if (qpcMaybe matches tagged Valid .qpc) begin
            if (getKeyQP(bth.dqpn) == qpc.qpnKeyPart) begin
                isQpKeyCheckPass = True;
            end

            if (isNeedQueryMrTable) begin
                case ({ pack(isSendReq || isWriteReq), pack(isReadReq), pack(isAtomicReq), pack(isReadResp) })
                    4'b1000: begin
                        isQpAccCheckPass = containAccessTypeFlag(qpc.rqAccessFlags, IBV_ACCESS_REMOTE_WRITE);
                    end
                    4'b0100: begin
                        isQpAccCheckPass = containAccessTypeFlag(qpc.rqAccessFlags, IBV_ACCESS_REMOTE_READ);
                    end
                    4'b0010: begin
                        isQpAccCheckPass = containAccessTypeFlag(qpc.rqAccessFlags, IBV_ACCESS_REMOTE_ATOMIC);
                    end
                    4'b0001: begin
                        isQpAccCheckPass = containAccessTypeFlag(qpc.rqAccessFlags, IBV_ACCESS_LOCAL_WRITE);
                    end
                    default: begin
                        immFail(
                            "unreachible case @ mkReqHandleRQ",
                            $format(
                                "isSendReq=", fshow(isSendReq),
                                ", isWriteReq=", fshow(isWriteReq),
                                ", isReadReq=", fshow(isReadReq),
                                ", isAtomicReq=", fshow(isAtomicReq),
                                ", bth=", fshow(bth)
                            )
                        );
                    end
                endcase
            end
            else begin
                isQpAccCheckPass = True;
            end

            // Note: For "Only" type packet the reth.len is also the packet len, only the "First" type packet has to calculate.
            let {_, startAddrOffsetAlignedToPmtu} = alignAddrByPMTU(reth.va, qpc.pmtu);
            Length calculatedFirstPacketLen = getChunkSizeForPMTU(qpc.pmtu) - truncate(startAddrOffsetAlignedToPmtu);
            packetLen = isFirstPacket ? calculatedFirstPacketLen : reth.dlen;

            ADDR rethEndAddrForBeatCountCalc = reth.va + zeroExtend(packetLen) - 1;
            Length dividedStartAddr = truncate(reth.va >> valueOf(DATA_BUS_BYTE_NUM_WIDTH));
            Length dividedEndAddr = truncate(rethEndAddrForBeatCountCalc >> valueOf(DATA_BUS_BYTE_NUM_WIDTH));
            zerobasedExpectedPayloadBeatNum = truncate(dividedEndAddr - dividedStartAddr);

            if (isNeedQueryMrTable) begin
                let mrEntryMaybe <- mrTableQueryCltInst.getResp;
                if (mrEntryMaybe matches tagged Valid .mrEntry) begin
                    mrEntryUnwraped = mrEntry;
                    if (rkey2KeyPartMR(reth.rkey) == mrEntry.keyPart) begin
                        isMrKeyCheckPass = True;
                    end

                    case ({pack(isSendReq), pack(isReadReq), pack(isWriteReq || isReadResp), pack(isAtomicReq)})
                        4'b1000: begin  // Send
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_LOCAL_WRITE);
                        end
                        4'b0100: begin  // Read
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_REMOTE_READ);
                        end
                        4'b0010: begin  // Write
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_REMOTE_WRITE);
                        end
                        4'b0001: begin  // Atomic
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_REMOTE_ATOMIC);
                        end
                        default: begin
                            isMrAccCheckPass = containAccessTypeFlag(mrEntry.accFlags, IBV_ACCESS_LOCAL_WRITE);
                        end
                    endcase

                    isMrLowerAddrBoundOk = reth.va >= mrEntry.baseVA;
                    
                    // The MR boundary check is a little trick. The straightforward way to check is to compare
                    //     (req.addr + req.len <= mr.startAddr + mr.len)
                    //
                    // But this way has many issues, first, we don't want to do many 64-bit add and compare;
                    // second, this can't handle overflow, unless we use a 65 bit to do the math.
                    // So, we use substruct instead of addition, we only care the the requests memory access span.
                    // The ( req.addr + req.len ) is the access upper memory boundary
                    // The ( req.addr + req.len - mr.startAddr ) is the span between MR's start address to  
                    // access request's upper boundary. ** The length of this span must not exceed MR's length **.
                    // 
                    // On the other hand, Since the access length is 32 bits, and to handle overflow, 
                    // we only need to care 33 bits. Like handling a ringbuf's address, we can think those 
                    // add and sub math is moving a point on a circle, and the substract result is the arc 
                    // on this circle.
                    // 
                    // Last, for the queation ( req.addr + req.len - mr.startAddr ),
                    // req.len is calucated in this beat, so it can't meet timing. So we have to change the
                    // operation order to ( (req.addr - mr.startAddr) + req.len ).
                    // In this beat, only calculate (req.addr - mr.startAddr)
                    TruncatedAddrForMrBoundCheck shortMrStartVa = truncate(mrEntry.baseVA);
                    TruncatedAddrForMrBoundCheck shortReqStartVa = truncate(reth.va);
                    deltaLen = shortReqStartVa - shortMrStartVa;
                end
            end
        end

        if (!isQpKeyCheckPass) begin
            packetStatus = RdmaRecvPacketStatusInvalidQpContext;
        end
        else if (!isQpAccCheckPass) begin
            packetStatus = RdmaRecvPacketStatusInvalidQpAccessFlag;
        end
        else if (!isMrKeyCheckPass) begin
            packetStatus = RdmaRecvPacketStatusInvalidMrKey;
        end
        else if (!isMrAccCheckPass) begin
            packetStatus = RdmaRecvPacketStatusInvalidMrAccessFlag;
        end

        let pipelineEntryOut = CheckMrTableStep2PipelineEntry{
            rdmaPacketMeta          : rdmaPacketMeta,
            packetStatus            : packetStatus,
            isNeedQueryMrTable      : isNeedQueryMrTable,
            isZeroPayload           : isZeroPayload,
            mrEntry                 : mrEntryUnwraped,
            qpc                     : unwrapMaybe(qpcMaybe),
            isMrLowerAddrBoundOk    : isMrLowerAddrBoundOk,
            zerobasedExpectedPayloadBeatNum  : zerobasedExpectedPayloadBeatNum,
            packetLen               : packetLen,
            deltaLen                : deltaLen
        };
        checkMrTableStep2PipeQ.enq(pipelineEntryOut);

        $display(
            "time=%0t:", $time, toGreen(" mkRQ checkQpcAndMrTable"),
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut)
        );
    endrule
    

    rule checkMrTableStep2;
        let pipelineEntryIn = checkMrTableStep2PipeQ.first;
        checkMrTableStep2PipeQ.deq;

        let deltaLen = pipelineEntryIn.deltaLen;
        let packetLen = pipelineEntryIn.packetLen;

        deltaLen = deltaLen + zeroExtend(packetLen);

        let pipelineEntryOut = CheckMrTableStep3PipelineEntry{
            rdmaPacketMeta          : pipelineEntryIn.rdmaPacketMeta,
            packetStatus            : pipelineEntryIn.packetStatus,
            isNeedQueryMrTable      : pipelineEntryIn.isNeedQueryMrTable,
            isZeroPayload           : pipelineEntryIn.isZeroPayload,
            mrEntry                 : pipelineEntryIn.mrEntry,
            qpc                     : pipelineEntryIn.qpc,
            isMrLowerAddrBoundOk    : pipelineEntryIn.isMrLowerAddrBoundOk,
            zerobasedExpectedPayloadBeatNum  : pipelineEntryIn.zerobasedExpectedPayloadBeatNum,
            packetLen               : pipelineEntryIn.packetLen,
            deltaLen                : deltaLen
        };
        checkMrTableStep3PipeQ.enq(pipelineEntryOut);
        $display(
            "time=%0t:", $time, toGreen(" mkRQ checkMrTableStep2"),
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut)
        );
    endrule

    rule checkMrTableStep3;

        let pipelineEntryIn = checkMrTableStep3PipeQ.first;
        checkMrTableStep3PipeQ.deq;

        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let packetStatus = pipelineEntryIn.packetStatus;
        let zerobasedExpectedPayloadBeatNum = pipelineEntryIn.zerobasedExpectedPayloadBeatNum;
        let isNeedQueryMrTable = pipelineEntryIn.isNeedQueryMrTable;
        let deltaLen = pipelineEntryIn.deltaLen;
        let packetLen = pipelineEntryIn.packetLen;
        let mrEntry = pipelineEntryIn.mrEntry;

        Bool isMrUpperAddrBoundOk = deltaLen <= zeroExtend(mrEntry.len);

        Bool isAccessRangeCheckPass = False;
        Bool isPacketBeatCountCheckPass = False;

        if (isRecvPacketStatusNormal(packetStatus)) begin
            if (rdmaPacketMeta.hasPayload) begin
                let packetTailMeta = rdmaPacketTailMetaPipeOutSyncQ.first;
                rdmaPacketTailMetaPipeOutSyncQ.deq;
                if (packetTailMeta.beatCnt - 1 == zerobasedExpectedPayloadBeatNum) begin
                    isPacketBeatCountCheckPass = True;
                end
            end
            else begin
                isPacketBeatCountCheckPass = True;
            end

            if (isNeedQueryMrTable) begin
                // if we reach here, then mrEntry must be a valid value, so we can safely use isMrUpperAddrBoundOk.
                isAccessRangeCheckPass = pipelineEntryIn.isMrLowerAddrBoundOk && isMrUpperAddrBoundOk;
            end


            if (!isAccessRangeCheckPass) begin
                packetStatus = RdmaRecvPacketStatusMemAccessOutOfBound;
            end
            else if (!isPacketBeatCountCheckPass) begin
                packetStatus = RdmaRecvPacketStatusCorruptPktLength;
            end
        end


        let pipelineEntryOut = IssuePayloadConReqOrDiscardPipelineEntry{
            rdmaPacketMeta          : rdmaPacketMeta,
            packetStatus            : packetStatus,
            isNeedQueryMrTable      : pipelineEntryIn.isNeedQueryMrTable,
            isZeroPayload           : pipelineEntryIn.isZeroPayload,
            mrEntry                 : pipelineEntryIn.mrEntry,
            qpc                     : pipelineEntryIn.qpc,
            zerobasedExpectedPayloadBeatNum  : pipelineEntryIn.zerobasedExpectedPayloadBeatNum,
            packetLen               : pipelineEntryIn.packetLen
        };
        issuePayloadConReqOrDiscardPipeQ.enq(pipelineEntryOut);
        $display(
            "time=%0t:", $time, toGreen(" mkRQ checkMrTableStep3"),
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut)
        );
    endrule



    rule issuePayloadConReqOrDiscard;
        let pipelineEntryIn = issuePayloadConReqOrDiscardPipeQ.first;
        issuePayloadConReqOrDiscardPipeQ.deq;
        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let packetStatus = pipelineEntryIn.packetStatus;
        let bth = rdmaPacketMeta.header.bth;
        let reth = extractPriRETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans);
        let mrEntry = pipelineEntryIn.mrEntry;

        Bool discardDebugFlag = True;
        if (rdmaPacketMeta.hasPayload) begin
            let isDiscard = !isRecvPacketStatusNormal(packetStatus);
            filterCmdSyncQ.enq(isDiscard);
            if (!isDiscard) begin
                let payloadConReq = PayloadConReq{
                    addr: reth.va,
                    len: pipelineEntryIn.packetLen,
                    baseVA: mrEntry.baseVA,    
                    pgtOffset: mrEntry.pgtOffset 
                };
                conReqPipeOutQ.enq(payloadConReq);
                discardDebugFlag = False;
            end
        end
        else begin
            discardDebugFlag = False;
        end

        let pipelineEntryOut = HandleConRespPipelineEntry{
            rdmaPacketMeta          : pipelineEntryIn.rdmaPacketMeta,
            packetStatus            : pipelineEntryIn.packetStatus,
            isNeedQueryMrTable      : pipelineEntryIn.isNeedQueryMrTable,
            isZeroPayload           : pipelineEntryIn.isZeroPayload,
            mrEntry                 : pipelineEntryIn.mrEntry,
            qpc                     : pipelineEntryIn.qpc,
            zerobasedExpectedPayloadBeatNum  : pipelineEntryIn.zerobasedExpectedPayloadBeatNum,
            packetLen               : pipelineEntryIn.packetLen
        };
        handleConRespPipeQ.enq(pipelineEntryOut);
        $display(
            "time=%0t:", $time, toGreen(" mkRQ issuePayloadConReqOrDiscard"),
            discardDebugFlag ? toRed(" Discard!") : " keeped",
            toBlue(", pipelineEntryOut="), fshow(pipelineEntryOut)
        );
    endrule

    rule handleConResp;
        let pipelineEntryIn = handleConRespPipeQ.first;
        handleConRespPipeQ.deq;
        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let packetStatus = pipelineEntryIn.packetStatus;

        if (rdmaPacketMeta.hasPayload) begin
            let isDiscard = !isRecvPacketStatusNormal(packetStatus);
            if (!isDiscard) begin
                let resp = conRespPipeInQ.first;
                conRespPipeInQ.deq;
                peerMetaStorage.deq;
                $display("payload con resp = ", fshow(resp));
            end
        end

        $display(
            "time=%0t:", $time, toGreen(" mkRQ handleConResp")
        );
    endrule


    rule filterDiscardedPayloadStream;
        let isDiscard = filterCmdSyncQ.first;
        let ds = payloadStorage.first;
        payloadStorage.deq;

        if (!isDiscard) begin
            filteredDataStreamForConsumeQ.enq(ds);
        end

        if (ds.isLast) begin
            filterCmdSyncQ.deq;
        end

        $display(
            "time=%0t:", $time, toGreen(" mkRQ filterDiscardedPayloadStream"),
            isDiscard ? toRed(" Discard!") : " keeped",
            toBlue(", ds="), fshow(ds)
        );
    endrule

    interface qpcQueryClt = qpcQueryCltInst.clt;
    interface mrTableQueryClt = mrTableQueryCltInst.clt;

    interface ethernetFramePipeIn = packetParser.ethernetFramePipeIn;
    interface otherRawPacketPipeOut = packetParser.otherRawPacketPipeOut;

    interface payloadConReqPipeOut      = toPipeOutSync(conReqPipeOutQ);
    interface payloadConStreamPipeOut   = toPipeOut(filteredDataStreamForConsumeQ);
    interface payloadConRespPipeIn      = toPipeInSync(conRespPipeInQ);

    method setLocalNetworkSettings = packetParser.setLocalNetworkSettings; 

    
endmodule