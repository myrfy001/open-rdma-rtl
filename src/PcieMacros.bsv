`ifndef __PCIE_MACROS__
`define __PCIE_MACROS__

`define PCIE_TLP_HEADER_FMT_3DW_NO_DATA             3'b000
`define PCIE_TLP_HEADER_FMT_4DW_NO_DATA             3'b001
`define PCIE_TLP_HEADER_FMT_3DW_WITH_DATA           3'b010
`define PCIE_TLP_HEADER_FMT_4DW_WITH_DATA           3'b011

`define PCIE_TLP_HEADER_TYPE_MEM_READ               5'b00000
`define PCIE_TLP_HEADER_TYPE_MEM_WRITE              5'b00000
`define PCIE_TLP_HEADER_TYPE_CPL_WITH_DATA          5'b01010

`endif