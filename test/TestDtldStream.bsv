import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;
import StmtFSM :: * ;

import Utils4Test :: *;

import PrimUtils :: *;
import RdmaUtils :: *;
import Utils4Test :: *;
import EthernetTypes :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ConnectableF :: *;
import DtldStream :: *;


interface TestDtldStreamConcatorTimingTest;
    method Bit#(128) getOutput;
endinterface

(* synthesize *)
module mkTestDtldStreamConcatorTimingTest(TestDtldStreamConcatorTimingTest);
    Reg#(Bit#(128)) outReg <- mkReg(0);
    Reg#(Bit#(10)) stepCounterReg <- mkReg(0);
    Reg#(Bit#(2))  rotReg <- mkReg(0);


    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);

    ForceKeepWideSignals#(Bit#(512), Bit#(128)) signalKeeper          <- mkForceKeepWideSignals; 

    DtldStreamConcator#(DATA, NUMERIC_TYPE_TWO) dut <- mkDtldStreamConcator;

    rule test;
        let randValue1 <- randSource1.get;
        
        dut.dataPipeIn.enq(unpack(truncate(randValue1)));
        dut.isLastStreamFlagPipeIn.enq(unpack(truncateLSB(randValue1)));
    endrule



    rule handleOutput;
        let out = dut.dataPipeOut.first;
        dut.dataPipeOut.deq;

        signalKeeper.bitsPipeIn.enq(zeroExtend(pack(out)));
        outReg <= zeroExtend({signalKeeper.out});
    endrule

    method getOutput = outReg;
endmodule




typedef Bit#(10) SpliterSubStreamAlignBlockCnt;

interface TestDtldStreamSpliterTimingTest;
    method Bit#(128) getOutput;
endinterface

(* synthesize *)
module mkTestDtldStreamSpliterTimingTest(TestDtldStreamSpliterTimingTest);
    Reg#(Bit#(128)) outReg <- mkReg(0);
    Reg#(Bit#(10)) stepCounterReg <- mkReg(0);
    Reg#(Bit#(2))  rotReg <- mkReg(0);


    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);

    ForceKeepWideSignals#(Bit#(512), Bit#(128)) signalKeeper          <- mkForceKeepWideSignals; 

    DtldStreamSplitor#(DATA, SpliterSubStreamAlignBlockCnt, NUMERIC_TYPE_TWO) dut <- mkDtldStreamSplitor;

    rule test;
        let randValue1 <- randSource1.get;
        
        dut.dataPipeIn.enq(unpack(truncate(randValue1)));
        dut.streamAlignBlockCountPipeIn.enq(unpack(truncateLSB(randValue1)));
    endrule



    rule handleOutput;
        let out = dut.dataPipeOut.first;
        dut.dataPipeOut.deq;

        signalKeeper.bitsPipeIn.enq(zeroExtend(pack(out)));
        outReg <= zeroExtend({signalKeeper.out});
    endrule

    method getOutput = outReg;
endmodule



