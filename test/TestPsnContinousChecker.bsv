import Connectable :: *;
import GetPut :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 

import PrimUtils :: *;
import RdmaUtils :: *;
import Utils4Test :: *;
import EthernetTypes :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ConnectableF :: *;

import PsnContinousChecker :: *;



module mkGenRandomPsnInContinousWindow(PipeOut#(PSN)) provisos (
    NumAlias#(TDiv#(OOO_WINDOW_SIZE, 2), szRandomWindow)
);
    FIFOF#(PSN) outputBufferQ <- mkFIFOF;
    
    Reg#(PSN) nextPsnReg <- mkReg(0);
    Reg#(Bit#(5)) swapCounterReg <- mkReg(0);
    Reg#(Bit#(8)) moveCounterReg <- mkReg(0);
    Reg#(Vector#(szRandomWindow, PSN)) randomWindowVecReg <- mkRegU;

    PipeOut#(Length) randomPsnSlotIdxPipeOut <- mkRandomLenPipeOut(0, fromInteger(valueOf(szRandomWindow)-1));

    Reg#(Bit#(2)) stateReg <- mkReg(0);
    rule addPsnToRandomWindow if (stateReg == 0);

        Vector#(szRandomWindow, PSN) winVec = newVector;
        for (Integer idx = 0; idx < valueOf(szRandomWindow); idx = idx + 1) begin
            winVec[idx] = nextPsnReg + fromInteger(idx);
        end
        nextPsnReg <= nextPsnReg + fromInteger(valueOf(szRandomWindow));
        randomWindowVecReg <= winVec;
        stateReg <= 1;

    endrule

    rule swapWindow if (stateReg == 1);
        let randomIdx = randomPsnSlotIdxPipeOut.first;
        randomPsnSlotIdxPipeOut.deq;

        let winVec = randomWindowVecReg;
        PSN t = winVec[valueOf(szRandomWindow) / 2];
        winVec[valueOf(szRandomWindow) / 2] = winVec[randomIdx];
        winVec[randomIdx] = t;

        randomWindowVecReg <= winVec;

        if (swapCounterReg == -1) begin
            swapCounterReg <= 0;
            stateReg <= 2;
        end
        else begin
            swapCounterReg <= swapCounterReg + 1;
        end
        
    endrule

    rule movePsnToOutputBuffer if (stateReg == 2);
        if (moveCounterReg == fromInteger(valueOf(szRandomWindow)-1)) begin
            moveCounterReg <= 0;
            stateReg <= 0;
        end
        else begin
            moveCounterReg <= moveCounterReg + 1;
        end
        let winVec = randomWindowVecReg;
        outputBufferQ.enq(winVec[moveCounterReg]);
    endrule

    return toPipeOut(outputBufferQ);
endmodule

