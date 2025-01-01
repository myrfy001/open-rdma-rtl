import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;
import Clocks :: *;
import Settings :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import AddressChunker :: *;
import PayloadGenAndCon :: *;
import DtldStream :: *;
import StreamDataTypes :: *;
import BasicDataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;
import NapWrapper :: *;
import StreamShifterG :: *;
import EthernetTypes :: *;
import QPContext :: *;
import RQ :: *;
import SQ :: *;
import MemRegionAndAddressTranslate :: *;
import PacketGenAndParse :: *;
import Top :: *;


// module mkTestTop(Empty);
//     Clock clkLogic <- mkAbsoluteClock(0, 250);
//     Clock clkEthNap  <- mkAbsoluteClock(0, 196);
//     Clock clkQpcMrPgtSrv  <- mkAbsoluteClock(0, 196);

//     let rstLogic <- mkAsyncResetFromCR(0, clkLogic);
//     let rstEthNap <- mkAsyncResetFromCR(0, clkEthNap);
//     let rstQpcMrPgtSrv <- mkAsyncResetFromCR(0, clkQpcMrPgtSrv);

//     let inner <- mkTestTopInner(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv, clocked_by clkLogic, reset_by rstLogic);
// endmodule

// module mkTestTopInner(
//         Clock clkEthNap,
//         Reset rstEthNap,
//         Clock clkQpcMrPgtSrv,
//         Reset rstQpcMrPgtSrv, 
//         Empty ifc
//     );

//     let dut <- mkBsvTop(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv);

// endmodule











// module mkTestTopNoMockHost(Empty);

//     Clock clkLogic <- mkAbsoluteClock(0, 250);
//     Clock clkEthNap  <- mkAbsoluteClock(0, 196);
//     Clock clkQpcMrPgtSrv  <- mkAbsoluteClock(0, 196);

//     let rstLogic <- mkAsyncResetFromCR(0, clkLogic);
//     let rstEthNap <- mkAsyncResetFromCR(0, clkEthNap);
//     let rstQpcMrPgtSrv <- mkAsyncResetFromCR(0, clkQpcMrPgtSrv);

//     let inner <- mkTestTopNoMockHostInner(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv, clocked_by clkLogic, reset_by rstLogic);


// endmodule


// module mkTestTopNoMockHostInner(
//         Clock clkEthNap,
//         Reset rstEthNap,
//         Clock clkQpcMrPgtSrv,
//         Reset rstQpcMrPgtSrv, 
//         Empty ifc
//     );

//     let dut <- mkQpMrPgtQpc(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv);

//     rule setNetworkParam;
//         LocalNetworkSettings networkSettings = unpack(0);
//         networkSettings.macAddr = 'hAABBCCDDEEFF;
//         networkSettings.ipAddr = 'h11223344;
//         dut.setLocalNetworkSettings(networkSettings);
//     endrule

//     Reg#(Bool) configDoneReg <- mkReg(False, clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
//     rule updateOnChipStorage if (!configDoneReg);
//         configDoneReg <= True;
//         dut.qpContextUpdateSrv.request.put(WriteReqQPC {
//             qpn: unpack(0),
//             ent: tagged Valid EntryQPC {
//                 qpnKeyPart: unpack(0),
//                 pdHandler: unpack(0),
//                 qpType: IBV_QPT_RC,
//                 rqAccessFlags: enum2Flag(IBV_ACCESS_LOCAL_WRITE) | enum2Flag(IBV_ACCESS_REMOTE_WRITE) | enum2Flag(IBV_ACCESS_REMOTE_READ),
//                 pmtu: IBV_MTU_256,
//                 peerQPN: 0
//             }
//         });

//         dut.pgtModifySrv.request.put(PgtModifyReq {
//             idx: unpack(0),
//             pte: unpack(0)
//         });

