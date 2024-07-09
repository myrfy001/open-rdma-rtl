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
import QPContext :: *;
import PacketGenAndParse :: *;


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
    ADDR mrUpperAddrBound;
    ADDR reqUpperAddrBound;
    PktFragNum expectedPayloadBeatNum;
    Length packetLen;
} CheckMrTableStep2PipelineEntry deriving(Bits, FShow);

typedef struct {
    RdmaRecvPacketMeta rdmaPacketMeta;
    RdmaRecvPacketStatus packetStatus;
    Bool isNeedQueryMrTable;
    MemRegionTableEntry mrEntry;
    EntryQPC qpc;
    Bool isMrLowerAddrBoundOk;
    ADDR mrUpperAddrBound;
    ADDR reqUpperAddrBound;
    PktFragNum expectedPayloadBeatNum;
    Length packetLen;
} IssuePayloadGenReqOrDiscardPipelineEntry deriving(Bits, FShow);

interface RQ;
    interface Client#(ReadReqQPC, Maybe#(EntryQPC)) qpcQueryClt; 

    interface PipeIn#(EthernetNapBeatEntry) ethernetFramePipeIn;
    interface PipeOut#(DataStream) otherRawPacketPipeOut;
    method Action setLocalNetworkSettings(LocalNetworkSettings networkSettings); 
endinterface


module mkRQ#(PayloadGenAndCon payloadGenAndCon)(RQ);
    PacketParse packetParser <- mkPacketParse;

    FIFOF#(DataStream) payloadStorage <- mkSizedFIFOF(valueOf(MAX_PAYLOAD_STORAGE_CAPACITY_PER_RQ));
    FIFOF#(ThinMacIpUdpMetaDataForRecv) peerMetaStorage <- mkSizedFIFOF(valueOf(MAX_PEER_META_STORAGE_CAPACITY_PER_RQ));
    mkConnection(packetParser.rdmaPayloadPipeOut, toPipeIn(payloadStorage));
    mkConnection(packetParser.rdmaMacIpUdpMetaPipeOut, toPipeIn(peerMetaStorage));

    QueuedClient#(ReadReqQPC, Maybe#(EntryQPC)) qpcQueryCltInst <- mkQueuedClient("qpcQueryCltInst");
    QueuedClient#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) mrTableQueryCltInst <- mkQueuedClient("mrTableQueryCltInst");

    // invalid request payload filter related
    FIFOF#(Bool) filterCmdQ <-  mkFIFOF;
    FIFOF#(DataStream) filteredDataStreamForConsumeQ <- mkFIFOF;

    // Pipeline Queues
    FIFOF#(CheckQpcAndMrTablePipelineEntry) checkQpcAndMrTablePipeQ <- mkFIFOF;
    FIFOF#(CheckMrTableStep2PipelineEntry) checkMrTableStep2PipeQ <- mkFIFOF;
    FIFOF#(IssuePayloadGenReqOrDiscardPipelineEntry) issuePayloadGenReqOrDiscardPipeQ <- mkFIFOF;

    rule sendQpcQueryReqAndSomeSimpleParse;
        let rdmaPacketMeta = packetParser.rdmaPacketMetaPipeOut.first;
        packetParser.rdmaPacketMetaPipeOut.deq;
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
        
        Bool isQpKeyCheckPass                   = False;
        Bool isQpAccCheckPass                   = False; 
        Bool isMrKeyCheckPass                   = False;
        Bool isMrAccCheckPass                   = False; 
        Bool isMrLowerAddrBoundOk               = False;
        ADDR mrUpperAddrBound                   = ?;
        ADDR reqUpperAddrBound                  = ?;
        MemRegionTableEntry mrEntryUnwraped     = ?;
        PktFragNum expectedPayloadBeatNum       = ?;
        Length packetLen                        = ?;

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
                    mrUpperAddrBound = mrEntry.baseVA + zeroExtend(mrEntry.len);
                    reqUpperAddrBound = reth.va + zeroExtend(packetLen);

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
            mrUpperAddrBound        : mrUpperAddrBound,
            reqUpperAddrBound       : reqUpperAddrBound,
            expectedPayloadBeatNum  : expectedPayloadBeatNum,
            packetLen               : packetLen
        };
        checkMrTableStep2PipeQ.enq(pipelineEntryOut);
    endrule
    

    rule checkMrTableStep2;
        let pipelineEntryIn = checkMrTableStep2PipeQ.first;
        checkMrTableStep2PipeQ.deq;
        let rdmaPacketMeta = pipelineEntryIn.rdmaPacketMeta;
        let packetStatus = pipelineEntryIn.packetStatus;
        let expectedPayloadBeatNum = pipelineEntryIn.expectedPayloadBeatNum;

        Bool isAccessRangeCheckPass = False;
        Bool isPacketBeatCountCheckPass = False;

        if (isRecvPacketStatusNormal(packetStatus)) begin
            let isMrUpperAddrBoundOk = pipelineEntryIn.mrUpperAddrBound >= pipelineEntryIn.reqUpperAddrBound;
            isAccessRangeCheckPass = pipelineEntryIn.isMrLowerAddrBoundOk && isMrUpperAddrBoundOk;

            if (rdmaPacketMeta.hasPayload) begin
                let packetTailMeta = packetParser.rdmaPacketTailMetaPipeOut.first;
                packetParser.rdmaPacketTailMetaPipeOut.deq;

                if (packetTailMeta.beatCnt == expectedPayloadBeatNum) begin
                    isPacketBeatCountCheckPass = True;
                end
            end
            else begin
                isPacketBeatCountCheckPass = True;
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
            isMrLowerAddrBoundOk    : pipelineEntryIn.isMrLowerAddrBoundOk,
            mrUpperAddrBound        : pipelineEntryIn.mrUpperAddrBound,
            reqUpperAddrBound       : pipelineEntryIn.reqUpperAddrBound,
            expectedPayloadBeatNum  : pipelineEntryIn.expectedPayloadBeatNum,
            packetLen               :pipelineEntryIn.packetLen
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
            filterCmdQ.enq(isDiscard);
            if (!isDiscard) begin
                let payloadConReq = PayloadConReq{
                    addr: reth.va,
                    len: pipelineEntryIn.packetLen,
                    baseVA: mrEntry.baseVA,    
                    pgtOffset: mrEntry.pgtOffset 
                };
                payloadGenAndCon.conReqPipeIn.enq(payloadConReq);
            end
        end
    endrule

    rule handleConResp;
        let resp = payloadGenAndCon.conRespPipeOut.first;
        payloadGenAndCon.conRespPipeOut.deq;
        $display("payload con resp = ", fshow(resp));
    endrule


    rule filterDiscardedPayloadStream;
        let isDiscard = filterCmdQ.first;
        let ds = payloadStorage.first;
        payloadStorage.deq;

        if (!isDiscard) begin
            filteredDataStreamForConsumeQ.enq(ds);
        end

        if (ds.isLast) begin
            filterCmdQ.deq;
        end
    endrule

    interface qpcQueryClt = qpcQueryCltInst.clt; 

    interface ethernetFramePipeIn = packetParser.ethernetFramePipeIn;
    interface otherRawPacketPipeOut = packetParser.otherRawPacketPipeOut;
    method setLocalNetworkSettings = packetParser.setLocalNetworkSettings; 
endmodule