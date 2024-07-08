import RegFile :: *;
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


    Vector#(TExp#(splitCntExp), RegFile#(subAddrType, dataType)) subBramVec <- replicateM(mkRegFileFull);

    FIFOF#(subBlockIdxType) orderKeepQueuePortA <- mkSizedFIFOF(6);
    FIFOF#(subBlockIdxType) orderKeepQueuePortB <- mkSizedFIFOF(6);

    FIFOF#(addrType)   bramReadReqQ <- mkFIFOF;
    FIFOF#(dataType)  bramReadRespQ <- mkFIFOF;

    FIFOF#(Tuple2#(addrType, dataType))  bramWriteReqQ  <- mkFIFOF;
    FIFOF#(Bool)                         bramWriteRespQ <- mkFIFOF;

    rule handleBramReadReq;
        let cacheAddr = bramReadReqQ.first;
        bramReadReqQ.deq;

        subAddrType addr = unpack(truncate(pack(cacheAddr)));
        subBlockIdxType subIdx = truncateLSB(pack(cacheAddr));
        let readRespData = subBramVec[subIdx].sub(addr);
        bramReadRespQ.enq(readRespData);
        // orderKeepQueuePortA.enq(subIdx);
        // $display("send BRAM read req to sub block =", fshow(subIdx), "addr=", fshow(addr));
    endrule

    // rule handleBramReadResp;
    //     let subIdx = orderKeepQueuePortA.first;
    //     orderKeepQueuePortA.deq;
    //     let readRespData <- subBramVec[subIdx].portA.response.get;
        
    //     // $display("recv BRAM read resp from sub block=", fshow(subIdx) , ", res=", fshow(readRespData));
    // endrule


    rule handleBramWriteReq;
        let {cacheAddr, writeData} = bramWriteReqQ.first;
        bramWriteReqQ.deq;
        
        subAddrType addr = unpack(truncate(pack(cacheAddr)));
        subBlockIdxType subIdx = truncateLSB(pack(cacheAddr));
        subBramVec[subIdx].upd(addr, writeData);
        orderKeepQueuePortB.enq(subIdx);
        bramWriteRespQ.enq(True);
        // $display("send BRAM write req to sub block =", fshow(subIdx), "addr=", fshow(addr));
    endrule

    // rule handleBramWriteResp;
    //     let subIdx = orderKeepQueuePortB.first;
    //     orderKeepQueuePortB.deq;
    //     let _ <- subBramVec[subIdx].portB.response.get;
        
    //     // $display("recv BRAM write resp from sub block =", fshow(subIdx));
    // endrule


    interface read =  toGPServer(bramReadReqQ,  bramReadRespQ);
    interface write = toGPServer(bramWriteReqQ, bramWriteRespQ);
endmodule


interface MemRegionTable;
    interface Server#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) querySrv;
    interface Server#(MrTableModifyReq, MrTableModifyResp) modifySrv;
endinterface

(* synthesize *)
module mkMemRegionTable(MemRegionTable);
    BramCache#(IndexMR, Maybe#(MemRegionTableEntry), 0) mrTableStorage <- mkBramCache;
    QueuedServer#(MrTableQueryReq, Maybe#(MemRegionTableEntry)) querySrvInst <- mkQueuedServer("mkMemRegionTable querySrvInst");
    QueuedServer#(MrTableModifyReq, MrTableModifyResp) modifySrvInst <- mkQueuedServer("modifySrvInst");

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
        QueuedServer#(MrTableModifyReq, MrTableModifyResp) modifySrvInst <- mkQueuedServer("modifySrvInst");
    
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
    
    BramCache#(PTEIndex, PageTableEntry, 2) pageTableStorage <- mkBramCache;

    QueuedServer#(PgtAddrTranslateReq, ADDR) translateSrvInst <- mkQueuedServer("translateSrvInst");
    QueuedServer#(PgtModifyReq, PgtModifyResp) modifySrvInst <- mkQueuedServer("modifySrvInst");

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
    QueuedServer#(PgtModifyReq, PgtModifyResp) modifySrvInst <- mkQueuedServer("modifySrvInst");

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