(* doc = "testcase" *)
module mkTestCpsnCalc(Empty);
    Vector#(6, PipeOut#(PSN)) rangPsnPipeOutVec <- replicateM(mkGenRandomPsnInContinousWindow); 
    Vector#(4, PipeOut#(Length)) qpnRandPipeOutVec <- replicateM(mkRandomLenPipeOut(0, fromInteger(8)));

    Reg#(Bit#(3)) stateReg <- mkReg(0);
    Vector#(4, Reg#(Maybe#(Tuple2#(QPN, PSN)))) reqRegVector <- replicateM(mkReg(tagged Invalid));

    FIFOF#(Vector#(4, Maybe#(Tuple2#(QPN, PSN)))) bufferedReqQueue <- mkSizedFIFOF(1024);

    Reg#(Bool) deqEvenOddReg <- mkReg(False);

    FourChannelPsnBitmapPreMerge dutPreMerge <- mkFourChannelPsnBitmapPreMerge;
    BitmapWindowStorage#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE) dutPsnMergeStorage <- mkBitmapWindowStorage("init_bram_psn_merge_storage.bin");

    for (Integer idx = 0; idx < 4; idx = idx + 1) begin
        rule fillReqVector if (stateReg == fromInteger(idx));
            IndexQP qpnIdx = truncate(qpnRandPipeOutVec[idx].first);
            PSN psn = truncateLSB(qpnRandPipeOutVec[idx].first);
            qpnRandPipeOutVec[idx].deq;
            stateReg <= stateReg + 1;
            if (qpnIdx >= 6) begin
                reqRegVector[idx] <= tagged Invalid;
            end
            else begin
                let req = tuple2(genQPN(qpnIdx, 0), rangPsnPipeOutVec[qpnIdx].first);
                reqRegVector[idx] <= tagged Valid req;
                rangPsnPipeOutVec[qpnIdx].deq;
            end
        endrule
    end

    rule fillBufferedReqQueue if (stateReg == 4);
        bufferedReqQueue.enq(vec(reqRegVector[0], reqRegVector[1], reqRegVector[2], reqRegVector[3]));
        stateReg <= 5;
    endrule

    rule continueFillReqBufferOrOutputBuffer if (stateReg == 5);
        stateReg <= bufferedReqQueue.notFull ? 0 : 6;
    endrule

    rule outputBufferedReq if (stateReg == 6);
        if (bufferedReqQueue.notEmpty) begin
            let reqVec = bufferedReqQueue.first;
            bufferedReqQueue.deq;
            for (Integer idx = 0; idx < 4; idx = idx + 1) begin
                if (reqVec[idx] matches tagged Valid .req) begin
                    dutPreMerge.reqPipeInVec[idx].enq(FourChannelPsnBitmapPreMergeReq {
                        qpn: tpl_1(req),
                        psn: tpl_2(req)
                    });
                end
            end
        end
        else begin
            stateReg <= 0;
        end
    endrule


    rule forwardPremergeToStorage;
        deqEvenOddReg <= !deqEvenOddReg;
        let resp = dutPreMerge.respPipeOut.first;
        if (deqEvenOddReg) begin
            // $display("time=%0t", $time, ", mkTestCpsnCalc forwardPremergeToStorage", 
            //         ", resp=", fshow(resp));

            if (resp[0] matches tagged Valid .req) begin
                dutPsnMergeStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });
                if (getIndexQP(req.qpn) == 4) begin
                    // $display("time=%0t", $time, ", per merge result=", fshow(req));
                end
            end
            else begin
                dutPsnMergeStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (resp[1] matches tagged Valid .req) begin
                dutPsnMergeStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });
                if (getIndexQP(req.qpn) == 4) begin
                    // $display("time=%0t", $time, ", per merge result=", fshow(req));
                end
            end
            else begin
                dutPsnMergeStorage.reqPipeInVec[1].enq(tagged Invalid);
            end
        end
        else begin
            if (resp[2] matches tagged Valid .req) begin
                dutPsnMergeStorage.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });
                if (getIndexQP(req.qpn) == 4) begin
                    // $display("time=%0t", $time, ", per merge result=", fshow(req));
                end
            end
            else begin
                dutPsnMergeStorage.reqPipeInVec[0].enq(tagged Invalid);
            end

            if (resp[3] matches tagged Valid .req) begin
                dutPsnMergeStorage.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
                    rowAddr: getIndexQP(req.qpn),
                    entry: BitmapWindowStorageEntry {
                        data: req.bitmap,
                        leftBound: req.maxLeftBoundary
                    }
                });
                if (getIndexQP(req.qpn) == 4) begin
                    // $display("time=%0t", $time, ", per merge result=", fshow(req));
                end
            end
            else begin
                dutPsnMergeStorage.reqPipeInVec[1].enq(tagged Invalid);
            end

            dutPreMerge.respPipeOut.deq;
        end
    endrule
    
    rule getResp;
        let resp1 = dutPsnMergeStorage.respPipeOutVec[0].first;
        dutPsnMergeStorage.respPipeOutVec[0].deq;
        let resp2 = dutPsnMergeStorage.respPipeOutVec[1].first;
        dutPsnMergeStorage.respPipeOutVec[1].deq;
        if (resp1 matches tagged Valid .resp) begin
            if (resp.rowAddr == 4) begin
                $display("time=%0t", $time, ", resp=", fshow(resp));

                immAssert(
                    resp.windowShiftedOutData == -1,
                    "PSN contonous checker found broken reorder window.",
                    $format("resp=", fshow(resp))
                );
            end
            
        end
        if (resp2 matches tagged Valid .resp) begin
            if (resp.rowAddr == 4) begin
                $display("time=%0t", $time, ", resp=", fshow(resp));

                immAssert(
                    resp.windowShiftedOutData == -1,
                    "PSN contonous checker found broken reorder window.",
                    $format("resp=", fshow(resp))
                );
            end 
        end
        
    endrule

    rule injectReset;
        dutPsnMergeStorage.resetReqPipeIn.enq(1);
    endrule

    rule getResetResp;
        dutPsnMergeStorage.resetRespPipeOut.deq;
        $display("Got Reset Resp");
    endrule
