import Connectable :: *;
import FIFOF :: *;
import ClientServer :: *;
import Clocks :: *;


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
import QPContext :: *;
import PacketGenAndParse :: *;

typedef Bit#(TAdd#(1, SizeOf#(Length))) TruncatedAddrForMrBoundCheck;

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    Bool isFirstPacket;
} CheckQpcAndMrTablePipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    Bool isMrLowerAddrBoundOk;
    PktFragNum expectedPayloadBeatNum;
    Length packetLen;
    TruncatedAddrForMrBoundCheck deltaLen;
} CheckMrTableStep2PipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    Bool isMrLowerAddrBoundOk;
    PktFragNum expectedPayloadBeatNum;
    Length packetLen;
    TruncatedAddrForMrBoundCheck deltaLen;
} CheckMrTableStep3PipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    PktFragNum expectedPayloadBeatNum;
    Length packetLen;
} IssuePayloadGenReqOrDiscardPipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    PktFragNum expectedPayloadBeatNum;
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

    SyncFIFOIfc#(PayloadConReq) conReqPipeOutQ <- mkSyncFIFOFromCC(valueOf(QUEUE_DEPTH_2), clkEthNap);
    SyncFIFOIfc#(Bool) conRespPipeInQ <- mkSyncFIFOToCC(valueOf(QUEUE_DEPTH_2), clkEthNap, rstEthNap);

    // invalid request payload filter related
    SyncFIFOIfc#(Bool) filterCmdSyncQ <-  mkSyncFIFOFromCC(valueOf(QUEUE_DEPTH_2), clkEthNap);
    FIFOF#(DataStream) filteredDataStreamForConsumeQ <- mkFIFOF(clocked_by clkEthNap, reset_by rstEthNap);

    // Clock domain convert queues
    SyncFIFOIfc#(RdmaRecvPacketMeta) rdmaPacketMetaPipeOutSyncQ <- mkSyncFIFOToCC(valueOf(QUEUE_DEPTH_2), clkEthNap, rstEthNap);
    SyncFIFOIfc#(RdmaRecvPacketTailMeta) rdmaPacketTailMetaPipeOutSyncQ <- mkSyncFIFOToCC(valueOf(QUEUE_DEPTH_2), clkEthNap, rstEthNap);

    mkConnection(packetParser.rdmaPacketMetaPipeOut, toPipeInSync(rdmaPacketMetaPipeOutSyncQ), clocked_by clkEthNap, reset_by rstEthNap);
    mkConnection(packetParser.rdmaPacketTailMetaPipeOut, toPipeInSync(rdmaPacketTailMetaPipeOutSyncQ), clocked_by clkEthNap, reset_by rstEthNap);

    // Pipeline Queues
    FIFOF#(CheckQpcAndMrTablePipelineEntry) checkQpcAndMrTablePipeQ <- mkFIFOF;
    FIFOF#(CheckMrTableStep2PipelineEntry) checkMrTableStep2PipeQ <- mkFIFOF;
    FIFOF#(CheckMrTableStep3PipelineEntry) checkMrTableStep3PipeQ <- mkFIFOF;
    FIFOF#(IssuePayloadGenReqOrDiscardPipelineEntry) issuePayloadGenReqOrDiscardPipeQ <- mkFIFOF;
    FIFOF#(HandleConRespPipelineEntry) handleConRespPipeQ <- mkFIFOF;

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
            isFirstPacket: isFirstPacket
        };
        checkQpcAndMrTablePipeQ.enq(pipelineEntryOut);
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
        PktFragNum                      expectedPayloadBeatNum      = ?;
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
            expectedPayloadBeatNum = truncate(dividedEndAddr - dividedStartAddr);

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
            mrEntry                 : mrEntryUnwraped,
            qpc                     : unwrapMaybe(qpcMaybe),
            isMrLowerAddrBoundOk    : isMrLowerAddrBoundOk,
            expectedPayloadBeatNum  : expectedPayloadBeatNum,
            packetLen               : packetLen,
            deltaLen                : deltaLen
        };
        checkMrTableStep2PipeQ.enq(pipelineEntryOut);
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
            mrEntry                 : pipelineEntryIn.mrEntry,
            qpc                     : pipelineEntryIn.qpc,
            isMrLowerAddrBoundOk    : pipelineEntryIn.isMrLowerAddrBoundOk,
            expectedPayloadBeatNum  : pipelineEntryIn.expectedPayloadBeatNum,
            packetLen               : pipelineEntryIn.packetLen,
            deltaLen                : deltaLen
        };
        checkMrTableStep3PipeQ.enq(pipelineEntryOut);
    endrule

    rule checkMrTableStep3;

        let pipelineEntryIn = checkMrTableStep3PipeQ.first;
        checkMrTableStep3PipeQ.deq;

        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let packetStatus = pipelineEntryIn.packetStatus;
        let expectedPayloadBeatNum = pipelineEntryIn.expectedPayloadBeatNum;
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

                if (packetTailMeta.beatCnt == expectedPayloadBeatNum) begin
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


        let pipelineEntryOut = IssuePayloadGenReqOrDiscardPipelineEntry{
            rdmaPacketMeta          : rdmaPacketMeta,
            packetStatus            : packetStatus,
            isNeedQueryMrTable      : pipelineEntryIn.isNeedQueryMrTable,
            mrEntry                 : pipelineEntryIn.mrEntry,
            qpc                     : pipelineEntryIn.qpc,
            expectedPayloadBeatNum  : pipelineEntryIn.expectedPayloadBeatNum,
            packetLen               : pipelineEntryIn.packetLen
        };
        issuePayloadGenReqOrDiscardPipeQ.enq(pipelineEntryOut);
    endrule



    rule issuePayloadGenReqOrDiscard;
        let pipelineEntryIn = issuePayloadGenReqOrDiscardPipeQ.first;
        issuePayloadGenReqOrDiscardPipeQ.deq;
        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let packetStatus = pipelineEntryIn.packetStatus;
        let bth = rdmaPacketMeta.header.bth;
        let reth = extractPriRETH(rdmaPacketMeta.header.rdmaExtendHeaderBuf, bth.trans);
        let mrEntry = pipelineEntryIn.mrEntry;

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
            end
        end

        let pipelineEntryOut = HandleConRespPipelineEntry{
            rdmaPacketMeta          : pipelineEntryIn.rdmaPacketMeta,
            packetStatus            : pipelineEntryIn.packetStatus,
            isNeedQueryMrTable      : pipelineEntryIn.isNeedQueryMrTable,
            mrEntry                 : pipelineEntryIn.mrEntry,
            qpc                     : pipelineEntryIn.qpc,
            expectedPayloadBeatNum  : pipelineEntryIn.expectedPayloadBeatNum,
            packetLen               : pipelineEntryIn.packetLen
        };
        handleConRespPipeQ.enq(pipelineEntryOut);
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