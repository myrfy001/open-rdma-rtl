import Connectable :: *;
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

import Ringbuf :: *;


(* doc = "testcase" *)
module mkTestRingbuf(Empty);
    Reg#(Long) exitCounterReg <- mkReg(10000000);

    let ringbufDmaNapWrappr <- mkRingbufDmaNapWrappr;

    RingbufC2hSlot4096 dutC2H <- mkRingbufC2h(0);
    let dutH2C <- mkRingbufH2c(0, 8);

    mkConnection(dutC2H.dmaWriteReqPipeOut, ringbufDmaNapWrappr.dmaWriteReqPipeIn);
    mkConnection(dutC2H.dmaWriteDataPipeOut, ringbufDmaNapWrappr.dmaWriteDataPipeIn);
    mkConnection(dutC2H.dmaWriteRespPipeIn, ringbufDmaNapWrappr.dmaWriteRespPipeOut);
    mkConnection(dutH2C.dmaReadReqPipeOut, ringbufDmaNapWrappr.dmaReadReqPipeIn);
    mkConnection(dutH2C.dmaReadRespPipeIn, ringbufDmaNapWrappr.dmaReadRespPipeOut);


    let burstWriteCntRaandVec = vec(0, 0, 0, 1, 2, 3);
    let burstReadCntRaandVec = vec(0, 1, 3, 0, 2, 0);
    PipeOut#(Length) c2hWriteCountRandPipeOut <- mkRandomItemFromVec(burstWriteCntRaandVec);
    PipeOut#(Length) writePointerSyncDelayRandPipeOut <- mkRandomLenPipeOut(3, 99);
    PipeOut#(Length) readPointerSyncDelayRandPipeOut <- mkRandomLenPipeOut(2, 100);

    PipeOut#(Length) h2cReadDelayRandPipeOut <- mkRandomItemFromVec(burstReadCntRaandVec);

    Reg#(Bool)      isInitReg <- mkReg(True);
    Reg#(Long)      c2hBatchWriteCounterReg <- mkReg(0);
    Reg#(Long)      writerSeqReg <- mkReg(0);
    Reg#(Long)      readerSeqReg <- mkReg(0);

    Reg#(Long)      writeSyncDelayCounterReg <- mkReg(0);
    Reg#(Long)      readSyncDelayCounterReg <- mkReg(0);
    Reg#(Long)      readDelayCntReg <- mkReg(0);

    Reg#(Long)      h2cEmptyCountReg <- mkReg(0);
    Reg#(Long)      h2cFullCountReg <- mkReg(0);
    Reg#(Long)      c2hEmptyCountReg <- mkReg(0);
    Reg#(Long)      c2hFullCountReg <- mkReg(0);

    Reg#(Bool)      h2cLastNotFullReg <- mkReg(True);
    Reg#(Bool)      h2cLastNotEmptyReg <- mkReg(False);
    Reg#(Bool)      c2hLastNotFullReg <- mkReg(True);
    Reg#(Bool)      c2hLastNotEmptyReg <- mkReg(False);


    rule doStateChangeCounter;
        let newH2cNotFull = isRingbufNotFull(dutH2C.controlRegs.head, dutH2C.controlRegs.tail);
        let newH2cNotEmpty = isRingbufNotEmpty(dutH2C.controlRegs.head, dutH2C.controlRegs.tail);
        let newC2hNotFull = isRingbufNotFull(dutC2H.controlRegs.head, dutC2H.controlRegs.tail);
        let newC2hNotEmpty = isRingbufNotEmpty(dutC2H.controlRegs.head, dutC2H.controlRegs.tail);
        

        h2cLastNotFullReg <= newH2cNotFull;
        h2cLastNotEmptyReg <= newH2cNotEmpty;
        c2hLastNotFullReg <= newC2hNotFull;
        c2hLastNotEmptyReg <= newC2hNotEmpty;

        if (h2cLastNotFullReg != newH2cNotFull) begin
            h2cFullCountReg <= h2cFullCountReg + 1;
            $display(
                "h2cFullCountReg=", fshow(h2cFullCountReg),
                ", h2cEmptyCountReg=", fshow(h2cEmptyCountReg),
                ", c2hFullCountReg=", fshow(c2hFullCountReg),
                ", c2hEmptyCountReg=", fshow(c2hEmptyCountReg)
            );
        end

        if (h2cLastNotEmptyReg != newH2cNotEmpty) begin
            h2cEmptyCountReg <= h2cEmptyCountReg + 1;
            $display(
                "h2cFullCountReg=", fshow(h2cFullCountReg),
                ", h2cEmptyCountReg=", fshow(h2cEmptyCountReg),
                ", c2hFullCountReg=", fshow(c2hFullCountReg),
                ", c2hEmptyCountReg=", fshow(c2hEmptyCountReg)
            );
        end

        if (c2hLastNotFullReg != newC2hNotFull) begin
            c2hFullCountReg <= c2hFullCountReg + 1;
            $display(
                "h2cFullCountReg=", fshow(h2cFullCountReg),
                ", h2cEmptyCountReg=", fshow(h2cEmptyCountReg),
                ", c2hFullCountReg=", fshow(c2hFullCountReg),
                ", c2hEmptyCountReg=", fshow(c2hEmptyCountReg)
            );
        end

        if (c2hLastNotEmptyReg != newC2hNotEmpty) begin
            c2hEmptyCountReg <= c2hEmptyCountReg + 1;
            $display(
                "h2cFullCountReg=", fshow(h2cFullCountReg),
                ", h2cEmptyCountReg=", fshow(h2cEmptyCountReg),
                ", c2hFullCountReg=", fshow(c2hFullCountReg),
                ", c2hEmptyCountReg=", fshow(c2hEmptyCountReg)
            );
        end
    endrule


    rule doInit if (isInitReg);
        isInitReg <= False;
        dutC2H.controlRegs.addr <= 0;
        dutH2C.controlRegs.addr <= 0;

        dutC2H.controlRegs.head <= 0;
        dutH2C.controlRegs.head <= 0;

        dutC2H.controlRegs.tail <= 0;
        dutH2C.controlRegs.tail <= 0;
    endrule

    rule doInjectC2HWrite if (!isInitReg);
        if (c2hBatchWriteCounterReg == 0) begin
            c2hBatchWriteCounterReg <= zeroExtend(c2hWriteCountRandPipeOut.first);
            c2hWriteCountRandPipeOut.deq;
        end
        else begin
            c2hBatchWriteCounterReg <= c2hBatchWriteCounterReg - 1;
            writerSeqReg <= writerSeqReg + 1;
            dutC2H.descPipeIn.enq(unpack({pack(writerSeqReg), pack(writerSeqReg), pack(writerSeqReg), pack(writerSeqReg)}));
        end
    endrule

    rule syncPointerBetweenWriterAndReader if (!isInitReg);

        if (writeSyncDelayCounterReg == 0) begin
            dutH2C.controlRegs.head <= dutC2H.controlRegs.head;
            writeSyncDelayCounterReg <= zeroExtend(writePointerSyncDelayRandPipeOut.first);
            writePointerSyncDelayRandPipeOut.deq;
        end
        else begin
            writeSyncDelayCounterReg <= writeSyncDelayCounterReg - 1;
        end

        if (readSyncDelayCounterReg == 0) begin
            dutC2H.controlRegs.tail <= dutH2C.controlRegs.tail;
            readSyncDelayCounterReg <= zeroExtend(readPointerSyncDelayRandPipeOut.first);
            readPointerSyncDelayRandPipeOut.deq;
        end
        else begin
            readSyncDelayCounterReg <= readSyncDelayCounterReg - 1;
        end

        // if (syncDelayCounterReg == 0) begin
        //     dutH2C.controlRegs.head <= dutC2H.controlRegs.head;
        //     dutC2H.controlRegs.tail <= dutH2C.controlRegs.tail;

        //     let randVal = pointerSyncDelayRandPipeOut.first;
        //     pointerSyncDelayRandPipeOut.deq;

        //     // The logic is:
        //     // we need to test the case when ringbuf is Full or empty, so we should generate some
        //     // case that the read or write is paused long enough to  make the ringbuf full or empty
        //     // if the random value is a certain trigger value (with the probablity of 1/100000), the prcess 
        //     // will be delayed for a long period.
        //     if (randVal == 20000) begin
        //         pointerSyncLongDelayCntReg <= pointerSyncLongDelayCntReg + 1;
        //         syncDelayCounterReg <= 20000;
        //     end
        //     else begin
        //         syncDelayCounterReg <= zeroExtend(randVal[2:0]);
        //     end
        // end
        // else begin
        //     syncDelayCounterReg <= syncDelayCounterReg - 1;
        // end
        // $display(
        //     "dutC2H.controlRegs.head=", fshow(pack(dutC2H.controlRegs.head)), 
        //     ", dutH2C.controlRegs.head=", fshow(pack(dutH2C.controlRegs.head)), 
        //     ", dutH2C.controlRegs.tail=", fshow(pack(dutH2C.controlRegs.head)), 
        //     ", dutC2H.controlRegs.tail=", fshow(pack(dutC2H.controlRegs.tail))
        // );
    endrule

    rule doReadCheck if (!isInitReg);

        if (readDelayCntReg == 0) begin
            readDelayCntReg <= zeroExtend(h2cReadDelayRandPipeOut.first);
            h2cReadDelayRandPipeOut.deq;
        end
        else begin
            readDelayCntReg <= readDelayCntReg - 1;

            let readout = dutH2C.descPipeOut.first;
            dutH2C.descPipeOut.deq;
            readerSeqReg <= readerSeqReg + 1;

            let expected = {pack(readerSeqReg), pack(readerSeqReg), pack(readerSeqReg), pack(readerSeqReg)};

            immAssert(
                pack(readout) == expected,
                "mkTestRingbuf doReadCheck failed",
                $format("got=", fshow(readout), ", expected=", fshow(expected))
            );

            exitCounterReg <= exitCounterReg - 1;
            if (exitCounterReg == 0) begin
                $display("PASS");
                $finish;
            end
            if (exitCounterReg % 10000 == 0) begin
                $display(exitCounterReg);
            end
        end
    endrule

endmodule