endmodule


(* doc = "testcase" *)
module mkTestBitmapPreMerge(Empty);
 
    FourChannelPsnBitmapPreMerge dut <- mkFourChannelPsnBitmapPreMerge;

    rule inject;
        let ch0 = FourChannelPsnBitmapPreMergeReq{psn: 0, qpn: 0};
        let ch1 = FourChannelPsnBitmapPreMergeReq{psn: 1, qpn: 0};
        let ch2 = FourChannelPsnBitmapPreMergeReq{psn: 2, qpn: 1};
        let ch3 = FourChannelPsnBitmapPreMergeReq{psn: 64, qpn: 0};

        // dut.reqPipeInVec[0].enq(ch0);
        dut.reqPipeInVec[1].enq(ch1);
        dut.reqPipeInVec[2].enq(ch2);
        dut.reqPipeInVec[3].enq(ch3);
    endrule

    rule check;
        let resp = dut.respPipeOut.first;
        dut.respPipeOut.deq;
        $display(fshow(resp));
    endrule
endmodule

(* doc = "testcase" *)
module mkTestCpsnCounter(Empty) provisos (
        NumAlias#(16, nTestCnt),
        NumAlias#(TLog#(TAdd#(1, nTestCnt)), szTestCnt),
        Alias#(Bit#(szTestCnt), tTestCnt)
    );
    
    CpsnCounter#(OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE) dut <- mkCpsnCounter;


    Vector#(nTestCnt, Tuple2#(PSN, BitmapWindowStorageEntry#(OooWindowBitmap, PsnMergeWindowBoundary))) testTable = vec(
        tuple2(0, BitmapWindowStorageEntry{ data: 128'h0000_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 0}),
        tuple2(1, BitmapWindowStorageEntry{ data: 128'h0001_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 0}),
        tuple2(1, BitmapWindowStorageEntry{ data: 128'h0005_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 0}),
        tuple2(0, BitmapWindowStorageEntry{ data: 128'h0006_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 0}),
        tuple2(3, BitmapWindowStorageEntry{ data: 128'h0007_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 0}),
        tuple2(16, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 0}),
        tuple2(0, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: -1}),
        tuple2(32, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 1}),
        tuple2(48, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 2}),
        tuple2(64, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 3}),
        tuple2(80, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 4}),
        tuple2(96, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 5}),
        tuple2(112, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 6}),
        tuple2(128, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, leftBound: 7}),
        tuple2(0, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFF0, leftBound: 7}),
        tuple2(1, BitmapWindowStorageEntry{ data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFF5, leftBound: 7})
    );

    Reg#(tTestCnt) inputIdxReg <- mkReg(0);
    Reg#(tTestCnt) outputIdxReg <- mkReg(0);

    rule inject;
        if (inputIdxReg < fromInteger(valueOf(nTestCnt))) begin
            inputIdxReg <= inputIdxReg + 1;
            let ent = CpsnCounterReq {
                bitmapEntry: tpl_2(testTable[inputIdxReg])
            };
            dut.reqPipeIn.enq(tagged Valid ent);
        end
    endrule

    rule check;
        let resp = dut.respPipeOut.first;
        dut.respPipeOut.deq;

        outputIdxReg <= outputIdxReg + 1;

        immAssert(
            isValid(resp) && fromMaybe(?, resp) == tpl_1(testTable[outputIdxReg]),
            "mkTestCpsnCounter test failed",
            $format("input=", fshow(testTable[outputIdxReg]), ", result=", fshow(resp))
        );
        
        if (outputIdxReg == fromInteger(valueOf(nTestCnt)-1)) begin
            $display("PASS");
            $finish;
        end
    endrule
endmodule

