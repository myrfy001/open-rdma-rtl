import Connectable :: *;
import FIFOF :: *;
import Vector :: *;
import BuildVector :: *;
import PAClib :: *; 
import GetPut :: *;

import PrimUtils :: *;

import Utils4Test :: *;

import AddressChunker :: *;
import PayloadGen :: *;
import DataTypes :: *;
import RdmaHeaders :: *;
import ClientServer :: *;
import ConnectableF::*;


(* doc = "testcase" *)
module mkTestPayloadGen(Empty);
    PayloadGen dut <- mkPayloadGen;

    Reg#(Bool) stopReg <- mkReg(True);
    rule test if (stopReg);
        stopReg <= False;
        let req = PayloadGenReq{
            addr: 1,
            len: 4096*4
        };
        dut.reqPipeIn.enq(req);
    endrule
endmodule

