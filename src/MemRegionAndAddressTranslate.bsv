import ClientServer :: *;
import GetPut :: *;
import Cntrs :: *;
import Connectable :: *;
import FIFOF :: *;
import PAClib :: *;
import Vector :: *;
import Cntrs :: * ;

import DataTypes :: *;
import RdmaHeaders :: *;
import PrimUtils :: *;
import Settings :: *;
import RdmaUtils :: *;
import Arbitration :: *;
import Ringbuf :: *;
import ConnectableF :: *;
import Descriptors :: *;
import NapWrapper :: *;

typedef Server#(addrType, dataType)                    BramRead#(type addrType, type dataType);
typedef Server#(Tuple2#(addrType, dataType), Bool)     BramWrite#(type addrType, type dataType);

interface BramCache#(type addrType, type dataType, numeric type splitCntExp);
    interface BramRead #(addrType, dataType)   read;
    interface BramWrite#(addrType, dataType)   write;
endinterface


module mkBramCache(BramCache#(addrType, dataType, splitCntExp)) provisos(
    Bits#(addrType, addrTypeSize),
    Bits#(dataType, dataTypeSize),
    Add#(subAddrTypeSize, splitCntExp, addrTypeSize),
    Alias#(Bit#(subAddrTypeSize), subAddrType),
    Alias#(Bit#(splitCntExp), subBlockIdxType),
    FShow#(addrType),
    FShow#(dataType)
);


    Vector#(TExp#(splitCntExp), AutoInferBram#(subAddrType, dataType)) subBramVec <- replicateM(mkAutoInferBram);

    FIFOF#(subBlockIdxType) orderKeepQueuePortA <- mkSizedFIFOF(6);

    FIFOF#(addrType)   bramReadReqQ <- mkFIFOF;
    FIFOF#(dataType)  bramReadRespQ <- mkFIFOF;

    FIFOF#(Tuple2#(addrType, dataType))  bramWriteReqQ  <- mkFIFOF;
    FIFOF#(Bool)                         bramWriteRespQ <- mkFIFOF;


    rule handleBramReadReq;
        let cacheAddr = bramReadReqQ.first;
        bramReadReqQ.deq;

        subAddrType addr = unpack(truncate(pack(cacheAddr)));
        subBlockIdxType subIdx = truncateLSB(pack(cacheAddr));
        subBramVec[subIdx].putReadReq(addr);
        orderKeepQueuePortA.enq(subIdx);
        // $display("send BRAM read req to sub block =", fshow(subIdx), "addr=", fshow(addr));
    endrule

    rule handleBramReadResp;
        let subIdx = orderKeepQueuePortA.first;
        orderKeepQueuePortA.deq;
        let readRespData <- subBramVec[subIdx].getReadResp;
        bramReadRespQ.enq(readRespData);
        // $display("recv BRAM read resp from sub block=", fshow(subIdx) , ", res=", fshow(readRespData));
    endrule


    rule handleBramWriteReq;
        let {cacheAddr, writeData} = bramWriteReqQ.first;
        bramWriteReqQ.deq;
        
        subAddrType addr = unpack(truncate(pack(cacheAddr)));
        subBlockIdxType subIdx = truncateLSB(pack(cacheAddr));
        subBramVec[subIdx].write(addr, writeData);
        bramWriteRespQ.enq(True);
        // $display("send BRAM write req to sub block =", fshow(subIdx), "addr=", fshow(addr));
    endrule


    interface read =  toGPServer(bramReadReqQ,  bramReadRespQ);
    interface write = toGPServer(bramWriteReqQ, bramWriteRespQ);
endmodule


interface MemRegionTable;
    interface Server#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) querySrv;
    interface Server#(MrTableModifyReq, MrTableModifyResp) modifySrv;
endinterface