//         dut.mrTableModifySrv.request.put(MrTableModifyReq {
//             idx: unpack(0),
//             entry: tagged Valid MemRegionTableEntry {
//                 pgtOffset: unpack(0),
//                 baseVA: 0,
//                 len: 1024*1024*1024,
//                 accFlags: enum2Flag(IBV_ACCESS_LOCAL_WRITE) | enum2Flag(IBV_ACCESS_REMOTE_WRITE) | enum2Flag(IBV_ACCESS_REMOTE_READ),
//                 pdHandler: 0,
//                 keyPart: 0
//             }
//         });
//     endrule


//     Reg#(Bool) sentReg <- mkReg(False);
//     rule injectWQE if (!sentReg);
//         // sentReg <= True;

//         let wqe = WorkQueueElem {
//             msn: 0,
//             opcode: IBV_WR_RDMA_WRITE_WITH_IMM,
//             flags:  enum2Flag(IBV_SEND_NO_FLAGS),
//             qpType: IBV_QPT_RC,
//             psn: 0,
//             pmtu: IBV_MTU_256,
//             dqpIP: 'h11223344,
//             macAddr: 'hAABBCCDDEEFF,
//             laddr: unpack(0),
//             lkey: unpack(0),
//             raddr: unpack(0),
//             rkey: unpack(0),
//             len: 1,
//             totalLen: 1,
//             dqpn: unpack(0),
//             sqpn: unpack(0),
//             comp: tagged Invalid,
//             swap: tagged Invalid,
//             immDtOrInvRKey: tagged Valid tagged Imm 1234,
//             srqn: tagged Invalid,
//             qkey: tagged Invalid,
//             isFirst: True,                              
//             isLast: True                              
//         };

//         dut.wqePipeInVec[0].enq(wqe);
//         // dut.wqePipeInVec[1].enq(wqe);
//     endrule

// endmodule




// interface TestTopTiming;
//     method Bool getOutput;
// endinterface

// module mkTestTopTiming#(
//         Clock clkEthNap,
//         Reset rstEthNap,
//         Clock clkQpcMrPgtSrv,
//         Reset rstQpcMrPgtSrv
//     )(TestTopTiming);

//     let dut <- mkBsvTop(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv);

//     Reg#(Bool) outputSyncReg <- mkSyncRegToCC(False, clkEthNap, rstEthNap);

//     Vector#(HARDWARE_QP_CHANNEL_CNT, ForceKeepWideSignals#(DataStream, Bool)) signalKeeperForRawPacketVec <- replicateM(mkForceKeepWideSignals(clocked_by clkEthNap, reset_by rstEthNap)); 
//     for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
//         mkConnection(dut.otherRawPacketPipeOutVec[idx], signalKeeperForRawPacketVec[idx].bitsPipeIn);
//     end


//     rule combineOutput;
//         Bool outputVal = signalKeeperForRawPacketVec[0].out;
//         for (Integer idx = 1; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
//             outputVal = unpack(pack(outputVal) ^ pack(signalKeeperForRawPacketVec[idx].out));
//         end
//         outputSyncReg <= outputVal;
//     endrule

//     method getOutput = outputSyncReg;
// endmodule



interface TestTopTimingNoHardIP;
    method Bit#(32) getOutput;
endinterface

