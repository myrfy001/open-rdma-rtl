import GetPut :: *;
import ClientServer :: *;
import Vector :: *;
import SpecialFIFOs :: *;
import Connectable :: *;
import FIFOF :: *;
import PrimUtils :: *;

typedef struct {
    tAddr addr;
    tValue value;
    Bool isWrite;
} CsrReadWriteReq#(type tAddr, type tValue) deriving(Bits, FShow);

typedef struct {
    Maybe#(tValue) valueMaybe;
} CsrReadWriteResp#(type tValue) deriving(Bits, FShow);


typedef Server#(CsrReadWriteReq#(tAddr, tValue), CsrReadWriteResp#(tValue)) CsrReadWriteSrvIfc#(type tAddr, type tValue);
typedef Client#(CsrReadWriteReq#(tAddr, tValue), CsrReadWriteResp#(tValue)) CsrReadWriteCltIfc#(type tAddr, type tValue);

interface CsrSwitch#(type tAddr, type tValue, type downStreamPortCnt);
    interface CsrReadWriteSrvIfc#(tAddr, tValue) busInputSrv;
    interface Vector#(downStreamPortCnt, CsrReadWriteCltIfc#(tAddr, tValue)) busOutputCltVecIfc;
endinterface


interface PutToGetProxy#(type tData);
    interface Put#(tData) in;
    interface Get#(tData) out;
endinterface

module mkPutToGetProxy(PutToGetProxy#(tData)) provisos (
    Bits#(tData, szData)
);

    Wire#(tData) relayWire <- mkWire;

    interface Put in;
        
        method Action put(tData value);
            relayWire <= value;
        endmethod
    endinterface

    interface Get out;
        method ActionValue#(tData) get;
            return relayWire;
        endmethod
    endinterface
endmodule



