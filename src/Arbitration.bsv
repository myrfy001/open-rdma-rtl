import BuildVector :: *;
import ClientServer :: *;
import Connectable :: *;
import FIFOF :: *;
import GetPut :: *;
import PAClib :: *;
import Vector :: *;

import PrimUtils :: *;
import RdmaUtils :: *;

import Arbiter :: * ;






module mkTwoWayFixedPriorityStreamMux#(
    String name,
    Bool enableDebug,
    Vector#(2, PipeOut#(reqType)) inVec,
    function Bool isReqFinished(reqType request)
)(Get#(Tuple2#(Bool, reqType))) provisos(
    FShow#(reqType), 
    Bits#(reqType, reqSz)
);

    Reg#(Bool) isIdleReg <- mkReg(True);
    Reg#(Bool) isForwardingCh0Reg <- mkReg(False);


    FIFOF#(Tuple2#(Bool, reqType))   reqQ <- mkFIFOF;

    rule handleIdle if (isIdleReg);
        let hasReq = inVec[0].notEmpty || inVec[1].notEmpty;
        let data = ?;
        let isForwardingCh0 = ?;
        if (inVec[0].notEmpty) begin
            data = inVec[0].first;
            inVec[0].deq;
            isForwardingCh0 = True;
        end
        else if (inVec[1].notEmpty) begin
            data = inVec[1].first;
            inVec[1].deq;
            isForwardingCh0 = False;
        end
        isForwardingCh0Reg <= isForwardingCh0;

        if (hasReq) begin
            reqQ.enq(tuple2(isForwardingCh0, data));
            if (!isReqFinished(data)) begin
                isIdleReg <= False;
            end
        end
    endrule

    rule handleForward if (!isIdleReg);
        let data = ?;
        if (isForwardingCh0Reg) begin
            data = inVec[0].first;
            inVec[0].deq;
        end
        else begin
            data = inVec[1].first;
            inVec[1].deq;
        end
        reqQ.enq(tuple2(isForwardingCh0Reg, data));
        if (isReqFinished(data)) begin
            isIdleReg <= True;
        end
    endrule

    return toGet(reqQ);
endmodule