module mkTestTopTimingNoHardIP(TestTopTimingNoHardIP);

    let dut <- mkBsvTopWithoutHardIpInstance;

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD);
    let randSource5 <- mkSynthesizableRng512('hEEEEEEEE);


    ForceKeepWideSignals#(Bit#(512), Bit#(32)) signalKeeper1 <- mkForceKeepWideSignals; 

    Vector#(HARDWARE_QP_CHANNEL_CNT, ForceKeepWideSignals#(Bit#(512), Bit#(32))) signalKeeperVec1 <- replicateM(mkForceKeepWideSignals); 
    Vector#(HARDWARE_QP_CHANNEL_CNT, ForceKeepWideSignals#(Bit#(512), Bit#(32))) signalKeeperVec2 <- replicateM(mkForceKeepWideSignals); 

    Reg#(Bit#(32)) outputReg <- mkRegU;

    rule injectPcieSlave1;
        let randValue1 <- randSource1.get;
        dut.dmaSlavePipeIfc.writePipeIfc.writeMetaPipeIn.enq(unpack(truncate(randValue1)));
    endrule

    rule injectPcieSlave2;
        let randValue2 <- randSource2.get;
        dut.dmaSlavePipeIfc.writePipeIfc.writeDataPipeIn.enq(unpack(truncate(randValue2)));
    endrule

    rule injectPcieSlave3;
        let randValue3 <- randSource3.get;
        dut.dmaSlavePipeIfc.readPipeIfc.readMetaPipeIn.enq(unpack(truncate(randValue3)));
    endrule 

    rule injectPcieMaster;
        let randValue4 <- randSource4.get;
        for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            if (dut.dmaMasterPipeIfcVec[idx].readPipeIfc.readDataPipeIn.notFull) begin
                dut.dmaMasterPipeIfcVec[idx].readPipeIfc.readDataPipeIn.enq(unpack(truncate(randValue4 >> (idx * 8))));
            end
        end
    endrule 

    rule injectEth;
        let randValue5 <- randSource5.get;
        for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            if (dut.qpEthDataStreamIfcVec[idx].dataPipeIn.notFull) begin
                dut.qpEthDataStreamIfcVec[idx].dataPipeIn.enq(unpack(truncate(randValue5 >> (idx * 8))));
            end
        end
    endrule


    rule handleOutputPcieSlave;
        if (dut.dmaSlavePipeIfc.readPipeIfc.readDataPipeOut.notEmpty) begin
            dut.dmaSlavePipeIfc.readPipeIfc.readDataPipeOut.deq;
            signalKeeper1.bitsPipeIn.enq(zeroExtend(pack(dut.dmaSlavePipeIfc.readPipeIfc.readDataPipeOut.first)));
        end
    endrule

    
    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        rule handleOptputPcieMaster;
            Bit#(512) tmpV = 0;
            if (dut.dmaMasterPipeIfcVec[idx].writePipeIfc.writeMetaPipeOut.notEmpty) begin
                dut.dmaMasterPipeIfcVec[idx].writePipeIfc.writeMetaPipeOut.deq;
                tmpV = tmpV ^ zeroExtend(pack(dut.dmaMasterPipeIfcVec[idx].writePipeIfc.writeMetaPipeOut.first));
            end

            if (dut.dmaMasterPipeIfcVec[idx].writePipeIfc.writeDataPipeOut.notEmpty) begin
                dut.dmaMasterPipeIfcVec[idx].writePipeIfc.writeDataPipeOut.deq;
                tmpV = tmpV ^ zeroExtend(pack(dut.dmaMasterPipeIfcVec[idx].writePipeIfc.writeDataPipeOut.first));
            end

            if (dut.dmaMasterPipeIfcVec[idx].readPipeIfc.readMetaPipeOut.notEmpty) begin
                dut.dmaMasterPipeIfcVec[idx].readPipeIfc.readMetaPipeOut.deq;
                tmpV = tmpV ^ zeroExtend(pack(dut.dmaMasterPipeIfcVec[idx].readPipeIfc.readMetaPipeOut.first));
            end

            signalKeeperVec1[idx].bitsPipeIn.enq(zeroExtend(pack(tmpV)));
        endrule
    end


    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        rule handleOptputEth;

            if (dut.qpEthDataStreamIfcVec[idx].dataPipeOut.notEmpty) begin
                dut.qpEthDataStreamIfcVec[idx].dataPipeOut.deq;
                signalKeeperVec2[idx].bitsPipeIn.enq(zeroExtend(pack(dut.qpEthDataStreamIfcVec[idx].dataPipeOut.first)));
            end
        endrule
    end


    rule combineOutput;
        Bit#(32) outputVal = signalKeeper1.out;
        for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            outputVal = unpack(pack(outputVal) ^ pack(signalKeeperVec1[idx].out));
            outputVal = unpack(pack(outputVal) ^ pack(signalKeeperVec2[idx].out));
        end
        outputReg <= outputVal;
    endrule

    method getOutput = outputReg;
endmodule