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
import EthernetTypes :: *;
import PacketGenAndParse :: *;


module mkTestPacketGen(Empty);
    let dut <- mkPacketGen;

    Reg#(Bool) isInitedReg <- mkReg(False);

    rule doInit if (!isInitedReg);
        isInitedReg <= True;
        dut.setLocalNetworkSettings(LocalNetworkSettings{
            macAddr: unpack('h112233445566),
            ipAddr: unpack('hAABBCCDD),
            gatewayAddr: unpack(0),
            netMask: unpack(0)
        });
    endrule

    rule injectStimulate;
        let wqe = WorkQueueElem{
            pkey: 0,
            opcode: IBV_WR_RDMA_WRITE_WITH_IMM,
            flags: enum2Flag(IBV_SEND_SIGNALED) | enum2Flag(IBV_SEND_SOLICITED),
            qpType: IBV_QPT_RC,
            psn: 0,
            pmtu: IBV_MTU_256,
            dqpIP: unpack(0),
            macAddr: unpack(0),
            laddr: unpack(0),
            lkey: unpack(0),
            raddr: unpack(0),
            rkey: unpack(0),
            len: 8192,
            totalLen: 8192,
            dqpn: unpack(0),
            sqpn: unpack(0),
            comp: tagged Invalid,
            swap: tagged Invalid,
            immDtOrInvRKey: tagged Valid tagged Imm unpack(0),
            srqn: tagged Invalid,
            qkey: tagged Invalid,
            isFirst: True,
            isLast: True
        };

        dut.wqePipeIn.enq(wqe);
    endrule

    rule getResponse;
        let ds = dut.packetPipeOut.first;
        dut.packetPipeOut.deq;
        $display(fshow(ds));
    endrule
endmodule