(* synthesize *)
module mkMemRegionTable(MemRegionTable);
    BramCache#(IndexMR, Maybe#(MemRegionTableEntry), 1) mrTableStorage <- mkBramCache;
    QueuedServer#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) querySrvInst <- mkQueuedServer("mkMemRegionTable querySrvInst");
    QueuedServer#(MrTableModifyReq, MrTableModifyResp) modifySrvInst <- mkQueuedServer("MemRegionTable modifySrvInst");

    rule handleQueryReq;
        let req <- querySrvInst.getReq;
        mrTableStorage.read.request.put(req.idx);
        $display("get MrTable query req: ", fshow(req));
    endrule

    rule handleQueryResp;
        let resp <- mrTableStorage.read.response.get;
        querySrvInst.putResp(resp);
        $display("send MrTable query resp: ", fshow(resp));
    endrule

    rule handleModifyReq;
        let req <- modifySrvInst.getReq;
        mrTableStorage.write.request.put(tuple2(req.idx, req.entry));
        $display("get MrTable update req: ", fshow(req));
    endrule

    rule handleModifyResp;
        let resp <- mrTableStorage.write.response.get;
        modifySrvInst.putResp(MrTableModifyResp{success: resp});
    endrule

    interface querySrv = querySrvInst.srv;
    interface modifySrv = modifySrvInst.srv;
endmodule


interface MemRegionTableTwoWayQuery;
    interface Vector#(NUMERIC_TYPE_TWO, Server#(MrTableQueryReq, Maybe#(MemRegionTableEntry))) querySrvVec;
    interface Server#(MrTableModifyReq, MrTableModifyResp) modifySrv;
endinterface

(* synthesize *)
module mkMemRegionTableTwoWayQuery(MemRegionTableTwoWayQuery);
    
    function Bool alwaysTrue(anytype resp);
        return True;
    endfunction

    MemRegionTable memRegionTable <- mkMemRegionTable;

    Vector#(NUMERIC_TYPE_TWO, Server2Client#(MrTableQueryReq, Maybe#(MemRegionTableEntry))) srvToCltConvertVec <- replicateM(mkServer2ClientSignleBeat);
    Vector#(NUMERIC_TYPE_TWO, Server#(MrTableQueryReq, Maybe#(MemRegionTableEntry))) querySrvVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, Client#(MrTableQueryReq, Maybe#(MemRegionTableEntry))) queryCltVecInst = newVector;

    querySrvVecInst[0] = srvToCltConvertVec[0].srv;
    querySrvVecInst[1] = srvToCltConvertVec[1].srv;

    queryCltVecInst[0] = srvToCltConvertVec[0].clt;
    queryCltVecInst[1] = srvToCltConvertVec[1].clt;

    let arbitratedClient <- mkClientArbiter(
        "MemRegionTableTwoWayQuery",
        False,
        2,
        queryCltVecInst,
        alwaysTrue,
        alwaysTrue
    );

    mkConnection(arbitratedClient, memRegionTable.querySrv);

    interface querySrvVec = querySrvVecInst;
    interface modifySrv = memRegionTable.modifySrv;

endmodule



interface MemRegionTableEightWayQuery;
    interface Vector#(NUMERIC_TYPE_EIGHT, Server#(MrTableQueryReq, Maybe#(MemRegionTableEntry))) querySrvVec;
    interface Server#(MrTableModifyReq, MrTableModifyResp) modifySrv;
endinterface

(* synthesize *)
module mkMemRegionTableEightWayQuery(MemRegionTableEightWayQuery);
    

    Vector#(NUMERIC_TYPE_FOUR, MemRegionTableTwoWayQuery) twoWayMemRegionTableVec <- replicateM(mkMemRegionTableTwoWayQuery);

    Vector#(NUMERIC_TYPE_EIGHT, Server2Client#(MrTableQueryReq, Maybe#(MemRegionTableEntry))) srvToCltConvertVec <- replicateM(mkServer2ClientSignleBeat);
    Vector#(NUMERIC_TYPE_EIGHT, Server#(MrTableQueryReq, Maybe#(MemRegionTableEntry))) querySrvVecInst = newVector;
    Vector#(NUMERIC_TYPE_EIGHT, Client#(MrTableQueryReq, Maybe#(MemRegionTableEntry))) queryCltVecInst = newVector;

    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_EIGHT); idx = idx + 1) begin
        querySrvVecInst[idx] = srvToCltConvertVec[idx].srv;
        mkConnection(srvToCltConvertVec[idx].clt, twoWayMemRegionTableVec[idx / 2].querySrvVec[idx % 2 == 0 ? 0 : 1]);
    end

    interface querySrvVec = querySrvVecInst;

    interface Server modifySrv;
        interface Put request;
            method Action put(MrTableModifyReq req);
                for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
                    twoWayMemRegionTableVec[idx].modifySrv.request.put(req);
                end
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(MrTableModifyResp) get;
                MrTableModifyResp resp = ?;
                // all instance should be in sync, so any one's response can be used as return value.
                for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
                     resp <- twoWayMemRegionTableVec[idx].modifySrv.response.get;
                end
                return resp;
            endmethod
        endinterface
    endinterface
