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

`include "PcieMacros.bsv"

(* doc = "testcase" *)
module mkTestRTilePcieAdaptor(Empty);
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



