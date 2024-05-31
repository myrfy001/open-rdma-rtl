import FIFOF :: *;
import BRAM :: *;
import Vector :: *;
import GetPut :: *;
import Connectable :: *;

import PrimUtils :: *;
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
        BRAM_Configure cfg, 
        function tData updateLogic(tData oldValue, tData newValue)
    )(
        FullyPipelinedUpdateBram2 #(tAddr, tBankAddr, tData)
    ) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tBankAddr, szBankAddr),
        Bits#(tData, szData),
        Eq#(tAddr),
        FShow#(tAddr),
        FShow#(tData),
        FShow#(Tuple2#(tAddr, tData)),
        PrimIndex#(tBankAddr, a__)
    );

    Vector#(TExp#(szBankAddr), BRAM2Port#(tAddr, tData)) bramInstVec <- replicateM(mkBRAM2Server(cfg));
    PrioritySearchBuffer#(FullyPipelinedUpdateBram2InternalCacheDepth, tAddr, tData) searchCache <- mkPrioritySearchBuffer(valueOf(FullyPipelinedUpdateBram2InternalCacheDepth));

    FIFOF#(Tuple5#(Bool, Bool, tAddr, tBankAddr, tData)) inflightBramReadReqQ1              <- mkFIFOF;
    FIFOF#(Tuple5#(Bool, Bool, tAddr, tBankAddr, tData)) inflightBramReadReqQ2              <- mkFIFOF;
    FIFOF#(FullyPipelinedUpdateBramUpdateReq#(tAddr, tBankAddr, tData)) updateReqQ          <- mkFIFOF;
    FIFOF#(FullyPipelinedUpdateBramQueryReq#(tAddr, tBankAddr)) queryReqQ                   <- mkFIFOF;
    FIFOF#(tData) updateRespQ                                                               <- mkFIFOF;
    FIFOF#(tData) queryRespQ                                                                <- mkFIFOF;
    FIFOF#(Tuple5#(Bool, tAddr, tBankAddr, tData, tData)) waitingUpdateDataQ                <- mkFIFOF; // TODO: Try Pipeline FIFO and see timing
    FIFOF#(Tuple4#(Bool, tAddr, tBankAddr, tData)) bramWriteBackQ                           <- mkFIFOF; // TODO: Try Pipeline FIFO and see timing

    mkConnection(toGet(inflightBramReadReqQ1), toPut(inflightBramReadReqQ2));

    rule debugRule;
        if (!inflightBramReadReqQ1.notFull) $display("FullQueue: inflightBramReadReqQ1");
        if (!updateReqQ.notFull) $display("FullQueue: updateReqQ");
        if (!updateReqQ.notFull) $display("FullQueue: updateReqQ");
        if (!queryReqQ.notFull) $display("FullQueue: queryReqQ");
        if (!updateRespQ.notFull) $display("FullQueue: updateRespQ");
        if (!queryRespQ.notFull) $display("FullQueue: queryRespQ");
        if (!waitingUpdateDataQ.notFull) $display("FullQueue: waitingUpdateDataQ");
        if (!bramWriteBackQ.notFull) $display("FullQueue: bramWriteBackQ");
    endrule
    
    rule handleInputReq;
        // query has higher priority
        if (queryReqQ.notEmpty) begin
            let isWrite = False;
            let req = queryReqQ.first;
            queryReqQ.deq;
            let generateResp = True; // infact, don't care for query request, only as a place holder
            bramInstVec[req.bankAddress].portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: req.address,
                datain: ?
            });
            inflightBramReadReqQ1.enq(tuple5(isWrite, generateResp, req.address, req.bankAddress, ?));
        end 
        else if (updateReqQ.notEmpty) begin
            let isWrite = True;
            let req = updateReqQ.first;
            updateReqQ.deq;
            let generateResp = req.generateResp;
            bramInstVec[req.bankAddress].portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: req.address,
                datain: ?
            });
            inflightBramReadReqQ1.enq(tuple5(isWrite, generateResp, req.address, req.bankAddress, req.datain));
        end
    endrule

    rule handleBramReadResp;
        let {isWrite, generateResp, address, bankAddress, data} = inflightBramReadReqQ2.first;
        inflightBramReadReqQ2.deq;
        let resp <- bramInstVec[bankAddress].portA.response.get;

        if (isWrite) begin
            waitingUpdateDataQ.enq(tuple5(generateResp, address, bankAddress, resp, data));
        end
        else begin
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
        bramInstVec[bankAddress].portB.request.put(BRAMRequest{
            write: True,
            responseOnWrite: False,
            address: address,
            datain: updatedData
        });
        if (generateResp) begin
            updateRespQ.enq(updatedData);
        end
    endrule

    interface updateSrv = toGPServer(updateReqQ, updateRespQ);
    interface querySrv = toGPServer(queryReqQ, queryRespQ);
endmodule


