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
module mkTestBitmapWindowStorage(Empty);
 
    BitmapWindowStorage#(Bit#(9), Bit#(128), Bit#(17), OOO_WINDOW_STRIDE) dut <- mkBitmapWindowStorage;


endmodule



interface TestBitmapWindowStorageTiming;
    method Bool getOutput;
endinterface

(* doc = "testcase" *)
module mkTestBitmapWindowStorageTiming(TestBitmapWindowStorageTiming);
 
    BitmapWindowStorage#(Bit#(9), Bit#(128), Bit#(17), OOO_WINDOW_STRIDE) dut <- mkBitmapWindowStorage;

    ForceKeepWideSignals#(Maybe#(BitmapWindowStorageUpdateResp#(Bit#(9), Bit#(128), Bit#(17)))) signalKeeperForResp1 <- mkForceKeepWideSignals; 
    ForceKeepWideSignals#(Maybe#(BitmapWindowStorageUpdateResp#(Bit#(9), Bit#(128), Bit#(17)))) signalKeeperForResp2 <- mkForceKeepWideSignals; 
    let randSource1 <- mkSynthesizableRng512('hAAAAAAAA);

    Reg#(Bool) outReg <- mkRegU;
    rule injectData;
        let rndData <- randSource1.get;
        dut.reqPipeInVec[0].enq(unpack(truncate(rndData)));
        dut.reqPipeInVec[1].enq(unpack(truncate(rndData[511:256])));
    endrule

    rule getResp;
        let resp1 = dut.respPipeOutVec[0].first;
        dut.respPipeOutVec[0].deq;
        let resp2 = dut.respPipeOutVec[1].first;
        dut.respPipeOutVec[1].deq;

        signalKeeperForResp1.bitsPipeIn.enq(resp1);
        signalKeeperForResp2.bitsPipeIn.enq(resp2);
    endrule

    rule gatherKeptSignals;
        outReg <= signalKeeperForResp1.out && signalKeeperForResp2.out;
    endrule

    method getOutput = outReg;
endmodule