endmodule


    module mkBypassMemRegionTableForTest(MemRegionTable);
        QueuedServer#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) querySrvInst <- mkQueuedServer("mkMemRegionTable querySrvInst");
        QueuedServer#(MrTableModifyReq, MrTableModifyResp) modifySrvInst <- mkQueuedServer("mkBypassMemRegionTableForTest modifySrvInst");
    
        rule handleQueryReq;
            let req <- querySrvInst.getReq;
            let resp = tagged Valid unpack(0);
            querySrvInst.putResp(resp);
        endrule
    

    
        rule handleModifyReq;
            let req <- modifySrvInst.getReq;
            immFail("not supported. this module is only for simple test", $format(""));
        endrule
    
        interface querySrv = querySrvInst.srv;
        interface modifySrv = modifySrvInst.srv;
    endmodule



interface AddressTranslate;
    interface Server#(PgtAddrTranslateReq, ADDR) translateSrv;
    interface Server#(PgtModifyReq, PgtModifyResp) modifySrv;
endinterface

function PageOffset getPageOffset(ADDR addr);
    return truncate(addr);
endfunction

function ADDR restorePA(PageNumber pn, PageOffset po);
    return signExtend({ pn, po });
endfunction

function PageNumber getPageNumber(ADDR pa);
    return truncate(pa >> valueOf(PAGE_OFFSET_WIDTH));
endfunction

(* synthesize *)
module mkAddressTranslate(AddressTranslate);
    
    BramCache#(PTEIndex, PageTableEntry, 3) pageTableStorage <- mkBramCache;

    QueuedServer#(PgtAddrTranslateReq, ADDR) translateSrvInst <- mkQueuedServer("translateSrvInst");
    QueuedServer#(PgtModifyReq, PgtModifyResp) modifySrvInst <- mkQueuedServer("mkAddressTranslate modifySrvInst");

    FIFOF#(Bit#(PAGE_OFFSET_WIDTH)) offsetInputQ <- mkSizedFIFOF(10);

    rule handleTranslateReq;
        let req <- translateSrvInst.getReq;
        let va = req.addrToTrans;

        let pageNumberOffset = getPageNumber(va) - getPageNumber(req.baseVA);
        PTEIndex pteIdx = req.pgtOffset + truncate(pageNumberOffset);
        pageTableStorage.read.request.put(pteIdx);

        offsetInputQ.enq(getPageOffset(va));

        $display("query AddressTranslate req = ", fshow(req), "pte index=", fshow(pteIdx));
    endrule

    rule handleTranslateResp;
        let pageOffset = offsetInputQ.first;
        offsetInputQ.deq;

        PageTableEntry pte <- pageTableStorage.read.response.get;

        let pa = restorePA(pte.pn, pageOffset);
        translateSrvInst.putResp(pa);

        $display("query AddressTranslate resp pageOffset= ", fshow(pageOffset), "pte =", fshow(pte));
        
    endrule

    rule handleModifyReq;
        let req <- modifySrvInst.getReq;
        pageTableStorage.write.request.put(tuple2(req.idx, req.pte));
        $display("insert AddressTranslate = ", fshow(req));
    endrule

    rule handleModifyResp;
        let resp <- pageTableStorage.write.response.get;
        modifySrvInst.putResp(PgtModifyResp{success: resp});
        $display("insert AddressTranslate response = ", fshow(resp));
    endrule


    interface translateSrv = translateSrvInst.srv;
    interface modifySrv = modifySrvInst.srv;
endmodule






interface AddressTranslateTwoWayQuery;
    interface Vector#(NUMERIC_TYPE_TWO, Server#(PgtAddrTranslateReq, ADDR)) querySrvVec;
    interface Server#(PgtModifyReq, PgtModifyResp) modifySrv;
