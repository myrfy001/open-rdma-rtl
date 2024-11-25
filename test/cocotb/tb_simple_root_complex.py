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

from common import gen_rtl_file_list, BluespecPipeIn, BluespecPipeOut, BlueRdmaDataStream256, BlueRdmaDtldStreamMemAccessMeta


class TB(object):
    def __init__(self, dut):
        self.dut = dut

        self.pcie_mrrs = 128

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self.requester_write_meta_pipes = []
        self.requester_write_data_pipes = []
        self.requester_read_meta_pipes = []
        self.requester_read_data_pipes = []

        for idx in range(4):
            self.requester_write_meta_pipes.append(BluespecPipeIn(
                dut, f"streamSlaveIfcVec_{idx}_writePipeIfc_writeMetaPipeIn", self.clock))
            self.requester_write_data_pipes.append(BluespecPipeIn(
                dut, f"streamSlaveIfcVec_{idx}_writePipeIfc_writeDataPipeIn", self.clock))
            self.requester_read_meta_pipes.append(BluespecPipeIn(
                dut, f"streamSlaveIfcVec_{idx}_readPipeIfc_readMetaPipeIn", self.clock))
            self.requester_read_data_pipes.append(BluespecPipeOut(
                dut, f"streamSlaveIfcVec_{idx}_readPipeIfc_readDataPipeOut", self.clock))

        # PCIe
        self.rc = RootComplex()

        self.hardware_ip_inst = RTilePcieDevice(
            # configuration options
            port_num=0,
            pcie_generation=5,
            pcie_link_width=16,
            pld_clk_frequency=500e6,
            pf_count=1,
            max_payload_size=512,
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

        self.hardware_ip_inst.log.setLevel(logging.INFO)
        self.rc.make_port().connect(self.hardware_ip_inst)

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

    def genRandomWritePacket(self):
        cur_packet_size = 0
        target_packet_size = 0
        packet_start_addr = 0
        byte_cnt_per_beat = 32
        while True:
            if target_packet_size == 0:
                packet_start_addr = 0x14d7b  # random.randint(0, 64*1024*1024)
                packet_start_addr_4k_block = packet_start_addr >> 12

                # can not exceed max read request size and can not cross 4kB boundary
                packet_max_end_addr = min(
                    packet_start_addr+self.pcie_mrrs,
                    packet_start_addr_4k_block << 12 + 4095
                )

                # random.randint(packet_start_addr, packet_max_end_addr)
                packet_end_addr = 0x14dd8
                target_packet_size = packet_end_addr - packet_start_addr + 1
                self.log.debug(
                    f"send new packet, start_addr = {hex(packet_start_addr)} size={hex(target_packet_size)}")

            byte_left = target_packet_size - cur_packet_size
            start_addr_aligned_to_4_byte = packet_start_addr & (~0x03)
            end_addr_for_this_beat = packet_start_addr + byte_left
            is_first = cur_packet_size == 0

            max_allowed_end_addr_for_this_beat = start_addr_aligned_to_4_byte + byte_cnt_per_beat - 1

            if end_addr_for_this_beat > max_allowed_end_addr_for_this_beat:

                end_addr_for_this_beat = max_allowed_end_addr_for_this_beat
                byte_num = end_addr_for_this_beat - packet_start_addr + 1
                # print("end_addr_for_this_beat=", hex(
                #     end_addr_for_this_beat), ", byte_num=", hex(byte_num))
                is_last = False
            else:
                byte_num = byte_left
                is_last = True

            data = [byte
                    for num in range(
                        start_addr_aligned_to_4_byte, start_addr_aligned_to_4_byte + byte_cnt_per_beat, 4)
                    for byte in num.to_bytes(4, byteorder="little")]

            head_invalid_byte_cnt = packet_start_addr % 4
            tail_invalid_byte_cnt = (
                byte_cnt_per_beat - head_invalid_byte_cnt - byte_num)

            # print("===========111", [hex(d) for d in data],
            #       head_invalid_byte_cnt, tail_invalid_byte_cnt, end_addr_for_this_beat, is_first, is_last)

            if head_invalid_byte_cnt != 0:
                data[0: head_invalid_byte_cnt] = ([0] * head_invalid_byte_cnt)
            if tail_invalid_byte_cnt != 0:
                data[head_invalid_byte_cnt +
                     byte_num: byte_cnt_per_beat] = ([0] * tail_invalid_byte_cnt)
            # print("===========222", [hex(d) for d in data])

            print("===========", data, is_first, is_last, cur_packet_size)

            ds = BlueRdmaDataStream256(
                data=bytes(data),
                byte_num=byte_num,
                start_byte_index=head_invalid_byte_cnt,
                is_first=is_first,
                is_last=is_last
            )
            print("target_packet_size=", target_packet_size, ", cur_packet_size=",
                  cur_packet_size, ", byte_left=", byte_left, ", byte_num=", byte_num)
            print("gen new packet=", ds)

            if is_last:
                cur_packet_size = 0
                target_packet_size = 0
            else:
                cur_packet_size = cur_packet_size + byte_num
                packet_start_addr += byte_num

            yield ds


@ cocotb.test(timeout_time=2000, timeout_unit="ns")
async def small_desc_fp_test(dut):

    tb = TB(dut)

    for idx, ds in enumerate(tb.genRandomWritePacket()):
        print(ds)
        if idx > 10:
            raise SystemExit

    # await tb.gen_reset()

    # await tb.rc.enumerate()
    # pcie_ep_dev = tb.rc.find_device(
    #     tb.hardware_ip_inst.functions[0].pcie_id)

    # await pcie_ep_dev.enable_device()
    # await pcie_ep_dev.set_master()

    # mem = tb.rc.mem_pool.alloc_region(1024*1024)
    # mem_base = mem.get_absolute_address(0)
    # for idx, data in enumerate(mem):
    #     mem[mem_base+idx] = data & 0xFF

    # write_meta = BlueRdmaDtldStreamMemAccessMeta(
    #     addr=0,
    #     total_len=32
    # )
    # await tb.requester_write_meta_pipes[0].enq(write_meta.pack())

    # write_ds = BlueRdmaDataStream256(
    #     data=bytes([random.randint(0, 255) for _ in range(32)]),
    #     byte_num=32,
    #     start_byte_index=0,
    #     is_first=True,
    #     is_last=True
    # )
    # await tb.requester_write_data_pipes[0].enq(write_ds.pack())

    # await Timer(100, units='ns')

    # read_meta = BlueRdmaDtldStreamMemAccessMeta(
    #     addr=0,
    #     total_len=32
    # )
    # await tb.requester_read_meta_pipes[0].enq(read_meta.pack())

    # await Timer(200, units='ns')

    # if await tb.requester_read_data_pipes[0].not_empty():
    #     read_ds_raw = await tb.requester_read_data_pipes[0].first()
    #     await tb.requester_read_data_pipes[0].deq()
    #     read_ds = BlueRdmaDataStream256.unpack(read_ds_raw)
    #     tb.log.info("pcie read resp1 = %s" % read_ds)

    # await Timer(10, units='ns')
    # if await tb.requester_read_data_pipes[0].not_empty():
    #     read_ds_raw = await tb.requester_read_data_pipes[0].first()
    #     await tb.requester_read_data_pipes[0].deq()
    #     read_ds = BlueRdmaDataStream256.unpack(read_ds_raw)
    #     tb.log.info("pcie read resp2 = %s" % read_ds)


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
        sim_build=sim_build,
        waves=True,
    )


if __name__ == "__main__":
    test_dma()
