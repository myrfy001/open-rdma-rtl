#!/usr/bin/env python
import itertools
import logging
import os
import random
import queue

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory
from cocotb.clock import Clock

from cocotbext.pcie.core import RootComplex
from cocotbext.pcie.intel.rtile import RTilePcieDevice, RTileRxBus, RTileTxBus


class TB(object):
    def __init__(self, dut, msix=False):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self._bus_width = 1024
        self._bus_bytes = 128

        # PCIe
        self.rc = RootComplex()

        self.client_tag = bool(int(os.getenv("CLIENT_TAG", "1")))

        self.dev = RTilePcieDevice(
            # configuration options
            port_num=0,
            pcie_generation=5,
            pcie_link_width=16,
            pld_clk_frequency=500e6,
            pf_count=1,
            max_payload_size=128,
            enable_extended_tag=True,

            # signals
            # Clock and reset
            reset_status=None,
            reset_status_n=None,
            coreclkout_hip=dut.CLK,
            refclk0=None,
            refclk1=None,
            pin_perst_n=None,

            # RX interface
            rx_bus=RTileRxBus.from_prefix(dut, "rxRawIfc"),
            rx_par_err=None,

            # TX interface
            tx_bus=RTileTxBus.from_prefix(dut, "txRawIfc"),
            tx_par_err=None,

            # RX flow control
            rx_buffer_limit=None,
            rx_buffer_limit_tdm_idx=None,

            # TX flow control
            tx_cdts_limit=None,
            tx_cdts_limit_tdm_idx=None,

        )

        self.dev.log.setLevel(logging.INFO)

        # dut.pcie_cq_np_req.setimmediatevalue(1)
        # dut.cfg_mgmt_addr.setimmediatevalue(0)
        # dut.cfg_mgmt_function_number.setimmediatevalue(0)
        # dut.cfg_mgmt_write.setimmediatevalue(0)
        # dut.cfg_mgmt_write_data.setimmediatevalue(0)
        # dut.cfg_mgmt_byte_enable.setimmediatevalue(0)
        # dut.cfg_mgmt_read.setimmediatevalue(0)
        # dut.cfg_mgmt_debug_access.setimmediatevalue(0)
        # dut.cfg_msg_transmit.setimmediatevalue(0)
        # dut.cfg_msg_transmit_type.setimmediatevalue(0)
        # dut.cfg_msg_transmit_data.setimmediatevalue(0)
        # dut.cfg_fc_sel.setimmediatevalue(0)
        # dut.cfg_dsn.setimmediatevalue(0)
        # dut.cfg_power_state_change_ack.setimmediatevalue(0)
        # dut.cfg_err_cor_in.setimmediatevalue(0)
        # dut.cfg_err_uncor_in.setimmediatevalue(0)
        # dut.cfg_flr_done.setimmediatevalue(0)
        # dut.cfg_vf_flr_func_num.setimmediatevalue(0)
        # dut.cfg_vf_flr_done.setimmediatevalue(0)
        # dut.cfg_link_training_enable.setimmediatevalue(1)
        # dut.cfg_interrupt_int.setimmediatevalue(0)
        # dut.cfg_interrupt_pending.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_select.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_int.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_pending_status.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_pending_status_data_enable.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_pending_status_function_num.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_attr.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_tph_present.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_tph_type.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_tph_st_tag.setimmediatevalue(0)
        # dut.cfg_interrupt_msi_function_number.setimmediatevalue(0)
        # dut.cfg_pm_aspm_l1_entry_reject.setimmediatevalue(0)
        # dut.cfg_pm_aspm_tx_l0s_entry_disable.setimmediatevalue(0)
        # dut.cfg_config_space_enable.setimmediatevalue(1)
        # dut.cfg_req_pm_transition_l23_ready.setimmediatevalue(0)
        # dut.cfg_hot_reset_in.setimmediatevalue(0)
        # dut.cfg_ds_port_number.setimmediatevalue(0)
        # dut.cfg_ds_bus_number.setimmediatevalue(0)
        # dut.cfg_ds_device_number.setimmediatevalue(0)

        self.rc.make_port().connect(self.dev)

    # Do not use user_rst but gen rstn for bsv
    async def gen_reset(self):
        self.resetn.value = 0
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.resetn.value = 1
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.log.info("Generated DMA RST_N")


@cocotb.test(timeout_time=100000000, timeout_unit="ns")
async def small_desc_fp_test(dut):

    dut.startTest_isStart.setimmediatevalue(0)

    tb = TB(dut)
    await tb.gen_reset()

    await tb.rc.enumerate()
    dev = tb.rc.find_device(tb.dev.functions[0].pcie_id)

    await dev.enable_device()
    await dev.set_master()

    mem = tb.rc.mem_pool.alloc_region(1024*1024)
    mem_base = mem.get_absolute_address(0)
    for idx, data in enumerate(len(mem)):
        mem[mem_base+idx] = data & 0xFF

    dut.startTest_isStart.value = 1
    await RisingEdge(tb.clock)
    dut.startTest_isStart.value = 0
    await RisingEdge(tb.clock)

    await Timer(1000, units='ns')


def gen_rtl_file_list(top_paths):
    fileset = set()
    filelist = []
    for top_path in top_paths.split(":"):
        for (dirpath, dirnames, filenames) in os.walk(top_path):
            for filename in filenames:
                if filename.endswith(".v") or filename.endswith(".sv"):
                    if filename not in fileset:
                        filelist.append(os.path.join(dirpath, filename))
                        fileset.add(filename)
    return filelist


def test_dma():
    rtl_dirs = os.getenv("COCOTB_VERILOG_DIR") or ""
    dut = os.getenv("COCOTB_DUT") or ""
    tests_dir = os.path.dirname(__file__)
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = gen_rtl_file_list(rtl_dirs)

    sim_build = os.path.join(tests_dir, "sim_build", dut)

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        timescale="1ns/1ps",
        sim_build=sim_build
    )


if __name__ == "__main__":
    test_dma()
