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
    tData       data;
} FullyPipelinedUpdateBramUpdateReq#(type tAddr, type tBankAddr, type tData) deriving(Bits, Eq, FShow);

typedef struct {
    tAddr       address;
    tBankAddr   bankAddress;
} FullyPipelinedUpdateBramQueryReq#(type tAddr, type tBankAddr) deriving(Bits, Eq, FShow);

typedef struct {
    tAddr       address;
    tBankAddr   bankAddress;
    tData       data;
} FullyPipelinedUpdateBramUpdateResp#(type tAddr, type tBankAddr, type tData) deriving(Bits, Eq, FShow);

interface FullyPipelinedUpdateBram2#(type tAddr, type tBankAddr, type tData);
    interface Server#(FullyPipelinedUpdateBramUpdateReq#(tAddr, tBankAddr, tData), FullyPipelinedUpdateBramUpdateResp#(tAddr, tBankAddr, tData)) updateSrv;
    interface Server#(FullyPipelinedUpdateBramQueryReq#(tAddr, tBankAddr), FullyPipelinedUpdateBramUpdateResp#(tAddr, tBankAddr, tData)) querySrv;
endinterface

typedef 6 FullyPipelinedUpdateBram2InternalCacheDepth; 
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
        FShow#(Tuple2#(tAddr, tBankAddr)),
        PrimIndex#(tBankAddr, a__),
        Add#(b__, szAddr, ACX_BRAM72K_SDP_ADDR_WIDTH),
        Add#(c__, szData, BITS_COUNT_72K),
        Alias#(Tuple2#(tAddr, tBankAddr), tSlotTag),
        Alias#(Bit#(TLog#(FullyPipelinedUpdateBram2InternalCacheDepth)), tSlotID),
        Alias#(Tuple2#(Bool, tSlotID), tSlotIdQueryResp)
    );

    Reg#(tSlotID) nextFreeSlotIdCounterReg <- mkReg(0);
    Vector#(TExp#(szBankAddr), SdpBram#(tData)) bramInstVec <- replicateM(mkSdpBram);
    PrioritySearchBuffer#(FullyPipelinedUpdateBram2InternalCacheDepth, tSlotTag, tSlotID) searchCache <- mkPrioritySearchBuffer(valueOf(FullyPipelinedUpdateBram2InternalCacheDepth));

    Vector#(FullyPipelinedUpdateBram2InternalCacheDepth, Reg#(tData)) cacheRegVec <- replicateM(mkRegU);

    FIFOF#(Tuple6#(Bool, Bool, tAddr, tBankAddr, tData, tSlotIdQueryResp)) inflightBramReadReqQ     <- mkSizedFIFOF(5);
    FIFOF#(FullyPipelinedUpdateBramUpdateReq#(tAddr, tBankAddr, tData)) updateReqQ                  <- mkFIFOF;
    FIFOF#(FullyPipelinedUpdateBramQueryReq#(tAddr, tBankAddr)) queryReqQ                           <- mkFIFOF;
    FIFOF#(FullyPipelinedUpdateBramUpdateResp#(tAddr, tBankAddr, tData)) updateRespQ                <- mkFIFOF;
    FIFOF#(FullyPipelinedUpdateBramUpdateResp#(tAddr, tBankAddr, tData)) queryRespQ                 <- mkFIFOF;
    FIFOF#(Tuple6#(Bool, tAddr, tBankAddr, tData, tData, tSlotIdQueryResp)) waitingUpdateDataQ      <- mkFIFOF; // TODO: Try Pipeline FIFO and see timing
    FIFOF#(Tuple4#(Bool, tAddr, tBankAddr, tData)) bramWriteBackQ                                   <- mkFIFOF; // TODO: Try Pipeline FIFO and see timing

    // mkConnection(toGet(inflightBramReadReqQ1), toPut(inflightBramReadReqQ2));

    function ActionValue#(tSlotIdQueryResp) getSlotId(tSlotTag tag);
        return actionvalue
            let slotIdxMaybe <- searchCache.search(tag);
            Bool isNewAllocSlotID;
            if (slotIdxMaybe matches tagged Valid .slotID) begin
                // if the tag is already in the buffer, re-enq this tag so we can make it keep in the buffer longer. 
                searchCache.enq(tag, slotID);
                isNewAllocSlotID = False;
                return tuple2(isNewAllocSlotID, slotID);
            end
            else begin
                // alloc a new slotID and put it into the buffer.
                let newSlotId = nextFreeSlotIdCounterReg;

                // nextFreeSlotIdCounterReg <= nextFreeSlotIdCounterReg + 1;

                if (nextFreeSlotIdCounterReg == fromInteger(valueOf(FullyPipelinedUpdateBram2InternalCacheDepth)-1)) begin
                    nextFreeSlotIdCounterReg <= 0;
                end
                else begin
                    nextFreeSlotIdCounterReg <= nextFreeSlotIdCounterReg + 1;
                end

                searchCache.enq(tag, newSlotId);
                isNewAllocSlotID = True;
                return tuple2(isNewAllocSlotID, newSlotId);
            end
        endactionvalue;
    endfunction

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
                inflightBramReadReqQ.enq(tuple6(isWrite, generateResp, req.address, req.bankAddress, ?, ?));
            end 
            else if (updateReqQ.notEmpty) begin
                let isWrite = True;
                let req = updateReqQ.first;
                updateReqQ.deq;
                let generateResp = req.generateResp;
                bramInstVec[req.bankAddress].readSrv.request.put(zeroExtend(pack(req.address)));
                let slotIdQueryResp <- getSlotId(tuple2(req.address, req.bankAddress)); 
                inflightBramReadReqQ.enq(tuple6(isWrite, generateResp, req.address, req.bankAddress, req.data, slotIdQueryResp));
            end
        endrule
    end

    rule handleBramReadResp;
        let {isWrite, generateResp, address, bankAddress, data, slotIdQueryResp} = inflightBramReadReqQ.first;
        inflightBramReadReqQ.deq;
        let resp <- bramInstVec[bankAddress].readSrv.response.get;

        if (isWrite) begin
            waitingUpdateDataQ.enq(tuple6(generateResp, address, bankAddress, resp, data, slotIdQueryResp));
        end
        else if (supportQuery) begin
            queryRespQ.enq(FullyPipelinedUpdateBramUpdateResp{
                address: address,
                bankAddress: bankAddress,
                data: data
            });
        end
    endrule

    rule handleUpdate;
        let {generateResp, address, bankAddress, oldBramData, newData, slotIdQueryResp} = waitingUpdateDataQ.first;
        waitingUpdateDataQ.deq;

        let {isNewAllocSlotID, slotID} = slotIdQueryResp;

        let oldData = isNewAllocSlotID ?  oldBramData : cacheRegVec[slotID];
        let updatedData = updateLogic(oldData, newData);
        cacheRegVec[slotID] <= updatedData;
        bramWriteBackQ.enq(tuple4(generateResp, address, bankAddress, updatedData));

    endrule

    rule handleBramWriteBack;
        let {generateResp, address, bankAddress, updatedData} = bramWriteBackQ.first;
        bramWriteBackQ.deq;
        bramInstVec[bankAddress].write.put(tuple2(zeroExtend(pack(address)), updatedData));

        // if timing is OK, try move the following if statement to rule handleUpdate to save one cycle delay
        if (generateResp) begin
            updateRespQ.enq(FullyPipelinedUpdateBramUpdateResp{
                address: address,
                bankAddress: bankAddress,
                data: updatedData
            });
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
                    let slotIdQueryResp <- getSlotId(tuple2(req.address, req.bankAddress)); 
                    inflightBramReadReqQ.enq(tuple6(isWrite, generateResp, req.address, req.bankAddress, req.data, slotIdQueryResp));
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
                method ActionValue#(FullyPipelinedUpdateBramUpdateResp#(tAddr, tBankAddr, tData)) get;
                    immFail("This mkFullyPipelinedUpdateBram2 instance does not support query.", $format(""));
                    return ?;
                endmethod
            endinterface
        endinterface
    end
endmodule