endinterface

(* synthesize *)
module mkAddressTranslateTwoWayQuery(AddressTranslateTwoWayQuery);
    
    function Bool alwaysTrue(anytype resp);
        return True;
    endfunction

    AddressTranslate addressTranslate <- mkAddressTranslate;

    Vector#(NUMERIC_TYPE_TWO, Server2Client#(PgtAddrTranslateReq, ADDR)) srvToCltConvertVec <- replicateM(mkServer2ClientSignleBeat);
    Vector#(NUMERIC_TYPE_TWO, Server#(PgtAddrTranslateReq, ADDR)) querySrvVecInst = newVector;
    Vector#(NUMERIC_TYPE_TWO, Client#(PgtAddrTranslateReq, ADDR)) queryCltVecInst = newVector;

    querySrvVecInst[0] = srvToCltConvertVec[0].srv;
    querySrvVecInst[1] = srvToCltConvertVec[1].srv;

    queryCltVecInst[0] = srvToCltConvertVec[0].clt;
    queryCltVecInst[1] = srvToCltConvertVec[1].clt;

    let arbitratedClient <- mkClientArbiter(
        "MemRegionTableTwoWayQuery",
        False,
        2,
        queryCltVecInst,
        alwaysTrue,
        alwaysTrue
    );

    mkConnection(arbitratedClient, addressTranslate.translateSrv);

    interface querySrvVec = querySrvVecInst;
    interface modifySrv = addressTranslate.modifySrv;

endmodule



interface AddressTranslateEightWayQuery;
    interface Vector#(NUMERIC_TYPE_EIGHT, Server#(PgtAddrTranslateReq, ADDR)) querySrvVec;
    interface Server#(PgtModifyReq, PgtModifyResp) modifySrv;
endinterface

(* synthesize *)
module mkAddressTranslateEightWayQuery(AddressTranslateEightWayQuery);
    

    Vector#(NUMERIC_TYPE_FOUR, AddressTranslateTwoWayQuery) twoWayAddressTranslateVec <- replicateM(mkAddressTranslateTwoWayQuery);

    Vector#(NUMERIC_TYPE_EIGHT, Server2Client#(PgtAddrTranslateReq, ADDR)) srvToCltConvertVec <- replicateM(mkServer2ClientSignleBeat);
    Vector#(NUMERIC_TYPE_EIGHT, Server#(PgtAddrTranslateReq, ADDR)) querySrvVecInst = newVector;
    Vector#(NUMERIC_TYPE_EIGHT, Client#(PgtAddrTranslateReq, ADDR)) queryCltVecInst = newVector;

    for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_EIGHT); idx = idx + 1) begin
        querySrvVecInst[idx] = srvToCltConvertVec[idx].srv;
        mkConnection(srvToCltConvertVec[idx].clt, twoWayAddressTranslateVec[idx / 2].querySrvVec[idx % 2 == 0 ? 0 : 1]);
    end

    interface querySrvVec = querySrvVecInst;

    interface Server modifySrv;
        interface Put request;
            method Action put(PgtModifyReq req);
                for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
                    twoWayAddressTranslateVec[idx].modifySrv.request.put(req);
                end
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(PgtModifyResp) get;
                PgtModifyResp resp = ?;
                // all instance should be in sync, so any one's response can be used as return value.
                for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
                     resp <- twoWayAddressTranslateVec[idx].modifySrv.response.get;
                end
                return resp;
            endmethod
        endinterface
    endinterface
endmodule


module mkBypassAddressTranslateForTest(AddressTranslate);
    QueuedServer#(PgtAddrTranslateReq, ADDR) translateSrvInst <- mkQueuedServer("translateSrvInst");
    QueuedServer#(PgtModifyReq, PgtModifyResp) modifySrvInst <- mkQueuedServer("mkBypassAddressTranslateForTest modifySrvInst");

    rule handleTranslateReq;
        let req <- translateSrvInst.getReq;
        let va = req.addrToTrans;
        let pa = va;
        translateSrvInst.putResp(pa);
    endrule

    rule handleModifyReq;
        let req <- modifySrvInst.getReq;
        immFail("not supported. this module is only for simple test", $format(""));
    endrule


    interface translateSrv = translateSrvInst.srv;
    interface modifySrv = modifySrvInst.srv;
