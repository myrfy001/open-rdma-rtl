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
import BasicDataTypes :: *;
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
    Clock clkLogic <- mkAbsoluteClock(0, 250);
    Clock clkEthNap  <- mkAbsoluteClock(0, 196);
    Clock clkQpcMrPgtSrv  <- mkAbsoluteClock(0, 196);

    let rstLogic <- mkAsyncResetFromCR(0, clkLogic);
    let rstEthNap <- mkAsyncResetFromCR(0, clkEthNap);
    let rstQpcMrPgtSrv <- mkAsyncResetFromCR(0, clkQpcMrPgtSrv);

    let inner <- mkTestTopInner(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv, clocked_by clkLogic, reset_by rstLogic);
endmodule

module mkTestTopInner(
        Clock clkEthNap,
        Reset rstEthNap,
        Clock clkQpcMrPgtSrv,
        Reset rstQpcMrPgtSrv, 
        Empty ifc
    );

    let dut <- mkBsvTop(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv);

endmodule











module mkTestTopNoMockHost(Empty);

    Clock clkLogic <- mkAbsoluteClock(0, 250);
    Clock clkEthNap  <- mkAbsoluteClock(0, 196);
    Clock clkQpcMrPgtSrv  <- mkAbsoluteClock(0, 196);

    let rstLogic <- mkAsyncResetFromCR(0, clkLogic);
    let rstEthNap <- mkAsyncResetFromCR(0, clkEthNap);
    let rstQpcMrPgtSrv <- mkAsyncResetFromCR(0, clkQpcMrPgtSrv);

    let inner <- mkTestTopNoMockHostInner(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv, clocked_by clkLogic, reset_by rstLogic);


endmodule


module mkTestTopNoMockHostInner(
        Clock clkEthNap,
        Reset rstEthNap,
        Clock clkQpcMrPgtSrv,
        Reset rstQpcMrPgtSrv, 
        Empty ifc
    );

    let dut <- mkQpMrPgtQpc(clkEthNap, rstEthNap, clkQpcMrPgtSrv, rstQpcMrPgtSrv);

    rule setNetworkParam;
        LocalNetworkSettings networkSettings = unpack(0);
        networkSettings.macAddr = 'hAABBCCDDEEFF;
        networkSettings.ipAddr = 'h11223344;
        dut.setLocalNetworkSettings(networkSettings);
    endrule

    Reg#(Bool) configDoneReg <- mkReg(False, clocked_by clkQpcMrPgtSrv, reset_by rstQpcMrPgtSrv);
    rule updateOnChipStorage if (!configDoneReg);
        configDoneReg <= True;
        dut.qpContextUpdateSrv.request.put(WriteReqQPC {
            qpn: unpack(0),
            ent: tagged Valid EntryQPC {
                qpnKeyPart: unpack(0),
                pdHandler: unpack(0),
                qpType: IBV_QPT_RC,
                rqAccessFlags: enum2Flag(IBV_ACCESS_LOCAL_WRITE) | enum2Flag(IBV_ACCESS_REMOTE_WRITE) | enum2Flag(IBV_ACCESS_REMOTE_READ),
                pmtu: IBV_MTU_256,
                peerQPN: 0
            }
        });

        dut.pgtModifySrv.request.put(PgtModifyReq {
            idx: unpack(0),
            pte: unpack(0)
        });

        dut.mrTableModifySrv.request.put(MrTableModifyReq {
            idx: unpack(0),
            entry: tagged Valid MemRegionTableEntry {
                pgtOffset: unpack(0),
                baseVA: 0,
                len: 1024*1024*1024,
                accFlags: enum2Flag(IBV_ACCESS_LOCAL_WRITE) | enum2Flag(IBV_ACCESS_REMOTE_WRITE) | enum2Flag(IBV_ACCESS_REMOTE_READ),
                pdHandler: 0,
                keyPart: 0
            }
        });
    endrule


    Reg#(Bool) sentReg <- mkReg(False);
    rule injectWQE if (!sentReg);
        // sentReg <= True;

        let wqe = WorkQueueElem {
            pkey: 0,
            opcode: IBV_WR_RDMA_WRITE_WITH_IMM,
            flags:  enum2Flag(IBV_SEND_NO_FLAGS),
            qpType: IBV_QPT_RC,
            psn: 0,
            pmtu: IBV_MTU_256,
            dqpIP: 'h11223344,
            macAddr: 'hAABBCCDDEEFF,
            laddr: unpack(0),
            lkey: unpack(0),
            raddr: unpack(0),
            rkey: unpack(0),
            len: 1,
            totalLen: 1,
            dqpn: unpack(0),
            sqpn: unpack(0),
            comp: tagged Invalid,
            swap: tagged Invalid,
            immDtOrInvRKey: tagged Valid tagged Imm 1234,
            srqn: tagged Invalid,
            qkey: tagged Invalid,
            isFirst: True,                              
            isLast: True                              
        };

        dut.wqePipeInVec[0].enq(wqe);
        // dut.wqePipeInVec[1].enq(wqe);
    endrule

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

    Vector#(HARDWARE_QP_CHANNEL_CNT, ForceKeepWideSignals#(DataStream, Bool)) signalKeeperForRawPacketVec <- replicateM(mkForceKeepWideSignals(clocked_by clkEthNap, reset_by rstEthNap)); 
    for (Integer idx = 0; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
        mkConnection(dut.otherRawPacketPipeOutVec[idx], signalKeeperForRawPacketVec[idx].bitsPipeIn);
    end


    rule combineOutput;
        Bool outputVal = signalKeeperForRawPacketVec[0].out;
        for (Integer idx = 1; idx < valueOf(HARDWARE_QP_CHANNEL_CNT); idx = idx + 1) begin
            outputVal = unpack(pack(outputVal) ^ pack(signalKeeperForRawPacketVec[idx].out));
        end
        outputSyncReg <= outputVal;
    endrule

    method getOutput = outputSyncReg;
endmodule