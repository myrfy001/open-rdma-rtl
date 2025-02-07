import BuildVector :: *;
import ClientServer :: *;
import Connectable :: *;
import ConnectableF :: *;
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


    FIFOF#(Tuple2#(Bool, reqType))   reqQ <- mkLFIFOF;

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

    // A trick here. This fifo's size must be small, and it should be smaller than portSz, or it will
    // queue too many granted requests ahead of time (mkArbiter will do arbit every clock cycle)
    FIFOF#(Bit#(TLog#(portSz))) grantReqKeepOrderQ <- mkLFIFOF;
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


















interface ServerToClientArbitP#(numeric type channelCnt, type tReq, type tResp);
    interface Vector#(channelCnt, ServerP#(tReq, tResp))        srvIfcVec;
    interface ClientP#(tReq, tResp)                             cltIfc;
endinterface


module mkServerToClientArbitP#(
        String name,
        Integer depth, 
        Bool needReadResp,
        function Bool isReqFinished(tReq request),
        function Bool isRespFinished(tResp response)
    )(ServerToClientArbitP#(channelCnt, tReq, tResp)) provisos (
        Bits#(tReq, szReq),
        Bits#(tResp, szResp),
        Alias#(Bit#(TLog#(channelCnt)), tChannelIdx),
        FShow#(tReq),
        FShow#(tResp)
    );

    Vector#(channelCnt, ServerP#(tReq, tResp))     srvIfcVecInst = newVector;

    Vector#(channelCnt, PipeInAdapterB0#(tReq))                         srvSideReqQueueVec      <- replicateM(mkPipeInAdapterB0);
    Vector#(channelCnt, FIFOF#(tResp))                                   srvSideRespQueueVec     <- replicateM(mkFIFOF);

    FIFOF#(tReq)                           cltSideReqQueue   <-  mkFIFOF;
    PipeInAdapterB0#(tResp)                 cltSideRespQueue  <-  mkPipeInAdapterB0;


    Arbiter_IFC#(channelCnt) innerArbiter <- mkArbiter(False);
    Reg#(Bool) isReqFirstBeatReg <- mkReg(True);
    Reg#(tChannelIdx) curReqChannelIdxReg <- mkRegU;
    FIFOF#(tChannelIdx) respKeepOrderQueue  <- mkSizedFIFOF(depth);   // TODO: check why use mkRegisteredSizedFIFOF will deadlock here

    // rule debug;
    //     $display(
    //         "time=%0t, ", $time, "DEBUG", 
    //         ", isWriteFirstBeatReg=", fshow(isWriteFirstBeatReg),
    //         ", masterSideQueueWm.notFull=", fshow(masterSideQueueWm.notFull),
    //         ", masterSideQueueWd.notFull=", fshow(masterSideQueueWd.notFull),
    //         ", writeSourceChannelIdPipeOutQueue.notFull=", fshow(writeSourceChannelIdPipeOutQueue.notFull)
    //     );
    // endrule

    rule sendWriteArbitReq if (isReqFirstBeatReg);
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (srvSideReqQueueVec[channelIdx].notEmpty) begin
            innerArbiter.clients[channelIdx].request;
                // $display(
                //     "time=%0t:", $time, toGreen(" mkServerToClientArbitP sendWriteArbitReq"),
                //     toBlue(", channelIdx=%d"), channelIdx
                // );
            end
        end
    endrule

    rule recvReqArbitResult if (isReqFirstBeatReg);
        Maybe#(tReq) reqMaybe = tagged Invalid;
        tChannelIdx curChannelIdx = 0;
        for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
            if (innerArbiter.clients[channelIdx].grant) begin
                reqMaybe = tagged Valid srvSideReqQueueVec[channelIdx].first;
                srvSideReqQueueVec[channelIdx].deq;
                curChannelIdx = fromInteger(channelIdx);
            end
        end

        if (reqMaybe matches tagged Valid .req) begin
            cltSideReqQueue.enq(req);
            isReqFirstBeatReg <= isReqFinished(req);
            curReqChannelIdxReg <= curChannelIdx;
            if (needReadResp) begin
                respKeepOrderQueue.enq(curChannelIdx);
            end
            $display(
                "time=%0t:", $time, toGreen(" mkServerToClientArbitP forward request first beat"),
                toBlue(", req="), fshow(req)
            );
        end
        // $display(
        //     "time=%0t:", $time, toGreen(" mkServerToClientArbitP recvReqArbitResult"),
        //     toBlue(", wmMaybe="), fshow(wmMaybe),
        //     toBlue(", curChannelIdx="), fshow(curChannelIdx)
        // );
    endrule

    rule forwardMoreReqBeat if (!isReqFirstBeatReg);
        let req  = srvSideReqQueueVec[curReqChannelIdxReg].first;
        srvSideReqQueueVec[curReqChannelIdxReg].deq;
        cltSideReqQueue.enq(req);
        isReqFirstBeatReg <= isReqFinished(req);

        $display(
            "time=%0t:", $time, toGreen(" mkServerToClientArbitP forward request more beat"),
            toBlue(", req="), fshow(req)
        );
    endrule


    if (needReadResp) begin
        rule forwardReadResp;
            let resp = cltSideRespQueue.first;
            cltSideRespQueue.deq;

            let channelIdx = respKeepOrderQueue.first;
            srvSideRespQueueVec[channelIdx].enq(resp);

            if (isRespFinished(resp)) begin
                respKeepOrderQueue.deq;
            end
            $display(
                "time=%0t:", $time, toGreen(" mkServerToClientArbitP forwardReadResp"),
                toBlue(", channelIdx="), fshow(channelIdx),
                toBlue(", resp="), fshow(resp)
            );
        endrule
    end


    for (Integer channelIdx = 0; channelIdx < valueOf(channelCnt); channelIdx = channelIdx + 1) begin
        srvIfcVecInst[channelIdx] = toGPServerP(toPipeInB0(srvSideReqQueueVec[channelIdx]), toPipeOut(srvSideRespQueueVec[channelIdx]));
    end

    interface srvIfcVec = srvIfcVecInst;
    interface cltIfc = toGPClientP(toPipeOut(cltSideReqQueue), toPipeInB0(cltSideRespQueue));
endmodule