module mkClientArbiter#(
    String name,
    Bool enableDebug,
    Integer keepOrderQueueLen,
    Vector#(portSz, Client#(reqType, respType)) clientVec,
    function Bool isReqFinished(reqType request),
    function Bool isRespFinished(respType response)
)(Client#(reqType, respType)) provisos(
    Bits#(reqType, reqSz),
    Bits#(respType, respSz),
    Add#(1, anysize, portSz),
    FShow#(reqType)
);

    Arbiter_IFC#(portSz) arbiter <- mkArbiter(False);
    Reg#(Bool) canSubmitArbitReqReg <- mkReg(True);

    Vector#(portSz, FIFOF#(reqType)) clientReqFifoVec <- replicateM(mkLFIFOF);
    // Vector#(portSz, FIFOF#(respType)) clientRespFifoVec <- replicateM(mkFIFOF);

    // A trick here. This fifo's size must be small, and it should be smaller than portSz, or it will
    // queue too many granted requests ahead of time (mkArbiter will do arbit every clock cycle)
    FIFOF#(Bit#(TLog#(portSz))) grantReqKeepOrderQ <- mkFIFOF;
    // This Fifo can be larger since receive response may take some time and there can be many outstanding requests.
    FIFOF#(Bit#(TLog#(portSz))) grantRespKeepOrderQ <- mkSizedFIFOF(keepOrderQueueLen);

    FIFOF#(reqType)   reqQ <- mkLFIFOF;
    FIFOF#(respType) respQ <- mkLFIFOF;

    // convert input Get interface to a FIFOF since we need full/empty signal
    // THIS QUEUE MUST BE SIZE OF 2, SO WHEN IT FULL IT MEANS THAT WE HAVE TO ELEMENTS IN QUEUE NOW.
    for (Integer idx=0; idx < valueOf(portSz); idx=idx+1) begin
        mkConnection(clientVec[idx].request, toPut(clientReqFifoVec[idx]));
    end



    rule forwardRequest if (!canSubmitArbitReqReg);
        let idx = grantReqKeepOrderQ.first;
        let req = clientReqFifoVec[idx].first;
        clientReqFifoVec[idx].deq;
        reqQ.enq(req);

        let reqFinished = isReqFinished(req);
        if (reqFinished) begin
            canSubmitArbitReqReg <= True;
            grantReqKeepOrderQ.deq;
        end
        

        if (enableDebug) begin
            $display(
                "time=%0t: ", $time,
                fshow(name),
                " arbitrate request, reqIdx=%0d", idx,
                ", reqFinished=", fshow(reqFinished)
            );
        end
        
        
    endrule

    for (Integer idx=0; idx < valueOf(portSz); idx=idx+1) begin
        rule sendArbitReq;
            if (enableDebug) begin
                $display(
                    "time=%0t: ", $time,
                    fshow(name),
                    " arbitrate sendArbitReq debug, reqIdx=%0d", idx,
                    " canSubmitArbitReqReg = ", fshow(canSubmitArbitReqReg),
                    " clientReqFifoVec[idx].notEmpty = ", fshow(clientReqFifoVec[idx].notEmpty)
                );
            end
            
            if (canSubmitArbitReqReg) begin
                arbiter.clients[idx].request;
                if (enableDebug) begin
                    $display(
                        "time=%0t: ", $time,
                        fshow(name),
                        " arbitrate submit req, reqIdx=%0d", idx
                    );
                end
            end
        endrule

        

        rule forwardResponse if (grantRespKeepOrderQ.first == fromInteger(idx));
            let resp = respQ.first;
            respQ.deq;
            clientVec[idx].response.put(resp);
            let respFinished = isRespFinished(resp);
            if (respFinished) begin
                grantRespKeepOrderQ.deq;
            end

            if (enableDebug) begin
                $display(
                    "time=%0t: ", $time,
                    fshow(name),
                    " dispatch response, idx=%0d", idx,
                    ", respFinished=", fshow(respFinished)
                );
            end
        endrule
    end

    rule recvArbitResp if (canSubmitArbitReqReg);

        Vector#(portSz, Bool) arbiterRespVec;
        for (Integer idx=0; idx < valueOf(portSz); idx=idx+1) begin
            arbiterRespVec[idx] = arbiter.clients[idx].grant;
        end
        if (enableDebug) begin
            $display(
                "time=%0t: ", $time,
                fshow(name),
                " arbit result=", fshow(arbiterRespVec)
            );
        end
        if (pack(arbiterRespVec) != 0) begin
            let idx = arbiter.grant_id;
            let req = clientReqFifoVec[idx].first;

            reqQ.enq(req);
            clientReqFifoVec[idx].deq;
            grantRespKeepOrderQ.enq(idx);

            if (!isReqFinished(req)) begin
                grantReqKeepOrderQ.enq(idx);
                canSubmitArbitReqReg <= False;
                if (enableDebug) begin
                    $display(
                        "time=%0t: ", $time,
                        fshow(name),
                        " grant new single beat request, client idx=%0d", idx
                    );
                end
            end
            
            if (enableDebug) begin
                $display(
                    "time=%0t: ", $time,
                    fshow(name),
                    ", grant new request, client idx=%0d", idx, 
                    ", req=", fshow(req)
                );
            end
        end

    endrule

    rule debug if (enableDebug);
        if (!reqQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(name) , " reqQ");
        end
        if (!respQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(name) , " respQ");
        end

        if (!reqQ.notEmpty) begin
            $display("time=%0t: ", $time, "EMPTY_QUEUE_DETECTED: mkClientArbiter ", fshow(name) , " reqQ");
        end
        if (!respQ.notEmpty) begin
            $display("time=%0t: ", $time, "EMPTY_QUEUE_DETECTED: mkClientArbiter ", fshow(name) , " respQ");
        end

        if (!grantReqKeepOrderQ.notEmpty) begin
            $display("time=%0t: ", $time, "EMPTY_QUEUE_DETECTED: mkClientArbiter ", fshow(name) , " grantReqKeepOrderQ");
        end

        if (!grantReqKeepOrderQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(name) , " grantReqKeepOrderQ");
        end

        if (!grantRespKeepOrderQ.notFull) begin
            $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(name) , " grantRespKeepOrderQ");
        end

        for (Integer idx=0; idx < valueOf(portSz); idx=idx+1) begin

            if (!clientReqFifoVec[idx].notFull) begin
                $display("time=%0t: ", $time, "FULL_QUEUE_DETECTED: mkClientArbiter ", fshow(name) , " clientReqFifoVec[%0d]", idx);
            end

            if (!clientReqFifoVec[idx].notEmpty) begin
                $display("time=%0t: ", $time, "EMPTY_QUEUE_DETECTED: mkClientArbiter ", fshow(name) , " clientReqFifoVec[%0d]", idx);
            end
            
        end
    endrule

    return toGPClient(reqQ, respQ);
endmodule