endmodule




interface MrAndPgtUpdater;
    interface PipeOut#(PgtUpdateDmaReadReq) dmaReadReqPipeOut;
    interface PipeIn#(PgtUpdateDmaReadResp) dmaReadRespPipeIn;

    interface Server#(RingbufRawDescriptor, Bool) mrAndPgtModifyDescSrv;
    interface Client#(MrTableModifyReq, MrTableModifyResp) mrModifyClt;
    interface Client#(PgtModifyReq, PgtModifyResp) pgtModifyClt;
endinterface


typedef enum {
    MrAndPgtManagerFsmStateIdle,
    MrAndPgtManagerFsmStateWaitMRModifyResponse,
    MrAndPgtManagerFsmStateHandlePGTUpdate,
    MrAndPgtManagerFsmStateWaitPGTUpdateLastResp
} MrAndPgtManagerFsmState deriving(Bits, Eq);

typedef 64 PGT_SECOND_STAGE_ENTRY_BIT_WIDTH_PADDED;
typedef TDiv#(PGT_SECOND_STAGE_ENTRY_BIT_WIDTH_PADDED, BYTE_WIDTH) PGT_SECOND_STAGE_ENTRY_BYTE_WIDTH_PADDED;

typedef TDiv#(PCIE_NAP_MAX_BYTE_IN_BURST, PGT_SECOND_STAGE_ENTRY_BYTE_WIDTH_PADDED) PGT_SECOND_STAGE_ENTRY_MAX_CNT_IN_DMA_BURST;
typedef Bit#(TLog#(PGT_SECOND_STAGE_ENTRY_MAX_CNT_IN_DMA_BURST)) ZeroBasedPgtSecondStageEntryCnt;

typedef Bit#(TLog#(TDiv#(PCIE_NAP_BYTE_PER_BEAT, PGT_SECOND_STAGE_ENTRY_BYTE_WIDTH_PADDED))) ZeroBasedPgtEntryCntInDmaBeat;

