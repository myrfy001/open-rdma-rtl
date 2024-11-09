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


from common import gen_rtl_file_list, BluespecPipeIn, BluespecPipeOut, BluespecDataStream256


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self.txChannels = []
        self.rxChannels = []
        for idx in range(4):
            self.txChannels.append(BluespecPipeIn(
                dut, f"ftilemacTxStreamPipeInVec_{idx}", self.clock))
            self.rxChannels.append(BluespecPipeOut(
                dut, f"ftilemacRxStreamPipeOutVec_{idx}", self.clock))

        self.resetn.setimmediatevalue(0)

    async def gen_reset(self):
        self.resetn.value = 0
        await RisingEdge(self.clock)
        await RisingEdge(self.clock)
        self.resetn.value = 1
        await RisingEdge(self.clock)
        self.log.info("Generated FTile RST_N")


def genRandomPacket():
    cur_packet_size = 0
    target_packet_size = 0
    while True:
        if target_packet_size == 0:
            target_packet_size = random.randint(64, 5120)

        byte_left = target_packet_size - cur_packet_size
        byte_num = min(32, byte_left)
        is_first = cur_packet_size == 0
        is_last = byte_left <= 32
        ds = BluespecDataStream256(
            data=bytes([random.randint(0, 255) for _ in range(byte_num)]),
            byte_num=byte_num,
            start_byte_index=0,
            is_first=is_first,
            is_last=is_last
        )

        if is_last:
            cur_packet_size = 0
            target_packet_size = 0
        else:
            cur_packet_size = cur_packet_size + byte_num

        yield ds


@cocotb.test(timeout_time=1500, timeout_unit="ns")
async def small_desc_fp_test(dut):

    tb = TB(dut)

    await cocotb.start(Clock(tb.clock, 2, "ns").start())
    await tb.gen_reset()

    async def gen_send_packet():
        ds_generators = [genRandomPacket() for _ in range(4)]
        while True:
            for channel_idx in range(4):
                if await tb.txChannels[channel_idx].not_full():
                    if (random.random() < 0.05):
                        # make some bubles
                        continue
                    ds = next(ds_generators[channel_idx])
                    await tb.txChannels[channel_idx].enq(ds.pack())
            await RisingEdge(tb.clock)

    await cocotb.start_soon(gen_send_packet())

    await Timer(1000, "ns")


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
