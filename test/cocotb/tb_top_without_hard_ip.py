#!/usr/bin/env python
import itertools
import gc
import logging
import os
import threading

import time

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory
from cocotb.clock import Clock
from cocotb.queue import Queue

from mock_host import UserspaceDriverServer, open_shared_mem_to_hw_simulator
from hw_init_helper import HardwareInitHelper

from common import gen_rtl_file_list, SimplePcieBehaviorModel, SimpleEthBehaviorModel, copy_mem_file_to_sim_build_dir
from scapy.layers.inet import IP, UDP
from scapy.layers.l2 import Ether


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self.shared_mem = open_shared_mem_to_hw_simulator(256*1024*1024)

        self.pcie_bfm = SimplePcieBehaviorModel(
            dut,
            ["dmaMasterPipeIfcVec_0",
             "dmaMasterPipeIfcVec_1",
             "dmaMasterPipeIfcVec_2",
             "dmaMasterPipeIfcVec_3"],
            [
                "dmaSlavePipeIfc"
            ],
            self.shared_mem.buf
        )

        self.eth_bfm = SimpleEthBehaviorModel(
            dut,
            [
                "qpEthDataStreamIfcVec_0_dataPipeOut",
                "qpEthDataStreamIfcVec_1_dataPipeOut",
                "qpEthDataStreamIfcVec_2_dataPipeOut",
                "qpEthDataStreamIfcVec_3_dataPipeOut",
            ],
            [
                "qpEthDataStreamIfcVec_0_dataPipeIn",
                "qpEthDataStreamIfcVec_1_dataPipeIn",
                "qpEthDataStreamIfcVec_2_dataPipeIn",
                "qpEthDataStreamIfcVec_3_dataPipeIn",
            ],
        )

        self.init_helper = HardwareInitHelper(self.pcie_bfm)

    def clean_up(self):
        # need to ensure no reference to shared_mem, if not, the shared memory resource can not be released.
        self.pcie_bfm = None
        shared_mem = self.shared_mem
        self.shared_mem = None
        gc.collect()
        shared_mem.close()

    async def put_rx_data(self, packet_data):
        await self.eth_bfm.inject_rx_packet(packet_data)

    async def gen_reset_and_do_hw_init(self):
        self.resetn.value = 0
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.resetn.value = 1
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.log.info("Generated DMA RST_N")

        await self.init_helper.do_init()


@ cocotb.test(timeout_time=6000000, timeout_unit="ns")
async def small_desc_fp_test(dut):

    tb = TB(dut)

    await cocotb.start(Clock(tb.clock, 2, "ns").start())

    await tb.gen_reset_and_do_hw_init()

    eth_layer = Ether(dst="AA:BB:CC:DD:EE:FF", src="AA:BB:CC:DD:EE:00")
    ip_layer = IP(dst="17.34.51.68")
    udp_layer = UDP(dport=1111, sport=2222)

    payload_to_send = "0123456789abcdef"
    bytes_to_send = bytes(eth_layer/ip_layer/udp_layer/payload_to_send)
    await tb.put_rx_data(bytes_to_send)

    await Timer(500, units='ns')
    tb.clean_up()


def test_top_without_hard_ip():
    rtl_dirs = os.getenv("COCOTB_VERILOG_DIR") or ""
    dut = os.getenv("COCOTB_DUT") or ""
    tests_dir = os.path.dirname(__file__)
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = gen_rtl_file_list(rtl_dirs)

    sim_build = os.path.join(tests_dir, "sim_build", dut)
    copy_mem_file_to_sim_build_dir(rtl_dirs, sim_build)

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        timescale="1ns/1ps",
        sim_build=sim_build,
        waves=True,
    )


if __name__ == "__main__":
    test_top_without_hard_ip()
