import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import RTilePcieAdaptor :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;

import PcieTypes :: *;
import StreamShifterG :: *;
import DtldStream :: *;

`include "PcieMacros.bsv"

(* doc = "testcase" *)
module mkTestRTilePcieAdaptorRx(Empty);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);

    let dut <- mkRTilePcie;

    Reg#(Bool) runReg <- mkReg(True);
    rule injectTlp if (runReg);
        runReg <= False;

        // Vector#(128, Byte) dataVec = map(fromInteger, genVector);
        // let data = unpack(pack(dataVec));

        PcieTlpDataBusSegBundle data = vec(
            'h00FFEEDD_CCBBAA00,
            0,
            0,
            0
        );

        PcieTlpHeaderCommon common_header1 = unpack(0);
        common_header1.fmt = `PCIE_TLP_HEADER_FMT_3DW_WITH_DATA;
        common_header1.typ = `PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA;
        common_header1.length = 2;
        common_header1.t8 = True;
        common_header1.t9 = False;

        PcieTlpHeaderCompletion cplt1 = unpack(0);
        cplt1.commonHeader = common_header1;
        cplt1.byteCount = 6;
        cplt1.tag = 'h01;
        cplt1.lowerAddress = 7'd125;
        
        PcieTlpHeaderBuffer headerBuf1 = zeroExtendLSB(pack(cplt1));
        PcieTlpHeaderBusSegBundle header = vec(
            headerBuf1,
            0,
            0,
            0
        );

        let beat = PcieRxBeat {
            data: data,
            header: header,
            sop: 'b0001,
            eop: 'b0001,
            hvalid: 'b0001,
            dvalid: 'b0001,
            bar: unpack(0),
            empty: ?
        };

        dut.pcieRxPipeIn.enq(beat);
    endrule
endmodule


(* doc = "testcase" *)
module mkTestRTilePcieAdaptorTx(Empty);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);

    let dut <- mkRTilePcie;

    Reg#(Bool) runReg <- mkReg(True);
    rule injectReadTlp if (runReg);
        runReg <= False;

        let writeMeta = DtldStreamMemAccessMeta {
            addr: 0,
            totalLen: 15
        };
        let writeData = DtldStreamData {
            data: ?,
            startByteIdx: 0,
            byteNum: 15,
            isFirst: True,
            isLast: True
        };
        dut.streamSlaveIfcVec[0].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        dut.streamSlaveIfcVec[0].writePipeIfc.writeDataPipeIn.enq(writeData);
    endrule

    rule getOutput;
        let outBeat = dut.pcieTxPipeOut.first;
        dut.pcieTxPipeOut.deq;
        $display(fshow(outBeat));
    endrule
endmodule

interface TestExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStreamTimingTest;
    method Bool getOutput;
endinterface

// (* doc = "testcase" *)
// (* synthesize *)
// module mkTestExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStreamTimingTest(TestExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStreamTimingTest);
//     Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);

//     ExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStream#(PcieDataStreamDataLsbRight) dut <- mkExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStream;

//     ForceKeepWideSignals#(PcieDataStreamLsbRight, Bool) signalKeeperForStream <- mkForceKeepWideSignals; 
//     ForceKeepWideSignals#(PcieLengthAndByteEn, Bool) signalKeeperForMeta <- mkForceKeepWideSignals; 
    

//     let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
//     let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
//     let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
//     let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
//     let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
//     let randSource6 <- mkSynthesizableRng512('h11111111);

//     Reg#(Bool) runReg <- mkReg(True);
//     Reg#(Bool) outReg <- mkReg(True);
//     rule injectTlp if (runReg);
//         runReg <= False;

//         let randValue1 <- randSource1.get;
//         let randValue2 <- randSource2.get;
//         let randValue3 <- randSource3.get;
//         let randValue4 <- randSource4.get;
//         let randValue5 <- randSource5.get;
//         let randValue6 <- randSource6.get;

//         let beat = unpack(truncate({pack(randValue1), pack(randValue2), pack(randValue3)}));
//         dut.axiWriteBeatPipeIn.enq(beat);

//     endrule

//     rule handleOutput;
//         if (dut.dataStreamPipeOut.notEmpty) begin
//             signalKeeperForStream.bitsPipeIn.enq(dut.dataStreamPipeOut.first);
//             dut.dataStreamPipeOut.deq;
//         end

//         if (dut.lengthAndByteEnPipeOut.notEmpty) begin
//             signalKeeperForMeta.bitsPipeIn.enq(dut.lengthAndByteEnPipeOut.first);
//             dut.lengthAndByteEnPipeOut.deq;
//         end

//         outReg <= signalKeeperForStream.out && signalKeeperForMeta.out;
//     endrule

//     method getOutput = outReg;
// endmodule









// (* doc = "testcase" *)
// (* synthesize *)
// module mkTestExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStreamTimingTest(TestExtractLengthAndByteEnFormAxiWriteBeatAndConvertToShiftedDataStreamTimingTest);
//     Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);

//     PcieStreamShifter dut <- mkBiDirectionStreamShifterG;

//     // ForceKeepWideSignals#(PcieDataStreamLsbRight, Bool) signalKeeperForStream <- mkForceKeepWideSignals; 
//     ForceKeepWideSignals#(PcieLengthAndByteEn, Bool) signalKeeperForMeta <- mkForceKeepWideSignals; 

//     ForceKeepWideSignals#(PcieDataStreamLsbRight, Bool) signalKeeperForStream <- mkForceKeepWideSignals; 
    

//     let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
//     let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
//     let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
//     let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
//     let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
//     let randSource6 <- mkSynthesizableRng512('h11111111);
//     let randSource7 <- mkSynthesizableRng512('h22222222);

//     Reg#(Bool) runReg <- mkReg(True);
//     Reg#(Bool) outReg <- mkReg(True);
//     rule injectTlp if (runReg);
//         runReg <= False;

//         let randValue1 <- randSource1.get;
//         let randValue2 <- randSource2.get;
//         let randValue3 <- randSource3.get;


//         let beat = unpack(truncate({pack(randValue1), pack(randValue2), pack(randValue3)}));
//         dut0.axiWriteBeatPipeIn.enq(beat);

//     endrule

//     rule tttt;
//         let randValue4 <- randSource4.get;
//         let randValue5 <- randSource5.get;
//         let randValue6 <- randSource6.get;
//         let randValue7 <- randSource7.get;

//         let dsOutput = dut0.dataStreamPipeOut.first;
//         dut0.dataStreamPipeOut.deq;

//         let signedShiftOffset = unpack(unpack(truncate({pack(randValue7)})));
//         dut.streamPipeIn.enq(dsOutput);
//         dut.offsetPipeIn.enq(signedShiftOffset);

//     endrule


//     rule handleOutput;
//         let shiftedLeftAlignedStream = dut.streamPipeOut.first;
//         dut.streamPipeOut.deq;
//         signalKeeperForStream.bitsPipeIn.enq(shiftedLeftAlignedStream);

//         if (dut0.lengthAndByteEnPipeOut.notEmpty) begin
//             signalKeeperForMeta.bitsPipeIn.enq(dut0.lengthAndByteEnPipeOut.first);
//             dut0.lengthAndByteEnPipeOut.deq;
//         end

//         outReg <= signalKeeperForStream.out && signalKeeperForMeta.out;
//     endrule



//     method getOutput = outReg;
// endmodule


interface TestRtilePcieAdaptorTimingTest;
    method Bit#(128) getOutput;
endinterface

(* synthesize *)
module mkTestRtilePcieAdaptorTimingTest(TestRtilePcieAdaptorTimingTest);
    Reg#(Bit#(32)) quitCounterReg <- mkReg(10000000);


    let rtilePcie <- mkRTilePcie;
    let dut <- mkRTilePcieAdaptor;

    mkConnection(dut.pcieRxPipeOut, rtilePcie.pcieRxPipeIn);
    mkConnection(dut.pcieTxPipeIn, rtilePcie.pcieTxPipeOut);


    ForceKeepWideSignals#(Bit#(2048), Bit#(32)) signalKeeperForTxBusOutput          <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(512), Bit#(16)) signalKeeperForRxBusOutput           <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Bit#(4164), Bit#(32)) signalKeeperForUserLogicReadOutput   <- mkForceKeepWideSignals; 
    

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
    let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);
    let randSource6 <- mkSynthesizableRng512('h11111111);
    let randSource7 <- mkSynthesizableRng512('h22222222);
    let randSource8 <- mkSynthesizableRng512('h33333333);
    let randSource9 <- mkSynthesizableRng512('h44444444);
    let randSourceA <- mkSynthesizableRng512('h55555555);
    let randSourceB <- mkSynthesizableRng512('h66666666);
    let randSourceC <- mkSynthesizableRng512('h77777777);
    let randSourceD <- mkSynthesizableRng512('h88888888);


    Reg#(Bool) runReg <- mkReg(True);
    Reg#(Bit#(128)) outReg <- mkReg(0);

    Reg#(Bit#(2048)) rxBusInputSignalReg <- mkReg(0);
    Reg#(Bit#(512)) txBusInputSignalReg <- mkReg(0);

    Reg#(Bit#(512)) rxBusOutputSignalReg <- mkReg(0);
    Reg#(Bit#(2048)) txBusOutputSignalReg <- mkReg(0);

    rule injectUserLogicReq if (runReg);
        
        let randValue1 <- randSource1.get;
        let randValue2 <- randSource2.get;
        let randValue3 <- randSource3.get;
        let randValue4 <- randSource4.get;
        let randValue5 <- randSource5.get;


        let writeMeta = unpack(truncate(randValue1));

        let writeData = unpack(truncate({randValue2, randValue3, randValue4}));

        let readMeta = unpack(truncate(randValue5));

        // write req
        rtilePcie.streamSlaveIfcVec[0].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[0].writePipeIfc.writeDataPipeIn.enq(writeData);

        rtilePcie.streamSlaveIfcVec[1].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[1].writePipeIfc.writeDataPipeIn.enq(writeData);

        rtilePcie.streamSlaveIfcVec[2].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[2].writePipeIfc.writeDataPipeIn.enq(writeData);

        rtilePcie.streamSlaveIfcVec[3].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        rtilePcie.streamSlaveIfcVec[3].writePipeIfc.writeDataPipeIn.enq(writeData);

        // read req
        rtilePcie.streamSlaveIfcVec[0].readPipeIfc.readMetaPipeIn.enq(readMeta);
        rtilePcie.streamSlaveIfcVec[1].readPipeIfc.readMetaPipeIn.enq(readMeta);
        rtilePcie.streamSlaveIfcVec[2].readPipeIfc.readMetaPipeIn.enq(readMeta);
        rtilePcie.streamSlaveIfcVec[3].readPipeIfc.readMetaPipeIn.enq(readMeta);


    endrule

    rule updateBusSignalReg;
        let randValue6 <- randSource6.get;
        let randValue7 <- randSource7.get;
        let randValue8 <- randSource8.get;
        let randValue9 <- randSource9.get;
        let randValueA <- randSourceA.get;

        rxBusInputSignalReg <= {randValue6, randValue7, randValue8, randValue9};
        txBusInputSignalReg <= {randValueA};
    endrule

    rule handleRxBusInputSignals;
        PcieTlpDataBusSegBundle         data;
        PcieTlpHeaderBusSegBundle       hdr;
        SopSignalBundle                 sop;
        EopSignalBundle                 eop;
        HvalidSignalBundle              hvalid;
        DvalidSignalBundle              dvalid;
        BarIdSignalBundle               bar;
        SegmentEmptySignalBundle        empty;
        HeaderCreditInitAckSignalBundle hcrdt_init_ack;
        DataCreditInitAckSignalBundle   dcrdt_init_ack;

        {data, hdr, sop, eop, hvalid, dvalid, bar, empty, hcrdt_init_ack, dcrdt_init_ack} = unpack(truncate(rxBusInputSignalReg));
        dut.rx.setRxInputData(data, hdr, sop, eop, hvalid, dvalid, bar, empty, hcrdt_init_ack, dcrdt_init_ack);
    endrule

    rule handleRxBusOutputSignals;
        rxBusOutputSignalReg <= zeroExtend({
            pack(dut.rx.hcrdt_init),
            pack(dut.rx.hcrdt_update),
            pack(dut.rx.hcrdt_update_cnt),
            pack(dut.rx.dcrdt_init),
            pack(dut.rx.dcrdt_update),
            pack(dut.rx.dcrdt_update_cnt)
        });
        signalKeeperForRxBusOutput.bitsPipeIn.enq(zeroExtend(pack(rxBusOutputSignalReg)));
    endrule

    rule handleTxBusInputSignals;

        HeaderCreditInitSignalBundle        hcrdt_init;
        HeaderCreditUpdateSignalBundle      hcrdt_update;
        HeaderCreditUpdateCntSignalBundle   hcrdt_update_cnt;
        DataCreditInitSignalBundle          dcrdt_init;
        DataCreditUpdateSignalBundle        dcrdt_update;
        DataCreditUpdateCntSignalBundle     dcrdt_update_cnt;
        Bool                                ready;

        {hcrdt_init, hcrdt_update, hcrdt_update_cnt, dcrdt_init, dcrdt_update, dcrdt_update_cnt, ready} = unpack(truncate(txBusInputSignalReg));
        dut.tx.setTxInputData(hcrdt_init, hcrdt_update, hcrdt_update_cnt, dcrdt_init, dcrdt_update, dcrdt_update_cnt, ready);
    
    endrule

    rule handleTxBusOutputSignals;
        txBusOutputSignalReg <= zeroExtend({
            pack(dut.tx.hcrdt_init_ack),
            pack(dut.tx.dcrdt_init_ack),
            pack(dut.tx.hdr),
            pack(dut.tx.data),
            pack(dut.tx.sop),
            pack(dut.tx.eop),
            pack(dut.tx.hvalid),
            pack(dut.tx.dvalid)
        });
        signalKeeperForTxBusOutput.bitsPipeIn.enq(zeroExtend(pack(txBusOutputSignalReg)));
    endrule

    rule handleUSerlogicReadOutput;
        Vector#(NUMERIC_TYPE_FOUR, PcieStreamData) resultVec = newVector;

        for (Integer idx = 0; idx < valueOf(NUMERIC_TYPE_FOUR); idx = idx + 1) begin
            if (rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.notEmpty) begin
                resultVec[idx] = rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.first;
                rtilePcie.streamSlaveIfcVec[idx].readPipeIfc.readDataPipeOut.deq;
            end
        end

        signalKeeperForUserLogicReadOutput.bitsPipeIn.enq(zeroExtend(pack(resultVec)));

    endrule


    rule handleOutput;
        

        outReg <= zeroExtend({signalKeeperForRxBusOutput.out, signalKeeperForTxBusOutput.out, signalKeeperForUserLogicReadOutput.out});
    endrule



    method getOutput = outReg;
endmodule





interface TestRTileDmaReadWriteSimple;
    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorRx rxRawIfc;

    (* always_ready, always_enabled *)
    interface RTilePcieAdaptorTx txRawIfc;

    (* always_ready, always_enabled *)
    method Action startTest(Bool isStart);

endinterface

module mkTestRTileDmaReadWriteSimple(TestRTileDmaReadWriteSimple);
    let dut <- mkRTilePcie;
    let rawInterfaceAdaptor <- mkRTilePcieAdaptor;

    mkConnection(rawInterfaceAdaptor.pcieRxPipeOut, dut.pcieRxPipeIn);
    mkConnection(rawInterfaceAdaptor.pcieTxPipeIn, dut.pcieTxPipeOut);

    Reg#(Bool) isStartedReg <- mkReg(False);
    Reg#(Word) runStepReg   <- mkReg(0);

    rule doTest if (isStartedReg && runStepReg < 1000);
        if (runStepReg == 0) begin
            $display("%t, ----------------start do test----------------------", $time);
        end
        runStepReg <= runStepReg + 1;

        let writeMeta = DtldStreamMemAccessMeta {
            addr: 'h0,
            totalLen: 16
        };
        let writeData = DtldStreamData {
            data: 'h00000000_11111111_22222222_33333333_44444444_55555555_66666666_77777777_88888888_99999999,
            startByteIdx: 0,
            byteNum: 16,
            isFirst: True,
            isLast: True
        };

        let readMeta = DtldStreamMemAccessMeta {
            addr: 4,
            totalLen: 17
        };

        case (runStepReg)
            0: begin
                dut.streamSlaveIfcVec[0].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
                dut.streamSlaveIfcVec[0].writePipeIfc.writeDataPipeIn.enq(writeData);

                dut.streamSlaveIfcVec[1].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
                dut.streamSlaveIfcVec[1].writePipeIfc.writeDataPipeIn.enq(writeData);

                dut.streamSlaveIfcVec[2].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
                dut.streamSlaveIfcVec[2].writePipeIfc.writeDataPipeIn.enq(writeData);

                dut.streamSlaveIfcVec[3].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
                dut.streamSlaveIfcVec[3].writePipeIfc.writeDataPipeIn.enq(writeData);
            end
            100: begin
                dut.streamSlaveIfcVec[0].readPipeIfc.readMetaPipeIn.enq(readMeta);
                dut.streamSlaveIfcVec[1].readPipeIfc.readMetaPipeIn.enq(readMeta);
                dut.streamSlaveIfcVec[2].readPipeIfc.readMetaPipeIn.enq(readMeta);
                dut.streamSlaveIfcVec[3].readPipeIfc.readMetaPipeIn.enq(readMeta);
            end
        endcase
        
    endrule

    rule getReadResult;
        let readDs = dut.streamSlaveIfcVec[0].readPipeIfc.readDataPipeOut.first;
        dut.streamSlaveIfcVec[0].readPipeIfc.readDataPipeOut.deq;
        $display("----------------read output----------------------\n", fshow(readDs));
    endrule

    method Action startTest(Bool isStart);
        if (isStart) begin
            $display("----------------isStartedReg <= True----------------------");
            isStartedReg <= True;
        end
    endmethod 

    interface rxRawIfc = rawInterfaceAdaptor.rx;
    interface txRawIfc = rawInterfaceAdaptor.tx;
endmodule