module mkCombinationalCsrSwitch(CsrSwitch#(tAddr, tValue, downStreamPortCnt)) provisos (
    Bits#(tAddr, szAddr),
    Bits#(tValue, szValue)
);

    Wire#(CsrReadWriteReq#(tAddr, tValue)) reqInputRelayWire <- mkWire;
    Vector#(downStreamPortCnt, PutToGetProxy#(CsrReadWriteReq#(tAddr, tValue))) reqRelayVec <- replicateM(mkPutToGetProxy);
    Vector#(downStreamPortCnt, PutToGetProxy#(CsrReadWriteResp#(tValue))) respRelayVec <- replicateM(mkPutToGetProxy);
    Vector#(downStreamPortCnt, CsrReadWriteCltIfc#(tAddr, tValue)) busOutputCltVec = newVector;

    for (Integer idx = 0; idx < valueOf(downStreamPortCnt); idx = idx + 1) begin
        busOutputCltVec[idx] = interface CsrReadWriteCltIfc#(tAddr, tValue)
            interface request = reqRelayVec[idx].out;
            interface response = respRelayVec[idx].in;
        endinterface;
    end

    interface CsrReadWriteSrvIfc busInputSrv;
        interface Put request;
            method Action put(CsrReadWriteReq#(tAddr, tValue) req);
                for (Integer portIdx = 0; portIdx < valueOf(downStreamPortCnt); portIdx = portIdx + 1) begin
                    reqRelayVec[portIdx].in.put(req);
                end
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(CsrReadWriteResp#(tValue)) get;
                Bool foundValidResp = False;
                CsrReadWriteResp#(tValue) finalResp = CsrReadWriteResp{valueMaybe: tagged Invalid};

                for (Integer portIdx = 0; portIdx < valueOf(downStreamPortCnt); portIdx = portIdx + 1) begin
                    let resp <- respRelayVec[portIdx].out.get;
                    if (isValid(resp.valueMaybe)) begin
                        immAssert(
                            !foundValidResp,
                            "More than one CSR generate response to the same address @ mkPipelineCsrSwitch",
                            $format("port index = %x", portIdx)
                        );

                        foundValidResp = True;
                        finalResp = resp;
                    end
                end
                return finalResp;
            endmethod
        endinterface
    endinterface

    interface busOutputCltVecIfc = busOutputCltVec;
endmodule


module mkPipelineCsrSwitch(CsrSwitch#(tAddr, tValue, downStreamPortCnt)) provisos (
        Bits#(tAddr, szAddr),
        Bits#(tValue, szValue)
    );

    Vector#(downStreamPortCnt, FIFOF#(CsrReadWriteReq#(tAddr, tValue))) reqRelayVec <- replicateM(mkPipelineFIFOF);
    Vector#(downStreamPortCnt, FIFOF#(CsrReadWriteResp#(tValue))) respRelayVec <- replicateM(mkPipelineFIFOF);
    Vector#(downStreamPortCnt, CsrReadWriteCltIfc#(tAddr, tValue)) busOutputCltVec = newVector;

    for (Integer idx = 0; idx < valueOf(downStreamPortCnt); idx = idx + 1) begin
        busOutputCltVec[idx] = toGPClient(reqRelayVec[idx], respRelayVec[idx]);
    end

    interface CsrReadWriteSrvIfc busInputSrv;
        interface Put request;
            method Action put(CsrReadWriteReq#(tAddr, tValue) req);
                for (Integer portIdx = 0; portIdx < valueOf(downStreamPortCnt); portIdx = portIdx + 1) begin
                    reqRelayVec[portIdx].enq(req);
                end
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(CsrReadWriteResp#(tValue)) get;
                Bool foundValidResp = False;
                CsrReadWriteResp#(tValue) finalResp = CsrReadWriteResp{valueMaybe: tagged Invalid};

                for (Integer portIdx = 0; portIdx < valueOf(downStreamPortCnt); portIdx = portIdx + 1) begin
                    let resp = respRelayVec[portIdx].first; 
                    respRelayVec[portIdx].deq;
                    if (isValid(resp.valueMaybe)) begin
                        immAssert(
                            !foundValidResp,
                            "More than one CSR generate response to the same address @ mkPipelineCsrSwitch",
                            $format("port index = %x", portIdx)
                        );

                        foundValidResp = True;
                        finalResp = resp;
                    end
                end
                return finalResp;
            endmethod

        endinterface
    endinterface

    interface busOutputCltVecIfc = busOutputCltVec;


endmodule

interface CsrLeaf#(type tAddr, type tValue);
    interface CsrReadWriteSrvIfc#(tAddr, tValue) busInputSrv;

    method Action _write (tValue value);
    method tValue _read;
    method ActionValue#(tValue) readWithSideEffecct;
endinterface

module mkCsrLeaf#(Integer myAddr) (CsrLeaf#(tAddr, tValue)) provisos (
    Bits#(tAddr, szAddr),
    Bits#(tValue, szData),
    Literal#(tAddr),
    Eq#(tAddr)
);

    Reg#(tValue) storageReg <- mkReg(unpack(0));
    RWire#(tValue) userWriteReqWire <- mkRWire;
    RWire#(tValue) busWriteReqWire <- mkRWire;

    PulseWire busReqIsReadWire <- mkPulseWire;
    PulseWire busReqOccuredWire <- mkPulseWire;



    rule arbitUserAndBusWrite;
        if (busWriteReqWire.wget matches tagged Valid .value) begin
            storageReg <= value;
        end
        else if (userWriteReqWire.wget matches tagged Valid .value) begin
            storageReg <= value;
        end
    endrule

    method Action _write (tValue value);
        userWriteReqWire.wset(value);
    endmethod
    method ActionValue#(tValue) readWithSideEffecct;
        return storageReg;
    endmethod
    method tValue _read;
        return storageReg;
    endmethod

    interface CsrReadWriteSrvIfc busInputSrv;
        interface Put request;
            method Action put(CsrReadWriteReq#(tAddr, tValue) req);
                busReqOccuredWire.send;

                Bool isAddrHit = req.addr == fromInteger(myAddr);

                $display("leaf node get req, addr=%x", req.addr, "my addr=%x", myAddr);

                if (isAddrHit) begin
                    if (req.isWrite) begin
                        busWriteReqWire.wset(req.value);
                    end
                    else begin
                        busReqIsReadWire.send;
                    end
                end
            endmethod
        endinterface

        interface Get response;

            method ActionValue#(CsrReadWriteResp#(tValue)) get if (busReqOccuredWire);
                if (busReqIsReadWire) begin
                    return CsrReadWriteResp{valueMaybe: tagged Valid storageReg};
                end
                else begin
                    return CsrReadWriteResp{valueMaybe: tagged Invalid};
                end
            endmethod
        endinterface
    endinterface

endmodule

interface CsrLeafAccessor#(type tAddr, type tValue);
    interface CsrReadWriteSrvIfc#(tAddr, tValue) busInputSrv;

    method Action readValIn (tValue value);
    method tValue writeValOut;
endinterface


module mkCsrLeafAccessor#(Integer myAddr) (CsrLeafAccessor#(tAddr, tValue)) provisos (
    Bits#(tAddr, szAddr),
    Bits#(tValue, szData),
    Literal#(tAddr),
    Eq#(tAddr)
);

    RWire#(tValue) readValueWire <- mkRWire;
    Wire#(tValue) busWriteReqWire <- mkWire;

    PulseWire busReqIsReadWire <- mkPulseWire;
    PulseWire busReqOccuredWire <- mkPulseWire;

    method Action readValIn (tValue value);
        readValueWire.wset(value);
    endmethod

    method tValue writeValOut;
        return busWriteReqWire;
    endmethod

    interface CsrReadWriteSrvIfc busInputSrv;
        interface Put request;
            method Action put(CsrReadWriteReq#(tAddr, tValue) req);
                busReqOccuredWire.send;

                Bool isAddrHit = req.addr == fromInteger(myAddr);

                $display("leaf node get req, addr=%x", req.addr, "my addr=%x", myAddr);

                if (isAddrHit) begin
                    if (req.isWrite) begin
                        busWriteReqWire <= req.value;
                    end
                    else begin
                        busReqIsReadWire.send;
                    end
                end
            endmethod
        endinterface

        interface Get response;

            method ActionValue#(CsrReadWriteResp#(tValue)) get if (busReqOccuredWire);
                if (busReqIsReadWire) begin
                    if (readValueWire.wget matches tagged Valid .inputReadData) begin
                        return CsrReadWriteResp{valueMaybe: tagged Valid inputReadData};
                    end 
                    else begin
                        immFail("mkCsrLeafAccessor, read value should be valid", $format(""));
                        return ?;
                    end
                end
                else begin
                    return CsrReadWriteResp{valueMaybe: tagged Invalid};
                end
            endmethod
        endinterface
    endinterface

endmodule