#!/usr/bin/env python
import itertools
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


from common import gen_rtl_file_list, BluespecPipeIn, BluespecPipeOut, BlueRdmaDataStream256, BlueRdmaDtldStreamMemAccessMeta, SimplePcieBehaviorModel


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        shared_mem = open_shared_mem_to_hw_simulator(256*1024*1024)

        UserspaceDriverServer(
            "0.0.0.0", 7700, self.csr_write_cb, self.csr_read_cb)

        self.pcie_bfm = SimplePcieBehaviorModel(
            dut,
            ["dmaMasterPipeIfcVec_0",
             "dmaMasterPipeIfcVec_1",
             "dmaMasterPipeIfcVec_2",
             "dmaMasterPipeIfcVec_3"],
            [
                "dmaSlavePipeIfc"
            ],
            shared_mem.buf)

        self.csr_write_req_queue = Queue()
        self.csr_read_req_queue = Queue()
        self.csr_read_resp_queue = Queue()
        self.csr_read_lock = threading.Lock()

        cocotb.start_soon(self._forward_csr_write_task())
        cocotb.start_soon(self._forward_csr_read_req_task())

    def csr_write_cb(self, addr, value):
        self.csr_write_req_queue.put_nowait((addr, value))

    def csr_read_cb(self, addr):
        with self.csr_read_lock:
            self.csr_read_req_queue.put_nowait(addr)
            while self.csr_read_resp_queue.empty:
                time.sleep(0)
            return self.csr_read_req_queue.get_nowait()

    async def _forward_csr_write_task(self):
        while True:
            addr, value = await self.csr_write_req_queue.get()
            await self.pcie_bfm.host_write_blocking(addr, value)

    async def _forward_csr_read_req_task(self):
        while True:
            addr = await self.csr_read_req_queue.get()
            val = await self.pcie_bfm.host_read_blocking(addr)
            await self.csr_read_resp_queue.put(val)

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


@ cocotb.test(timeout_time=6000000, timeout_unit="ns")
async def small_desc_fp_test(dut):

    tb = TB(dut)
    await cocotb.start(Clock(tb.clock, 2, "ns").start())

    await tb.gen_reset()

    await tb.pcie_bfm.host_write_blocking(0x02 << 2, 4)

    await Timer(4000000, units='ns')


def test_top_without_hard_ip():
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
        sim_build=sim_build,
        waves=True,
    )


if __name__ == "__main__":
    test_top_without_hard_ip()
