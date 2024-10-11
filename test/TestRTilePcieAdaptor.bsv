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

//     ForceKeepWideSignals#(PcieDataStreamLsbRight) signalKeeperForStream <- mkForceKeepWideSignals; 
//     ForceKeepWideSignals#(PcieLengthAndByteEn) signalKeeperForMeta <- mkForceKeepWideSignals; 
    

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

//     // ForceKeepWideSignals#(PcieDataStreamLsbRight) signalKeeperForStream <- mkForceKeepWideSignals; 
//     ForceKeepWideSignals#(PcieLengthAndByteEn) signalKeeperForMeta <- mkForceKeepWideSignals; 

//     ForceKeepWideSignals#(PcieDataStreamLsbRight) signalKeeperForStream <- mkForceKeepWideSignals; 
    

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
    Reg#(Bool) arleadyRunReg <- mkReg(False);

    rule doTest if (isStartedReg && !arleadyRunReg);
        $display("----------------start do test----------------------");
        arleadyRunReg <= True;

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
            addr: 0,
            totalLen: 17
        };

        // dut.streamSlaveIfcVec[0].writePipeIfc.writeMetaPipeIn.enq(writeMeta);
        // dut.streamSlaveIfcVec[0].writePipeIfc.writeDataPipeIn.enq(writeData);
        dut.streamSlaveIfcVec[0].readPipeIfc.readMetaPipeIn.enq(readMeta);
        
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