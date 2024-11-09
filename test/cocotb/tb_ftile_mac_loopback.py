#!/usr/bin/env python
import itertools
import logging
import os
import random
import queue

import cocotb.triggers
import cocotb_test.simulator
import pytest

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ReadWrite
from cocotb.regression import TestFactory
from cocotb.clock import Clock


from common import gen_rtl_file_list, BluespecPipeIn, BluespecPipeOut


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self.pipeIn = BluespecPipeIn(dut, "pipeIn", self.clock)
        self.pipeOut = BluespecPipeOut(dut, "pipeOut", self.clock)
        self.resetn.setimmediatevalue(0)

    async def gen_reset(self):
        self.resetn.value = 0
        await RisingEdge(self.clock)
        self.resetn.value = 1
        await RisingEdge(self.clock)
        self.log.info("Generated FTile RST_N")


@cocotb.test(timeout_time=15, timeout_unit="ns")
async def small_desc_fp_test(dut):
    # print("-=----------")
    tb = TB(dut)
    # print("00000000")
    await cocotb.start(Clock(tb.clock, 2, "ns").start())
    await tb.gen_reset()

    async def _enq():
        await tb.pipeIn.enq(10)
        await RisingEdge(tb.clock)
        # await tb.pipeIn.enq(9)
        # await RisingEdge(tb.clock)
        # await tb.pipeIn.enq(8)
        # await RisingEdge(tb.clock)
        # await tb.pipeIn.enq(7)

    cocotb.start_soon(_enq())

    await RisingEdge(tb.clock)
    await RisingEdge(tb.clock)
    await RisingEdge(tb.clock)
    print("time1=", cocotb.utils.get_sim_time(units='ns'))
    await tb.pipeOut.deq()
    print("time2=", cocotb.utils.get_sim_time(units='ns'))
    ret = await tb.pipeOut.first()
    print("ret=", ret, "time3=", cocotb.utils.get_sim_time(units='ns'))

    await RisingEdge(tb.clock)
    print("time4=", cocotb.utils.get_sim_time(units='ns'))
    # await RisingEdge(tb.clock)
    # print("time5=", cocotb.utils.get_sim_time(units='ns'))

    await tb.pipeOut.deq()
    print("time6=", cocotb.utils.get_sim_time(units='ns'))
    ret = await tb.pipeOut.first()
    print("ret=", ret, "time7=", cocotb.utils.get_sim_time(units='ns'))

    # await RisingEdge(tb.clock)
    # await tb.pipeOut.deq()
    # ret = await tb.pipeOut.first()
    # print("ret=", ret)

    # await RisingEdge(tb.clock)
    # await tb.pipeOut.deq()
    # ret = await tb.pipeOut.first()
    # print("ret=", ret)

    # await RisingEdge(tb.clock)
    # await tb.pipeOut.deq()
    # ret = await tb.pipeOut.first()
    # print("ret=", ret)


def test_ftile_mac():
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
        waves=True
    )


if __name__ == "__main__":
    test_ftile_mac()