module mkTestDtldStreamSpliterAndConcator(Empty);
   
    Reg#(Bool) genNewTestReg <- mkReg(True);
    Reg#(Bool) runCheckerReg[2] <- mkCReg(2, False);


    DtldStreamConcator#(DATA, NUMERIC_TYPE_TWO) concator <- mkDtldStreamConcator;
    DtldStreamSplitor#(DATA, SpliterSubStreamAlignBlockCnt, NUMERIC_TYPE_TWO) splitor <- mkDtldStreamSplitor;

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);

    let originStreamTotalByteNumRandomGenPipeOut <- mkRandomLenPipeOut(1, 192);
    let originStreamStartByteIdxRandomGenPipeOut <- mkRandomLenPipeOut(0,3);
    let splitFirstStreamAlignBlockCntRandomGenPipeOut <- mkRandomLenPipeOut(1,24);
    let splitOtherStreamAlignBlockCntRandomGenPipeOut <- mkRandomLenPipeOut(8,24);

    Reg#(Length) targetOriginDsTotalByteNumReg <- mkRegU;
    Reg#(Length) targetOriginDsStartByteIdxReg <- mkRegU;
    Reg#(Length) curOriginDsTotalByteNumReg <- mkRegU;
    Reg#(Bool)   originDsIsFirstReg <- mkReg(True);

    Reg#(Length) leftAlignBlockCntForSubDsReg <- mkReg(0);
    Reg#(Bool)   firstSubDsLenHasSelectedReg <- mkReg(False);

    

    FIFOF#(DtldStreamData#(DATA)) originDsQueue <- mkSizedFIFOF(100);
    FIFOF#(Tuple2#(Length, Length)) originDsInfoQueue <- mkSizedFIFOF(100);
    FIFOF#(Tuple2#(SpliterSubStreamAlignBlockCnt, Bool)) splitAlignBlockCntQueue <- mkSizedFIFOF(100);

    FIFOF#(DtldStreamData#(DATA)) checkerExpectedDsQueue <- mkSizedFIFOF(100);

    // mkConnection(splitor.dataPipeOut, concator.dataPipeIn);


    function DtldStreamData#(DATA) maskOutUnusedBytes(DtldStreamData#(DATA) dsIn);
        DATA mask = -1;
        BusBitNum shiftCnt = zeroExtend(dsIn.startByteIdx) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
        mask = mask >> (shiftCnt);
        mask = mask << (shiftCnt);

        if (dsIn.isLast) begin
            ByteEnBitNum emptyByteCntAtTail = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - dsIn.byteNum - zeroExtend(dsIn.startByteIdx);
            shiftCnt = zeroExtend(emptyByteCntAtTail) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
            mask = mask << shiftCnt;
            mask = mask >> shiftCnt;
        end

        dsIn.data = dsIn.data & mask;
        return dsIn;
    endfunction


    rule connectSplitorAndConcator;
        splitor.dataPipeOut.deq;
        concator.dataPipeIn.enq(splitor.dataPipeOut.first);
        $display("froward from S to C: ds=", fshow(splitor.dataPipeOut.first));
    endrule
    
    rule forkOriginDsToCheckerAndDut;
        let ds = originDsQueue.first;
        originDsQueue.deq;
        splitor.dataPipeIn.enq(ds);
        checkerExpectedDsQueue.enq(ds);

        $display("original DS: ds=", fshow(ds));
    endrule

    rule forkOriginDsMetaToCheckerAndDut;
        let {subDsAlignCnt, isSubDsLast} = splitAlignBlockCntQueue.first;
        splitAlignBlockCntQueue.deq;
        splitor.streamAlignBlockCountPipeIn.enq(subDsAlignCnt);
        concator.isLastStreamFlagPipeIn.enq(isSubDsLast);
        $display("split plan: subDsAlignCnt=", fshow(subDsAlignCnt), ", isSubDsLast=", fshow(isSubDsLast));
    endrule

    rule checkOutput if (runCheckerReg[1]);
        let expectedDs = checkerExpectedDsQueue.first;
        checkerExpectedDsQueue.deq;

        let gotDs = concator.dataPipeOut.first;
        concator.dataPipeOut.deq;



        if (expectedDs.isLast) begin
            runCheckerReg[1] <= False;
        end

        // $display("expectedDs=", fshow(expectedDs));
        // $display("     gotDs=", fshow(gotDs));

        expectedDs = maskOutUnusedBytes(expectedDs);
        gotDs = maskOutUnusedBytes(gotDs);
        $display("time=%t", $time);
        $display("masked expectedDs=", fshow(expectedDs));
        $display("     masked gotDs=", fshow(gotDs));

        immAssert(
            pack(expectedDs) == pack(gotDs),
            "not match",
            $format("")
        );
    endrule

    Stmt genOriginStream = (seq
        action
            targetOriginDsTotalByteNumReg <= originStreamTotalByteNumRandomGenPipeOut.first;
            originStreamTotalByteNumRandomGenPipeOut.deq;

            targetOriginDsStartByteIdxReg <= originStreamStartByteIdxRandomGenPipeOut.first;
            originStreamStartByteIdxRandomGenPipeOut.deq;

            curOriginDsTotalByteNumReg <= 0;

            originDsInfoQueue.enq(tuple2(originStreamTotalByteNumRandomGenPipeOut.first, originStreamStartByteIdxRandomGenPipeOut.first));
            $display("originDsInfoQueue.enq");
        endaction

        while (curOriginDsTotalByteNumReg != targetOriginDsTotalByteNumReg)
        seq
            action

                ByteEnBitNum byteCntCanHoldInThisBeat = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH)) - truncate(targetOriginDsStartByteIdxReg);

                let isFirst = originDsIsFirstReg;
                let isLast = (targetOriginDsTotalByteNumReg - curOriginDsTotalByteNumReg <= fromInteger(valueOf(DATA_BUS_BYTE_WIDTH))) && (truncate(targetOriginDsTotalByteNumReg - curOriginDsTotalByteNumReg) <= byteCntCanHoldInThisBeat);
                originDsIsFirstReg <= isLast;
                targetOriginDsStartByteIdxReg <= 0;

                // $display("targetOriginDsStartByteIdxReg=", fshow(targetOriginDsStartByteIdxReg), ", curOriginDsTotalByteNumReg=", fshow(curOriginDsTotalByteNumReg), ", targetOriginDsTotalByteNumReg=", fshow(targetOriginDsTotalByteNumReg));
                ByteEnBitNum byteNum;
                ByteIndexInBeat    startByteIdx;

                if (isFirst && isLast) begin
                    byteNum = truncate(targetOriginDsTotalByteNumReg);
                    startByteIdx = truncate(targetOriginDsStartByteIdxReg);
                end
                else if (isFirst) begin
                    byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
                    byteNum = byteNum - truncate(targetOriginDsStartByteIdxReg);
                    startByteIdx = truncate(targetOriginDsStartByteIdxReg);
                end
                else if (isLast) begin
                    byteNum = truncate(targetOriginDsTotalByteNumReg - curOriginDsTotalByteNumReg);
                    startByteIdx = 0;
                end
                else begin
                    byteNum = fromInteger(valueOf(DATA_BUS_BYTE_WIDTH));
                    startByteIdx = 0;
                end

                let tmpData <- randSource1.get;
                let ds = DtldStreamData {
                    data: truncate(tmpData),
                    byteNum: byteNum,
                    startByteIdx: startByteIdx,
                    isFirst: isFirst,
                    isLast: isLast
                };
                originDsQueue.enq(ds);

                curOriginDsTotalByteNumReg <= curOriginDsTotalByteNumReg + zeroExtend(byteNum);
                
            endaction
        endseq
    endseq);


    Stmt splitMetaGen = (seq
        while (!firstSubDsLenHasSelectedReg)
        seq
            action
                if (originDsInfoQueue.notFull) begin
                    let {originDsLen, startIdx} = originDsInfoQueue.first;
                    let firstStreamAlignBlockCnt = splitFirstStreamAlignBlockCntRandomGenPipeOut.first;
                    splitFirstStreamAlignBlockCntRandomGenPipeOut.deq;
                    let originDsALignBlockCnt = ((originDsLen + startIdx - 1) >> valueOf(NUMERIC_TYPE_TWO)) + 1;
                    if (firstStreamAlignBlockCnt <= originDsALignBlockCnt) begin
                        $display("org ds meta = ", fshow(originDsInfoQueue.first));
                        $display("originDsInfoQueue.deq");
                        originDsInfoQueue.deq;
                        let isLastSubDs = firstStreamAlignBlockCnt == originDsALignBlockCnt;
                        splitAlignBlockCntQueue.enq(tuple2(truncate(firstStreamAlignBlockCnt), isLastSubDs));
                        leftAlignBlockCntForSubDsReg <= originDsALignBlockCnt - firstStreamAlignBlockCnt;
                        firstSubDsLenHasSelectedReg <= True;
                    end
                end
            endaction
        endseq

        firstSubDsLenHasSelectedReg <= False;

        while (leftAlignBlockCntForSubDsReg != 0)
        seq
            action
                if (leftAlignBlockCntForSubDsReg >= 8) begin
                    // let otherStreamAlignBlockCnt = splitOtherStreamAlignBlockCntRandomGenPipeOut.first;
                    // splitOtherStreamAlignBlockCntRandomGenPipeOut.deq;

                    let t = splitOtherStreamAlignBlockCntRandomGenPipeOut.first;
                    splitOtherStreamAlignBlockCntRandomGenPipeOut.deq;

                    Length otherStreamAlignBlockCnt = 8 * (1 + zeroExtend(pack(t)[1:0]));


                    if (otherStreamAlignBlockCnt > leftAlignBlockCntForSubDsReg) begin
                        // nothing to do
                    end
                    else begin
                        let isLastSubDs = leftAlignBlockCntForSubDsReg == otherStreamAlignBlockCnt;
                        splitAlignBlockCntQueue.enq(tuple2(truncate(otherStreamAlignBlockCnt), isLastSubDs));
                        leftAlignBlockCntForSubDsReg <= leftAlignBlockCntForSubDsReg - otherStreamAlignBlockCnt;
                    end
                end
                else begin
                    splitAlignBlockCntQueue.enq(tuple2(truncate(leftAlignBlockCntForSubDsReg), True));
                    leftAlignBlockCntForSubDsReg <= 0;
                end
            endaction
        endseq
    endseq);




    FSM originDsGenFSM <- mkFSM(genOriginStream);
    FSM genSplitMetaFSM  <- mkFSM(splitMetaGen);


    Stmt runTest = (seq
        action
            $display("======================================================");
            $display("=====================New Stream=======================");
            $display("======================================================");
            originDsGenFSM.start;
            genSplitMetaFSM.start;
        endaction
        await(originDsGenFSM.done && genSplitMetaFSM.done);
        runCheckerReg[0] <= True;
        await(!runCheckerReg[0]);
    endseq);

    FSM runTestFSM  <- mkFSM(runTest);
    
    // rule debug;
    //     $display(fshow(originDsGenFSM.done), " ", fshow(genSplitMetaFSM.done), " ", fshow(originDsInfoQueue.notEmpty), " ", fshow(splitAlignBlockCntQueue.notFull));
    // endrule

    rule runTestRule;
        runTestFSM.start;
    endrule
endmodule