(* synthesize *)
module mkMrAndPgtUpdater#(
        Clock clkQpcMrPgtSrv,
        Reset rstQpcMrPgtSrv
    )(MrAndPgtUpdater);

    FIFOF#(RingbufRawDescriptor) reqQ <- mkFIFOF;
    FIFOF#(Bool) respQ <- mkFIFOF;

    FIFOF#(PgtUpdateDmaReadReq) dmaReadReqQ <- mkFIFOF;
    FIFOF#(PgtUpdateDmaReadResp) dmaReadRespQ <- mkFIFOF;

    QueuedClient#(MrTableModifyReq, MrTableModifyResp) mrModifyCltInst <- mkSyncQueuedClient("mrModifyCltInst", clkQpcMrPgtSrv, rstQpcMrPgtSrv);
    QueuedClient#(PgtModifyReq, PgtModifyResp) pgtModifyCltInst <- mkSyncQueuedClient("pgtModifyCltInst", clkQpcMrPgtSrv, rstQpcMrPgtSrv);
    

    Reg#(MrAndPgtManagerFsmState) state <- mkReg(MrAndPgtManagerFsmStateIdle);

    Reg#(DataStream) curBeatOfDataReg <- mkReg(unpack(0));
    Reg#(PTEIndex) curSecondStagePgtWriteIdxReg <- mkRegU;
    Reg#(ZeroBasedPgtSecondStageEntryCnt) zeroBasedPgtEntryTotalCntReg <- mkRegU;
    Reg#(ZeroBasedPgtEntryCntInDmaBeat) zeroBasedPgtEntryBeatCntReg <- mkReg(0);
    
    
    
    Integer bytesPerPgtSecondStageEntry = valueOf(PGT_SECOND_STAGE_ENTRY_BYTE_WIDTH_PADDED);

    // we set max inflight pgt update request is 2^3 = 8;
    Count#(Bit#(3)) pgtUpdateRespCounter <- mkCount(0);

    rule updateMrAndPgtStateIdle if (state == MrAndPgtManagerFsmStateIdle);
        let descRaw = reqQ.first;
        reqQ.deq;
        // $display("PGT get modify request", fshow(descRaw));

        RingbufDescCommonHead descComHdr = unpack(truncate(descRaw));

        case (unpack(truncate(descComHdr.opCode)))
            CmdQueueOpcodeUpdateMrTable: begin
                state <= MrAndPgtManagerFsmStateWaitMRModifyResponse;
                CmdQueueReqDescUpdateMrTable desc = unpack(descRaw);
                let modifyReq = MrTableModifyReq {
                    idx: lkey2IndexMR(unpack(desc.mrKey)),
                    entry: isZeroR(desc.mrLength) ?
                            tagged Invalid : 
                            tagged Valid MemRegionTableEntry {
                                pgtOffset: desc.pgtOffset,
                                baseVA: desc.mrBaseVA,
                                len: desc.mrLength,
                                accFlags: unpack(desc.accFlags),
                                pdHandler: desc.pdHandler,
                                keyPart: lkey2KeyPartMR(desc.mrKey)
                            }
                };
                mrModifyCltInst.putReq(modifyReq);
                $display("time=%0t: ", $time, "SOFTWARE DEBUG POINT ", "Hardware receive cmd queue descriptor: ", fshow(desc));
            end
            CmdQueueOpcodeUpdatePGT: begin
                CmdQueueReqDescUpdatePGT desc = unpack(descRaw);

                immAssertAddressAlign(desc.dmaAddr, AddressAlignAssertionMask512B, "PGT table update dma request");
                Length dmaReadLengthInByte = (zeroExtend(desc.zeroBasedEntryCount) + 1) << valueOf(TLog#(PGT_SECOND_STAGE_ENTRY_BYTE_WIDTH_PADDED)); 
                immAssertAddressAndLengthNotCross4kBoundary(desc.dmaAddr, dmaReadLengthInByte, "PGT table update dma request");
                immAssert(
                    dmaReadLengthInByte <= fromInteger(valueOf(PCIE_NAP_MAX_BYTE_IN_BURST)),
                    "PGT update dma request length exceed max PCIe read burst",
                    $format("dmaReadLengthInByte=", fshow(dmaReadLengthInByte), ", maxburst='h%x", valueOf(PCIE_NAP_MAX_BYTE_IN_BURST))
                );

                dmaReadReqQ.enq(PgtUpdateDmaReadReq{
                    addr: desc.dmaAddr,
                    zeroBasedPgtUpdateReadBlockNum: truncate(desc.zeroBasedEntryCount)
                });
                curSecondStagePgtWriteIdxReg <= truncate(desc.startIndex);
                zeroBasedPgtEntryTotalCntReg <= truncate(desc.zeroBasedEntryCount);
                state <= MrAndPgtManagerFsmStateHandlePGTUpdate;
                $display("time=%0t: ", $time, "SOFTWARE DEBUG POINT ", "Hardware receive cmd queue descriptor: ", fshow(desc));
            end
        endcase
    endrule

    rule handleMrModifyResp if (state == MrAndPgtManagerFsmStateWaitMRModifyResponse);
        let _ <- mrModifyCltInst.getResp;
        respQ.enq(True);
        state <= MrAndPgtManagerFsmStateIdle;
    endrule


    rule updatePgtStateHandlePGTUpdate if (state == MrAndPgtManagerFsmStateHandlePGTUpdate);
        // since this is the control path, it's not fully pipelined to make it simple.
        
        if (isZeroR(zeroBasedPgtEntryTotalCntReg)) begin
            state <= MrAndPgtManagerFsmStateWaitPGTUpdateLastResp;
            $display("addr translate modify second stage finished.");
        end
        zeroBasedPgtEntryTotalCntReg <= zeroBasedPgtEntryTotalCntReg - 1;
        
        let ds = ?;
        if (isZeroR(zeroBasedPgtEntryBeatCntReg)) begin
            let newFrag = dmaReadRespQ.first.data;
            dmaReadRespQ.deq;
            $display("beat deq");
            ds = newFrag;
        end
        else begin
            ds = curBeatOfDataReg;
        end

        zeroBasedPgtEntryBeatCntReg <= zeroBasedPgtEntryBeatCntReg + 1;

        let modifyReq = PgtModifyReq {
            idx: curSecondStagePgtWriteIdxReg,
            pte: PageTableEntry {
                pn: truncate(ds.data >> valueOf(PAGE_OFFSET_WIDTH))
            }
        };
        pgtModifyCltInst.putReq(modifyReq);
        pgtUpdateRespCounter.incr(1);
        $display("addr translate modify second stage:", fshow(modifyReq));
        curSecondStagePgtWriteIdxReg <= curSecondStagePgtWriteIdxReg + 1;

        ds.data = ds.data >> valueOf(PGT_SECOND_STAGE_ENTRY_BIT_WIDTH_PADDED);
        curBeatOfDataReg <= ds;
    endrule

    rule handlePgtModifyResp;
        $display("pgtModifyCltInst.getResp");
        let _ <- pgtModifyCltInst.getResp;
        pgtUpdateRespCounter.decr(1);
    endrule

    rule handlePgtModifyLastResp if (state == MrAndPgtManagerFsmStateWaitPGTUpdateLastResp);
        if (pgtUpdateRespCounter == 0) begin
            respQ.enq(True);
            state <= MrAndPgtManagerFsmStateIdle;
        end
    endrule

    interface mrAndPgtModifyDescSrv = toGPServer(reqQ, respQ);

    interface dmaReadReqPipeOut = toPipeOut(dmaReadReqQ);
    interface dmaReadRespPipeIn = toPipeIn(dmaReadRespQ);

    interface mrModifyClt = mrModifyCltInst.clt;
    interface pgtModifyClt = pgtModifyCltInst.clt;
endmodule




typedef Bit#(TLog#(PCIE_NAP_MAX_BURST_LEN)) ZeroBasedPgtUpdateReadBlockNum;

typedef struct {
    ADDR addr;
    ZeroBasedPgtUpdateReadBlockNum zeroBasedPgtUpdateReadBlockNum;
} PgtUpdateDmaReadReq deriving(Bits, FShow);

typedef struct {
    DataStream data;
} PgtUpdateDmaReadResp deriving(Bits, FShow);





interface PgtUpdateDmaNapWrappr;
    interface PipeIn#(PgtUpdateDmaReadReq) dmaReadReqPipeIn;
    interface PipeOut#(PgtUpdateDmaReadResp) dmaReadRespPipeOut;
endinterface

module mkPgtUpdateDmaNapWrappr(PgtUpdateDmaNapWrappr);
    FIFOF#(PgtUpdateDmaReadReq)   dmaReadReqPipeInQ       <- mkFIFOF;
    FIFOF#(PgtUpdateDmaReadResp)  dmaReadRespPipeOutQ     <- mkFIFOF;

    AcxNapSlaveWrapperPipe nap <- mkAcxNapSlaveWrapperPipe;

    rule forwardReadReq;
        let req = dmaReadReqPipeInQ.first;
        dmaReadReqPipeInQ.deq;

        let ar = AxiMmNapBeatAr {
            arid: 0,
            araddr: truncate(req.addr),
            arlen: unpack(zeroExtend(req.zeroBasedPgtUpdateReadBlockNum)),
            arsize: unpack(pack(NapAxiSize32B)),
            arburst: unpack(pack(NapAxiBurstIncr)),
            arlock: False,
            arqos: 0
        };
        nap.readPipeIfc.readAddrPipeIn.enq(ar);
    endrule

    rule forwardReadResp;
        let resp = nap.readPipeIfc.readRespPipeOut.first;
        nap.readPipeIfc.readRespPipeOut.deq;

        let ds = PgtUpdateDmaReadResp {
            data: DataStream {
                data: resp.rdata,
                byteNum: fromInteger(valueOf(USER_LOGIC_DESCRIPTOR_BYTE_WIDTH)),
                startByteIdx: 0,
                isFirst: dontCareValue,
                isLast: resp.rlast
            }
        };

        dmaReadRespPipeOutQ.enq(ds);
    endrule

    interface dmaReadReqPipeIn = toPipeIn(dmaReadReqPipeInQ);
    interface dmaReadRespPipeOut = toPipeOut(dmaReadRespPipeOutQ);
endmodule