(* doc = "testcase" *)
module mkTestMonoInrcNumberStorage(Empty) provisos (
        NumAlias#(22, nTestCnt),
        NumAlias#(TLog#(TAdd#(1, nTestCnt)), szTestCnt),
        Alias#(Bit#(szTestCnt), tTestCnt)
    );
    
    MonoInrcNumberStorage#(IndexQP, PSN) dutWithMaxLimit <- mkMonoInrcNumberStorage("init_bram_psn_incr_storage.bin", tagged Valid fromInteger(valueOf(OOO_WINDOW_SIZE) - 1));
    MonoInrcNumberStorage#(IndexQP, PSN) dutWithoutMaxLimit <- mkMonoInrcNumberStorage("init_bram_psn_incr_storage.bin", tagged Invalid);


    Vector#(nTestCnt, Tuple4#(PSN, PSN, PSN, Bool)) testTable = vec(
        tuple4(0, 0, 0, True),
        tuple4(1, 1, 1, True),
        tuple4(1, 1, 0, True),
        tuple4(5, 5, 5, False),
        tuple4(5, 5, 4, True),
        tuple4(6, 6, 6, False),
        tuple4(7, 7, 7, True),
        tuple4(8, 8, 8, False),
        tuple4(20, 20, 20, True),
        tuple4(20, 20, 16, False),
        tuple4(20, 20, 17, False),
        tuple4(20, 20, 18, False),
        tuple4(20, 20, 19, False),
        tuple4(128, 128, 128, True),
        tuple4(128, 128, 124, True),
        tuple4(128, 128, 125, True),
        tuple4(128, 128, 126, True),
        tuple4(128, 128, 127, True),
        tuple4(128, (1<<23)-1, (1<<23)-1, True),
        tuple4(128, (1<<23)+5, (1<<23)+5, False),
        tuple4(128, (1<<24)-10, (1<<24)-10, False),
        tuple4(128, 0, 0, True)
    );

    Reg#(tTestCnt) inputIdxReg <- mkReg(0);
    Reg#(tTestCnt) outputIdxReg <- mkReg(0);

    rule inject;
        if (inputIdxReg < fromInteger(valueOf(nTestCnt))) begin
            inputIdxReg <= inputIdxReg + 1;
            let {expectDataForNoLimitCkeck, expectDataForHasLimitCkeck, injectData, injectFirstChannel} = testTable[inputIdxReg];
            let ent = MonoInrcNumberStorageUpdateReq {
                rowAddr: 4,
                value: injectData
            };
            if (injectFirstChannel) begin
                dutWithMaxLimit.reqPipeInVec[0].enq(tagged Valid ent);
                dutWithMaxLimit.reqPipeInVec[1].enq(tagged Invalid);

                dutWithoutMaxLimit.reqPipeInVec[0].enq(tagged Valid ent);
                dutWithoutMaxLimit.reqPipeInVec[1].enq(tagged Invalid);
            end
            else begin
                dutWithMaxLimit.reqPipeInVec[0].enq(tagged Invalid);
                dutWithMaxLimit.reqPipeInVec[1].enq(tagged Valid ent);

                dutWithoutMaxLimit.reqPipeInVec[0].enq(tagged Invalid);
                dutWithoutMaxLimit.reqPipeInVec[1].enq(tagged Valid ent);
            end
        end
    endrule

    rule check;
        let respWithMaxLimitMaybe0 = dutWithMaxLimit.respPipeOutVec[0].first;
        dutWithMaxLimit.respPipeOutVec[0].deq;
        let respWithMaxLimitMaybe1 = dutWithMaxLimit.respPipeOutVec[1].first;
        dutWithMaxLimit.respPipeOutVec[1].deq;

        let respWithoutMaxLimitMaybe0 = dutWithoutMaxLimit.respPipeOutVec[0].first;
        dutWithoutMaxLimit.respPipeOutVec[0].deq;
        let respWithoutMaxLimitMaybe1 = dutWithoutMaxLimit.respPipeOutVec[1].first;
        dutWithoutMaxLimit.respPipeOutVec[1].deq;

        outputIdxReg <= outputIdxReg + 1;

        let {expectDataForHasLimitCkeck, expectDataForNoLimitCkeck, injectData, injectFirstChannel} = testTable[outputIdxReg];
        if (injectFirstChannel) begin
            let respWithMaxLimit = fromMaybe(?, respWithMaxLimitMaybe0);
            immAssert(
                respWithMaxLimit.newValue == expectDataForHasLimitCkeck && isValid(respWithMaxLimitMaybe0) && !isValid(respWithMaxLimitMaybe1),
                "mkTestMonoInrcNumberStorage test failed",
                $format("input=", fshow(testTable[outputIdxReg]), ", result=", fshow(respWithMaxLimit))
            );

            let respWithoutMaxLimit = fromMaybe(?, respWithoutMaxLimitMaybe0);
            immAssert(
                respWithoutMaxLimit.newValue == expectDataForNoLimitCkeck && isValid(respWithoutMaxLimitMaybe0) && !isValid(respWithoutMaxLimitMaybe1),
                "mkTestMonoInrcNumberStorage test failed",
                $format("input=", fshow(testTable[outputIdxReg]), ", result=", fshow(respWithoutMaxLimit))
            );
        end
        else begin
            let respWithMaxLimit = fromMaybe(?, respWithMaxLimitMaybe1);
            immAssert(
                respWithMaxLimit.newValue == expectDataForHasLimitCkeck && isValid(respWithMaxLimitMaybe1) && !isValid(respWithMaxLimitMaybe0),
                "mkTestMonoInrcNumberStorage test failed",
                $format("input=", fshow(testTable[outputIdxReg]), ", result=", fshow(respWithMaxLimit))
            );

            let respWithoutMaxLimit = fromMaybe(?, respWithoutMaxLimitMaybe1);
            immAssert(
                respWithoutMaxLimit.newValue == expectDataForNoLimitCkeck && isValid(respWithoutMaxLimitMaybe1) && !isValid(respWithoutMaxLimitMaybe0),
                "mkTestMonoInrcNumberStorage test failed",
                $format("input=", fshow(testTable[outputIdxReg]), ", result=", fshow(respWithoutMaxLimit))
            );
        end

        
        
        if (outputIdxReg == fromInteger(valueOf(nTestCnt)-1)) begin
            $display("PASS");
            $finish;
        end
    endrule
