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
    rule test;
        $display("%d", valueOf(SizeOf#(TypeQP)));
    endrule
endmodule

