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
import DataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;
import NapWrapper :: *;
import StreamShifter :: *;
import EthernetTypes :: *;
import QPContext :: *;
import RQ :: *;
import SQ :: *;
import MemRegionAndAddressTranslate :: *;
import PacketGenAndParse :: *;
import Top :: *;


module mkTestTop(Empty);

endmodule

interface TestTopTiming;
    method Bool getOutput;
endinterface

module mkTestTopTiming#(
        Clock clkEthNap,
        Reset rstEthNap,
        Clock clkQpcMrPgtSrv,
        Reset rstQpcMrPgtSrv
    )(TestTopTiming);

    let dut <- mkBsvTop(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv);

    Reg#(Bool) outputSyncReg <- mkSyncRegToCC(False, clkEthNap, rstEthNap);

    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA, clocked_by clkEthNap, reset_by rstEthNap);
    let randSource2 <- mkSynthesizableRng512('hBBBBBBBB);
    let randSource3 <- mkSynthesizableRng512('hCCCCCCCC);
    let randSource4 <- mkSynthesizableRng512('hDDDDDDDD, clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);

    Vector#(HARDWARE_QP_CHANNEL_CNT, ForceKeepWideSignals#(DataStream)) signalKeeperForRawPacketVec <- replicateM(mkForceKeepWideSignals(clocked_by clkEthNap, reset_by rstEthNap)); 
    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(dut.otherRawPacketPipeOutVec[idx], signalKeeperForRawPacketVec[idx].bitsPipeIn);
    end

    rule injectWqe;
        let randBitsPart2 <- randSource2.get;
        let randBitsPart3 <- randSource3.get;

        let wideRandomBits = {{randBitsPart2, randBitsPart3}};
        for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            WorkQueueElem wqe = unpack(truncate(wideRandomBits) >> idx * 5);
            dut.wqePipeInVec[idx].enq(wqe);
        end
    endrule

    rule injectStorage;
        let randBitsPart4 <- randSource4.get;

        WriteReqQPC qpcUpdateReq = unpack(truncate(randBitsPart4));
        MrTableModifyReq mrTableUpdateReq = unpack(truncate(randBitsPart4 >> 5));
        PgtModifyReq pgtUpdateReq = unpack(truncate(randBitsPart4 >> 11));

        dut.qpContextUpdateSrv.request.put(qpcUpdateReq);
        dut.mrTableModifySrv.request.put(mrTableUpdateReq);
        dut.pgtModifySrv.request.put(pgtUpdateReq);
    endrule

    rule consumeStorageUpdateResp;
        let _1 <- dut.qpContextUpdateSrv.response.get;
        let _2 <- dut.mrTableModifySrv.response.get;
        let _3 <- dut.pgtModifySrv.response.get;
    endrule

    rule combineOutput;
        Bool outputVal = signalKeeperForRawPacketVec[0].out;
        for (Integer idx = 1; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            outputVal = unpack(pack(outputVal) ^ pack(signalKeeperForRawPacketVec[idx].out));
        end
        outputSyncReg <= outputVal;
    endrule

    rule setNetworkParam;
        let randBitsPart1 <- randSource1.get;
        LocalNetworkSettings networkSettings = unpack(truncate(randBitsPart1));
        dut.setLocalNetworkSettings(networkSettings);
    endrule

    method getOutput = outputSyncReg;
endmodule