import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import AddressChunker :: *;
import PayloadGenAndCon :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;
import NapWrapper :: *;
import StreamShifter :: *;


typedef enum {
    TestPayloadGenAndConStateGenWriteReq = 0,
    TestPayloadGenAndConStateWaitWriteFinish = 1,
    TestPayloadGenAndConStateCheckReadResp = 2
} TestPayloadGenAndConState deriving(FShow, Bits, Eq);

(* doc = "testcase" *)
module mkTestPayloadGenAndCon(Empty);

    Reg#(Bit#(32)) quitCounterReg <- mkReg(1000000);

    PayloadGenAndCon dut <- mkPayloadGenAndCon;

    let payloadStreamGen <- mkFixedLengthDateStreamRandomGen;
    let writeStreamShifter <- mkBiDirectionStreamShifter;
    mkConnection(payloadStreamGen.streamPipeOut, writeStreamShifter.streamPipeIn);

    FIFOF#(PayloadGenReq) payloadGenReqQ <- mkFIFOF;
    FIFOF#(DataStream) expectedStreamQ <- mkSizedFIFOF(1024);

    Vector#(2, PipeOut#(DataStream)) rdmaPayloadDataStreamPipeOutForkedVec <- mkForkVector(writeStreamShifter.streamPipeOut);
    mkConnection(rdmaPayloadDataStreamPipeOutForkedVec[0], dut.payloadConStreamPipeIn);
    mkConnection(rdmaPayloadDataStreamPipeOutForkedVec[1], toPipeIn(expectedStreamQ));

    PipeOut#(Length) payloadLenRandPipeOut <- mkRandomLenPipeOut(1, 2048);//fromInteger(valueOf(MAX_PMTU)));
    PipeOut#(Length)   payloadAddrRandPipeOut <- mkRandomLenPipeOut(0, 1 << (valueOf(MOCK_HOST_ADDR_WIDTH)-1) );


    Reg#(TestPayloadGenAndConState) stateReg <- mkReg(TestPayloadGenAndConStateGenWriteReq);




    rule genWriteReq if (stateReg == TestPayloadGenAndConStateGenWriteReq);
       
        let rdmaPayloadLen = payloadLenRandPipeOut.first;
        payloadLenRandPipeOut.deq;

        ADDR rdmaPayloadStartAddr = zeroExtend(payloadAddrRandPipeOut.first);
        payloadAddrRandPipeOut.deq;


        payloadStreamGen.reqPipeIn.enq(zeroExtend(rdmaPayloadLen));

        ByteIndexInBeat startByteOffset = truncate(rdmaPayloadStartAddr);
        DataBusSignedShiftOffset signedShiftOffset = zeroExtend(startByteOffset);
        writeStreamShifter.offsetPipeIn.enq(signedShiftOffset);

        let conReq = PayloadConReq{
            addr: rdmaPayloadStartAddr,
            len: rdmaPayloadLen
        };
        dut.conReqPipeIn.enq(conReq);


        let genReq = PayloadGenReq{
            addr: rdmaPayloadStartAddr,
            len: rdmaPayloadLen
        };
        payloadGenReqQ.enq(genReq);

        stateReg <= TestPayloadGenAndConStateWaitWriteFinish;
    endrule

    rule waitWriteFinished if (stateReg == TestPayloadGenAndConStateWaitWriteFinish);
        let writeFinishResp = dut.conRespPipeOut.first;
        dut.conRespPipeOut.deq;
        immAssert(
            writeFinishResp,
            "writeFinishResp should be True, which means no error occured",
            $format("")
        );

        let genReq = payloadGenReqQ.first;
        payloadGenReqQ.deq;
        dut.genReqPipeIn.enq(genReq);

        stateReg <= TestPayloadGenAndConStateCheckReadResp;
    endrule

    rule checkReadResp if (stateReg == TestPayloadGenAndConStateCheckReadResp);
        let ds = dut.payloadGenStreamPipeOut.first;
        dut.payloadGenStreamPipeOut.deq;

        let expectedDs = expectedStreamQ.first;
        expectedStreamQ.deq;

        // mask out non-valid bytes.
        if (ds.isFirst) begin
            // only first beat is right aligned.
            BusBitNum shiftOffset = zeroExtend(ds.startByteIdx) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
            DATA maskForStartByteIdx = ~((1 << shiftOffset) - 1);

            shiftOffset = (zeroExtend(ds.startByteIdx) + zeroExtend(ds.byteNum)) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
            DATA maskForByteNum = (1 << shiftOffset) - 1;

            ds.data = ds.data & maskForStartByteIdx & maskForByteNum;
        end
        else if (ds.isLast) begin
            BusBitNum shiftOffset = zeroExtend(ds.byteNum) << valueOf(BIT_BYTE_CONVERT_SHIFT_NUM);
            DATA maskForByteNum = ~((-1) >> shiftOffset);
            ds.data = ds.data & maskForByteNum;
        end
        

        immAssert(
            ds == expectedDs,
            "read datastream not match write datastream",
            $format("ds=", fshow(ds), ", expectedDs=", fshow(expectedDs))
        );

        if (ds.isLast) begin
            stateReg <= TestPayloadGenAndConStateGenWriteReq;

            quitCounterReg <= quitCounterReg - 1;
            if (quitCounterReg % 50000 == 0) begin
                $display(quitCounterReg);
            end
            if (quitCounterReg == 0) begin
                $display("PASS");
                $finish;
            end
        end
    endrule
endmodule



interface TestPayloadGenAndConTiming;
    method Bool getOutput;
endinterface


(* doc = "testcase" *)
module mkTestPayloadGenAndConTiming(TestPayloadGenAndConTiming);

    PayloadGenAndCon dut <- mkPayloadGenAndCon;
    ForceKeepWideSignals#(DataStream) signalKeeperForGen <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bool) signalKeeperForCon <- mkForceKeepWideSignals; 
    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    Reg#(Bool) outReg <- mkRegU;

    rule genWriteReq;
        
        let randData512 <- randSource1.get;

        Length rdmaPayloadLen = truncate(randData512 >> 2);
        ADDR rdmaPayloadStartAddr = truncate(randData512 >> 12);

        let conReq = PayloadConReq{
            addr: rdmaPayloadStartAddr,
            len: rdmaPayloadLen
        };
        dut.conReqPipeIn.enq(conReq);


        let genReq = PayloadGenReq{
            addr: rdmaPayloadStartAddr,
            len: rdmaPayloadLen
        };
        dut.genReqPipeIn.enq(genReq);

    endrule

    rule genWriteData;
        let randData512 <- randSource2.get;
        dut.payloadConStreamPipeIn.enq(unpack(truncate(randData512)));
    endrule

    rule getConResult;
        let writeFinishResp = dut.conRespPipeOut.first;
        dut.conRespPipeOut.deq;
        signalKeeperForCon.bitsPipeIn.enq(writeFinishResp);
    endrule

    rule getGenResult;
        let ds = dut.payloadGenStreamPipeOut.first;
        dut.payloadGenStreamPipeOut.deq;
        signalKeeperForGen.bitsPipeIn.enq(ds);
    endrule

    rule gatherKeptSignals;
        outReg <= signalKeeperForCon.out && signalKeeperForGen.out;
    endrule

    method getOutput = outReg;
endmodule

