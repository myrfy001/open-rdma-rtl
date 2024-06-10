import FIFOF :: *;
import Vector :: *;
import GetPut :: *;
import Connectable :: *;
import ClientServer :: *;

import PrimUtils :: *;
import SdpBramWrapper :: *;
import PrioritySearchBuffer :: *;

typedef struct {
    Bool        generateResp;
    tAddr       address;
    tBankAddr   bankAddress;
    tData       datain;
} FullyPipelinedUpdateBramUpdateReq#(type tAddr, type tBankAddr, type tData) deriving(Bits, Eq);

typedef struct {
    tAddr       address;
    tBankAddr   bankAddress;
} FullyPipelinedUpdateBramQueryReq#(type tAddr, type tBankAddr) deriving(Bits, Eq);

interface FullyPipelinedUpdateBram2#(type tAddr, type tBankAddr, type tData);
    interface Server#(FullyPipelinedUpdateBramUpdateReq#(tAddr, tBankAddr, tData), tData) updateSrv;
    interface Server#(FullyPipelinedUpdateBramQueryReq#(tAddr, tBankAddr), tData) querySrv;
endinterface

typedef 4 FullyPipelinedUpdateBram2InternalCacheDepth;
module mkFullyPipelinedUpdateBram2#(
        Bool supportQuery,
        function tData updateLogic(tData oldValue, tData newValue)
    )(
        FullyPipelinedUpdateBram2#(tAddr, tBankAddr, tData)
    ) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tBankAddr, szBankAddr),
        Bits#(tData, szData),
        Eq#(tAddr),
        FShow#(tAddr),
        FShow#(tData),
        FShow#(Tuple2#(tAddr, tData)),
        PrimIndex#(tBankAddr, a__),
        Add#(b__, szAddr, ACX_BRAM72K_SDP_ADDR_WIDTH),
        Add#(c__, szData, BITS_COUNT_72K)
    );

    Vector#(TExp#(szBankAddr), SdpBram#(tData)) bramInstVec <- replicateM(mkSdpBram);
    PrioritySearchBuffer#(FullyPipelinedUpdateBram2InternalCacheDepth, tAddr, tData) searchCache <- mkPrioritySearchBuffer(valueOf(FullyPipelinedUpdateBram2InternalCacheDepth));

    FIFOF#(Tuple5#(Bool, Bool, tAddr, tBankAddr, tData)) inflightBramReadReqQ               <- mkSizedFIFOF(5);
    FIFOF#(FullyPipelinedUpdateBramUpdateReq#(tAddr, tBankAddr, tData)) updateReqQ          <- mkFIFOF;
    FIFOF#(FullyPipelinedUpdateBramQueryReq#(tAddr, tBankAddr)) queryReqQ                   <- mkFIFOF;
    FIFOF#(tData) updateRespQ                                                               <- mkFIFOF;
    FIFOF#(tData) queryRespQ                                                                <- mkFIFOF;
    FIFOF#(Tuple5#(Bool, tAddr, tBankAddr, tData, tData)) waitingUpdateDataQ                <- mkFIFOF; // TODO: Try Pipeline FIFO and see timing
    FIFOF#(Tuple4#(Bool, tAddr, tBankAddr, tData)) bramWriteBackQ                           <- mkFIFOF; // TODO: Try Pipeline FIFO and see timing

    // mkConnection(toGet(inflightBramReadReqQ1), toPut(inflightBramReadReqQ2));

    rule debugRule;
        if (!inflightBramReadReqQ.notFull) $display("FullQueue: inflightBramReadReqQ");
        if (!updateReqQ.notFull) $display("FullQueue: updateReqQ");
        if (!updateReqQ.notFull) $display("FullQueue: updateReqQ");
        if (!queryReqQ.notFull) $display("FullQueue: queryReqQ");
        if (!updateRespQ.notFull) $display("FullQueue: updateRespQ");
        if (!queryRespQ.notFull) $display("FullQueue: queryRespQ");
        if (!waitingUpdateDataQ.notFull) $display("FullQueue: waitingUpdateDataQ");
        if (!bramWriteBackQ.notFull) $display("FullQueue: bramWriteBackQ");
    endrule
    
    if (supportQuery) begin
        rule handleInputReq;
            // query has higher priority
            if (queryReqQ.notEmpty) begin
                let isWrite = False;
                let req = queryReqQ.first;
                queryReqQ.deq;
                let generateResp = True; // infact, don't care for query request, only as a place holder
                bramInstVec[req.bankAddress].readSrv.request.put(zeroExtend(pack(req.address)));
                inflightBramReadReqQ.enq(tuple5(isWrite, generateResp, req.address, req.bankAddress, ?));
            end 
            else if (updateReqQ.notEmpty) begin
                let isWrite = True;
                let req = updateReqQ.first;
                updateReqQ.deq;
                let generateResp = req.generateResp;
                bramInstVec[req.bankAddress].readSrv.request.put(zeroExtend(pack(req.address)));
                inflightBramReadReqQ.enq(tuple5(isWrite, generateResp, req.address, req.bankAddress, req.datain));
            end
        endrule
    end

    rule handleBramReadResp;
        let {isWrite, generateResp, address, bankAddress, data} = inflightBramReadReqQ.first;
        inflightBramReadReqQ.deq;
        let resp <- bramInstVec[bankAddress].readSrv.response.get;

        if (isWrite) begin
            waitingUpdateDataQ.enq(tuple5(generateResp, address, bankAddress, resp, data));
        end
        else if (supportQuery) begin
            queryRespQ.enq(resp);
        end
    endrule

    rule handleUpdate;
        let {generateResp, address, bankAddress, oldBramData, newData} = waitingUpdateDataQ.first;
        waitingUpdateDataQ.deq;

        let cacheDataMaybe <- searchCache.search(address);
        let oldData = isValid(cacheDataMaybe) ? fromMaybe(?, cacheDataMaybe) : oldBramData;
        let updatedData = updateLogic(oldData, newData);
        searchCache.enq(address, updatedData);
        bramWriteBackQ.enq(tuple4(generateResp, address, bankAddress, updatedData));
    endrule

    rule handleBramWriteBack;
        let {generateResp, address, bankAddress, updatedData} = bramWriteBackQ.first;
        bramWriteBackQ.deq;
        bramInstVec[bankAddress].write.put(tuple2(zeroExtend(pack(address)), updatedData));

        if (generateResp) begin
            updateRespQ.enq(updatedData);
        end
    endrule

    if (supportQuery) begin
        interface updateSrv = toGPServer(updateReqQ, updateRespQ);
        interface querySrv = toGPServer(queryReqQ, queryRespQ);
    end
    else begin
        interface Server updateSrv;
            interface Put request;
                method Action put(FullyPipelinedUpdateBramUpdateReq#(tAddr, tBankAddr, tData) req);
                    let isWrite = True;
                    let generateResp = req.generateResp;
                    bramInstVec[req.bankAddress].readSrv.request.put(zeroExtend(pack(req.address)));
                    inflightBramReadReqQ.enq(tuple5(isWrite, generateResp, req.address, req.bankAddress, req.datain));
                endmethod
            endinterface
            interface response = toGet(updateRespQ);
        endinterface

        interface Server querySrv;
            interface Put request;
                method Action put(FullyPipelinedUpdateBramQueryReq#(tAddr, tBankAddr) req);
                    immFail("This mkFullyPipelinedUpdateBram2 instance does not support query.", $format(""));
                endmethod
            endinterface
            interface Get response;
                method ActionValue#(tData) get;
                    immFail("This mkFullyPipelinedUpdateBram2 instance does not support query.", $format(""));
                    return ?;
                endmethod
            endinterface
        endinterface
    end
endmodule


