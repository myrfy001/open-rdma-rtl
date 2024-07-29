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
    tAddr           address;
    tBankAddr       bankAddress;
    tData           data;
    Maybe#(tData)   evictedDataMaybe;
} FullyPipelinedUpdateBramUpdateResp#(type tAddr, type tBankAddr, type tData) deriving(Bits, Eq, FShow);

typedef struct {
    tAddr           address;
    tBankAddr       bankAddress;
    tData           data;
} FullyPipelinedUpdateBramQueryResp#(type tAddr, type tBankAddr, type tData) deriving(Bits, Eq, FShow);

interface FullyPipelinedUpdateBram2#(type tAddr, type tBankAddr, type tData);
    interface Server#(FullyPipelinedUpdateBramUpdateReq#(tAddr, tBankAddr, tData), FullyPipelinedUpdateBramUpdateResp#(tAddr, tBankAddr, tData)) updateSrv;
    interface Server#(FullyPipelinedUpdateBramQueryReq#(tAddr, tBankAddr), FullyPipelinedUpdateBramQueryResp#(tAddr, tBankAddr, tData)) querySrv;
endinterface

module mkFullyPipelinedUpdateBram2#(
        Bool supportQuery,
        function Tuple2#(tData, Bool) updateLogic(tData oldValue, tData newValue)
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
        Alias#(Tuple2#(tAddr, tBankAddr), tSlotTag)
    );

    Vector#(TExp#(szBankAddr), SdpBram#(tData)) rwBramInstVec = newVector;
    Vector#(TExp#(szBankAddr), SdpBram#(tData)) roBramInstVec = newVector;

    for (Integer idx = 0; idx < valueOf(TExp#(szBankAddr)); idx = idx + 1) begin
        rwBramInstVec[idx] <- mkSdpBram(idx);
        roBramInstVec[idx] <- mkSdpBram(idx);
    end
    


    Reg#(tSlotTag) lastUpdateTagReg <- mkReg(unpack(0));
    Reg#(tData) lastUpdateDataReg <- mkReg(unpack(0));




    // FIFOF#(FullyPipelinedUpdateBramUpdateReq#(tAddr, tBankAddr, tData)) updateReqQ                  <- mkFIFOF;
    FIFOF#(FullyPipelinedUpdateBramUpdateResp#(tAddr, tBankAddr, tData)) updateRespQ                <- mkFIFOF;
    // FIFOF#(FullyPipelinedUpdateBramQueryReq#(tAddr, tBankAddr)) queryReqQ                           <- mkFIFOF;
    // FIFOF#(FullyPipelinedUpdateBramQueryResp#(tAddr, tBankAddr, tData)) queryRespQ                 <- mkFIFOF;
    

    FIFOF#(Tuple4#(Bool, tAddr, tBankAddr, tData)) inflightBramReadForWriteReqQ                     <- mkFIFOF;
    FIFOF#(Tuple5#(Bool, tAddr, tBankAddr, tData, tData)) waitingForUpdataQ                         <- mkFIFOF;
    FIFOF#(Tuple2#(tAddr, tBankAddr)) inflightBramReadReqQ                                          <- mkFIFOF;
    FIFOF#(Tuple3#(tAddr, tBankAddr, tData)) bramWriteBackQ                                         <- mkFIFOF; // TODO: Try Pipeline FIFO and see timing

  

    rule debugRule;
        if (!inflightBramReadForWriteReqQ.notFull) $display("FullQueue: inflightBramReadForWriteReqQ");
        // if (!updateReqQ.notFull) $display("FullQueue: updateReqQ");
        // if (!queryReqQ.notFull) $display("FullQueue: queryReqQ");
        if (!updateRespQ.notFull) $display("FullQueue: updateRespQ");
        // if (!queryRespQ.notFull) $display("FullQueue: queryRespQ");
    endrule

    rule handleBramReadResp;
        let {generateResp, address, bankAddress, newData} = inflightBramReadForWriteReqQ.first;
        inflightBramReadForWriteReqQ.deq;
        let bramReadResp <- rwBramInstVec[bankAddress].readSrv.response.get;
        
        tSlotTag reqTag = tuple2(address, bankAddress);
        let tagMatch = reqTag == lastUpdateTagReg;

        bramReadResp = tagMatch ? lastUpdateDataReg : bramReadResp;

        waitingForUpdataQ.enq(tuple5(generateResp, address, bankAddress, newData, bramReadResp));
        // $display("time=%0t", $time, ", handleBramReadResp, tagMatch=", fshow(tagMatch), ", lastUpdateDataReg=", fshow(lastUpdateDataReg), ", bramReadResp=", fshow(bramReadResp));
    endrule

    rule handleUpdata;

        let {generateResp, address, bankAddress, newData, bramReadResp} = waitingForUpdataQ.first;
        waitingForUpdataQ.deq;

        tSlotTag reqTag = tuple2(address, bankAddress);
        let tagMatch = reqTag == lastUpdateTagReg;

        let oldData = tagMatch ? lastUpdateDataReg : bramReadResp;
        let {updatedData, isEvicated} = updateLogic(oldData, newData);

        // $display("time=%0t", $time, ", lastUpdateDataReg=", fshow(lastUpdateDataReg), ", bramReadResp=", fshow(bramReadResp), ", updatedData=", fshow(updatedData), ", isEvicated=", fshow(isEvicated), ", tagMatch=", fshow(tagMatch), ", reqTag=", fshow(reqTag), ", lastUpdateTagReg=", fshow(lastUpdateTagReg));

        lastUpdateTagReg <= reqTag;
        lastUpdateDataReg <= updatedData;

        if (generateResp) begin
            updateRespQ.enq(FullyPipelinedUpdateBramUpdateResp{
                address: address,
                bankAddress: bankAddress,
                data: updatedData,
                evictedDataMaybe: isEvicated ? tagged Valid oldData : tagged Invalid
            });
        end

        bramWriteBackQ.enq(tuple3(address, bankAddress, updatedData));

    endrule

    rule handleBramWriteBack;
        let {address, bankAddress, updatedData} = bramWriteBackQ.first;
        bramWriteBackQ.deq;
        rwBramInstVec[bankAddress].write.put(tuple2(zeroExtend(pack(address)), updatedData));
        if (supportQuery) begin
            roBramInstVec[bankAddress].write.put(tuple2(zeroExtend(pack(address)), updatedData));
        end
        // $display("time=%0t", $time, "handleBramWriteBack, bankAddress=%x", bankAddress, "updatedData=", fshow(updatedData));
    endrule
    
    interface Server updateSrv;
        interface Put request;
            method Action put(FullyPipelinedUpdateBramUpdateReq#(tAddr, tBankAddr, tData) req);
                let generateResp = req.generateResp;
                rwBramInstVec[req.bankAddress].readSrv.request.put(zeroExtend(pack(req.address)));
                inflightBramReadForWriteReqQ.enq(tuple4(generateResp, req.address, req.bankAddress, req.data));
                // $display("time=%0t", $time, "put bram read for write req, bankAddress=%x", req.bankAddress, "req.data=", fshow(req.data));
            endmethod
        endinterface
        interface response = toGet(updateRespQ);
    endinterface

    interface Server querySrv;
        interface Put request;
            method Action put(FullyPipelinedUpdateBramQueryReq#(tAddr, tBankAddr) req);
                if (supportQuery) begin
                    roBramInstVec[req.bankAddress].readSrv.request.put(zeroExtend(pack(req.address)));
                    inflightBramReadReqQ.enq(tuple2(req.address, req.bankAddress));
                end
                else begin
                    immFail("This mkFullyPipelinedUpdateBram2 instance does not support query.", $format(""));
                end
            endmethod
        endinterface
        interface Get response;
            method ActionValue#(FullyPipelinedUpdateBramQueryResp#(tAddr, tBankAddr, tData)) get;
                if (supportQuery) begin
                    let {address, bankAddress} = inflightBramReadReqQ.first;
                    inflightBramReadReqQ.deq;
                    let resp <- rwBramInstVec[bankAddress].readSrv.response.get;
                    return FullyPipelinedUpdateBramQueryResp{
                        address: address,
                        bankAddress: bankAddress,
                        data: resp
                    };
                end
                else begin
                    immFail("This mkFullyPipelinedUpdateBram2 instance does not support query.", $format(""));
                    return ?;
                end
            endmethod
        endinterface
    endinterface

endmodule