endmodule



(* doc = "testcase" *)
module mkTestMaxAckPsnCalculator(Empty) provisos (
        NumAlias#(24, nTestCnt),
        NumAlias#(TLog#(TAdd#(1, nTestCnt)), szTestCnt),
        Alias#(Bit#(szTestCnt), tTestCnt)
    );
    
    MaxAckPsnCalculator#(OooWindowBitmap, PsnMergeWindowBoundary) dut <- mkMaxAckPsnCalculator;


    Vector#(nTestCnt, Tuple2#(Maybe#(PSN), MaxAckPsnCalculatorReq#(OooWindowBitmap, PsnMergeWindowBoundary))) testTable = vec(
        tuple2(tagged Valid 0, MaxAckPsnCalculatorReq{cpsn: 0, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF}}),
        tuple2(tagged Valid 10, MaxAckPsnCalculatorReq{cpsn: 10, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF}}),
        tuple2(tagged Valid 1000, MaxAckPsnCalculatorReq{cpsn: 1000, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF}}),
        tuple2(tagged Invalid, MaxAckPsnCalculatorReq{cpsn: 0, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Invalid, MaxAckPsnCalculatorReq{cpsn: 10, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Invalid, MaxAckPsnCalculatorReq{cpsn: 1000, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Valid 0, MaxAckPsnCalculatorReq{cpsn: 0, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_0000_0000_0000_0000_0000_0000_0001}}),
        tuple2(tagged Valid 10, MaxAckPsnCalculatorReq{cpsn: 10, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_0000_0000_0000_0000_0000_0000_0001}}),
        tuple2(tagged Valid 1000, MaxAckPsnCalculatorReq{cpsn: 1000, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_0000_0000_0000_0000_0000_0000_0001}}),
        tuple2(tagged Invalid, MaxAckPsnCalculatorReq{cpsn: 0, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Invalid, MaxAckPsnCalculatorReq{cpsn: 10, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Invalid, MaxAckPsnCalculatorReq{cpsn: 1000, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0000_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Valid 0, MaxAckPsnCalculatorReq{cpsn: 0, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0001_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Valid 10, MaxAckPsnCalculatorReq{cpsn: 10, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0001_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Valid 1000, MaxAckPsnCalculatorReq{cpsn: 1000, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0001_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Invalid, MaxAckPsnCalculatorReq{cpsn: 0, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0002_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Valid 1, MaxAckPsnCalculatorReq{cpsn: 1, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0002_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Valid 2, MaxAckPsnCalculatorReq{cpsn: 2, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0002_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Valid 10, MaxAckPsnCalculatorReq{cpsn: 10, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0002_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Valid 1000, MaxAckPsnCalculatorReq{cpsn: 1000, needAckBitmap: BitmapWindowStorageEntry{leftBound: 0, data: 128'h0002_0000_0000_0000_0000_0000_0000_0000}}),
        tuple2(tagged Invalid, MaxAckPsnCalculatorReq{cpsn: 'h0F, needAckBitmap: BitmapWindowStorageEntry{leftBound: 8, data: 128'h0000_0000_0000_0000_0000_0000_0000_0001}}),
        tuple2(tagged Valid 'h10, MaxAckPsnCalculatorReq{cpsn: 'h10, needAckBitmap: BitmapWindowStorageEntry{leftBound: 8, data: 128'h0000_0000_0000_0000_0000_0000_0000_0001}}),
        tuple2(tagged Invalid, MaxAckPsnCalculatorReq{cpsn: 'h0F, needAckBitmap: BitmapWindowStorageEntry{leftBound: 8, data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF}}),
        tuple2(tagged Valid 'h10, MaxAckPsnCalculatorReq{cpsn: 'h10, needAckBitmap: BitmapWindowStorageEntry{leftBound: 8, data: 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF}})
    );

    Reg#(tTestCnt) inputIdxReg <- mkReg(0);
    Reg#(tTestCnt) outputIdxReg <- mkReg(0);

    rule inject;
        if (inputIdxReg < fromInteger(valueOf(nTestCnt))) begin
            inputIdxReg <= inputIdxReg + 1;
            let {expectData, injectData} = testTable[inputIdxReg];
            dut.reqPipeIn.enq(tagged Valid injectData);
        end
    endrule

    rule check;
        let respMaybe = dut.respPipeOut.first;
        dut.respPipeOut.deq;

        outputIdxReg <= outputIdxReg + 1;

        let {expectData, injectData} = testTable[outputIdxReg];
        immAssert(
            respMaybe == expectData,
            "mkTestMonoInrcNumberStorage test failed",
            $format("input=", fshow(testTable[outputIdxReg]), ", result=", fshow(respMaybe))
        );
        
        if (outputIdxReg == fromInteger(valueOf(nTestCnt)-1)) begin
            $display("PASS");
            $finish;
        end
    endrule
endmodule




(* doc = "testcase" *)
module mkTestBitmapWindowStorage(Empty);
 
    BitmapWindowStorage#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE) dut <- mkBitmapWindowStorage("init_bram_psn_merge_storage.bin");

    rule inject;
        dut.reqPipeInVec[0].enq(tagged Valid BitmapWindowStorageUpdateReq {
            rowAddr: 0,
            entry: BitmapWindowStorageEntry {
                data: 0,
                leftBound: 0
            }
        });
        dut.reqPipeInVec[1].enq(tagged Valid BitmapWindowStorageUpdateReq {
            rowAddr: 4,
            entry: BitmapWindowStorageEntry {
                data: 0,
                leftBound: 0
            }
        });
    endrule

    rule check;
        let resp1 = dut.respPipeOutVec[0].first;
        dut.respPipeOutVec[0].deq;
        let resp2 = dut.respPipeOutVec[1].first;
        dut.respPipeOutVec[1].deq;
    endrule
endmodule



interface TestBitmapWindowStorageTiming;
    method Bool getOutput;
endinterface

(* doc = "testcase" *)
module mkTestBitmapWindowStorageTiming(TestBitmapWindowStorageTiming);
 
    BitmapWindowStorage#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary, OOO_WINDOW_STRIDE) dut <- mkBitmapWindowStorage("init_bram_psn_merge_storage.bin");

    ForceKeepWideSignals#(Maybe#(BitmapWindowStorageUpdateResp#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary)), Bool) signalKeeperForResp1 <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Maybe#(BitmapWindowStorageUpdateResp#(IndexQP, OooWindowBitmap, PsnMergeWindowBoundary)), Bool) signalKeeperForResp2 <- mkForceKeepWideSignals; 
    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);

    Reg#(Bool) outReg <- mkRegU;
    rule injectData;
        let rndData <- randSource1.get;
        dut.reqPipeInVec[0].enq(unpack(truncate(rndData)));
        dut.reqPipeInVec[1].enq(unpack(truncate(rndData[511:256])));
        if (rndData[20] == 1) begin
            dut.resetReqPipeIn.enq(unpack(truncate(rndData[100: 10])));
        end
    endrule

    rule getResp;
        let resp1 = dut.respPipeOutVec[0].first;
        dut.respPipeOutVec[0].deq;
        let resp2 = dut.respPipeOutVec[1].first;
        dut.respPipeOutVec[1].deq;

        signalKeeperForResp1.bitsPipeIn.enq(resp1);
        signalKeeperForResp2.bitsPipeIn.enq(resp2);
    endrule

    rule getResetResp;
        dut.resetRespPipeOut.deq;
    endrule

    rule gatherKeptSignals;
        outReg <= signalKeeperForResp1.out && signalKeeperForResp2.out;
    endrule

    method getOutput = outReg;
endmodule