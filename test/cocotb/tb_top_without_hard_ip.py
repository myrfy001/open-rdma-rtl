#!/usr/bin/env python
import itertools
import gc
import logging
import os
import random
import threading

import time

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, Timer
from cocotb.regression import TestFactory
from cocotb.clock import Clock
from cocotb.queue import Queue

from descriptors import WorkReqOpCode, RdmaOpCode, MetaReportQueueAckDesc, MetaReportQueueAckExtraDesc, MetaReportQueuePacketBasicInfoDesc
from mock_host import UserspaceDriverServer, open_shared_mem_to_hw_simulator
from hw_init_helper import HardwareTestHelper, CARD_A_IP_ADDRESS, CARD_A_MAC_ADDRESS

import test_case_common as tcc

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

        self.shared_mem = open_shared_mem_to_hw_simulator(
            tcc.TOTAL_MEMORY_SIZE)

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

        self.init_helper: HardwareTestHelper = HardwareTestHelper(
            self.pcie_bfm)

    def clean_up(self):
        # need to ensure no reference to shared_mem, if not, the shared memory resource can not be released.
        self.pcie_bfm = None
        shared_mem = self.shared_mem
        self.shared_mem = None
        self.init_helper = None
        gc.collect()
        # shared_mem.close()

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

        await self.init_helper.do_device_init()

    async def start_single_card_loop_back(self):
        async def _loop_back_task(self):
            while True:
                tx_beat = await self.eth_bfm.get_tx_packet()
                await self.eth_bfm.inject_rx_packet(tx_beat)
                # self.log.debug(f"single_card_loop_back forward beat: {tx_beat}")

        cocotb.start_soon(_loop_back_task(self))

    async def testcase_send_simple_write_loopback_req(self):

        await self.init_helper.start_meta_report_queue_collector()

        src_buf_mem_addr, src_buf_mem = self.init_helper.alloc_physical_memory(
            1024, 1)
        src_mr_key = await self.init_helper.reg_mr(src_buf_mem_addr, 1024)

        dst_buf_mem_addr, dst_buf_mem = self.init_helper.alloc_physical_memory(
            1024, 1)
        dst_mr_key = await self.init_helper.reg_mr(dst_buf_mem_addr, 1024)

        self_qpn = self.init_helper.alloc_qpn()
        peer_qpn = self.init_helper.alloc_qpn()

        self.log.info(
            f"create qp: self qpn = {hex(self_qpn)}, peer qpn = {hex(peer_qpn)}")

        # create qp for send side
        await self.init_helper.create_qp(
            peer_mac_addr=CARD_A_MAC_ADDRESS,
            peer_ip_addr=CARD_A_IP_ADDRESS,
            local_udp_port=0x100,
            self_qpn=self_qpn,
            peer_qpn=peer_qpn,
        )

        # create qp for recv side
        await self.init_helper.create_qp(
            peer_mac_addr=CARD_A_MAC_ADDRESS,
            peer_ip_addr=CARD_A_IP_ADDRESS,
            local_udp_port=0x100,
            self_qpn=peer_qpn,
            peer_qpn=self_qpn,
        )

        imm_data = random.randint(0, 0xFFFFFFFF)
        msn = random.randint(0, 0xFFF)
        # psn = random.randint(0, 0xFFF)
        psn = 256

        self.init_helper.send_queues[0].put_work_request(
            opcode=WorkReqOpCode.IBV_WR_RDMA_WRITE_WITH_IMM,
            is_first=True,
            is_last=True,
            is_retry=False,
            enable_ecn=False,
            total_len=1,
            lkey=src_mr_key,
            laddr=src_buf_mem_addr,
            data_len=1,
            r_va=dst_buf_mem_addr,
            r_key=dst_mr_key,
            r_ip=CARD_A_IP_ADDRESS,
            r_mac=CARD_A_MAC_ADDRESS,
            dqpn=peer_qpn,
            sqpn=self_qpn,
            msn=msn,
            psn=psn,
            imm_data=imm_data
        )
        await self.init_helper.send_queues[0].sync_pointers()

        resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        self.log.debug(
            f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")

        resp = MetaReportQueuePacketBasicInfoDesc.from_buffer(resp_raw)
        assert resp.common_header.F_OP_CODE == RdmaOpCode.RDMA_WRITE_ONLY_WITH_IMMEDIATE
        assert resp.common_header.F_HAS_NEXT_FRAG == 0
        assert resp.F_MSN == msn
        assert resp.F_PSN == psn
        assert resp.F_SOLICITED == 0
        assert resp.F_ACK_REQ == 0
        assert resp.F_IS_RETRY == 0
        assert resp.F_DQPN == peer_qpn
        assert resp.F_TOTAL_LEN == 1
        assert resp.F_RADDR == dst_buf_mem_addr
        assert resp.F_RKEY == dst_mr_key
        assert resp.F_IMM_DATA == imm_data

        resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        self.log.debug(
            f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        resp = MetaReportQueueAckDesc.from_buffer(resp_raw)
        assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        assert resp.common_header.F_HAS_NEXT_FRAG == 1
        assert resp.F_IS_SEND_BY_LOCAL_HW == 1
        assert resp.F_IS_SEND_BY_DRIVER == 0
        assert resp.F_IS_WINDOW_SLIDED == 1
        assert resp.F_IS_PACKET_LOST == 1
        assert resp.F_PSN_BEFORE_SLIDE == 0xFFFFF0
        assert resp.F_PSN_NOW == psn
        assert resp.F_MSN == 0
        assert resp.F_NOW_BITMAP_LOW == 0
        assert resp.F_NOW_BITMAP_HIGH == 0x00010000_00000000

        resp_raw = await self.init_helper.get_meta_report_from_collected_queue()
        self.log.debug(
            f"resp_raw={hex(int.from_bytes(resp_raw, byteorder='little'))}")
        resp = MetaReportQueueAckExtraDesc.from_buffer(resp_raw)
        assert resp.common_header.F_OP_CODE == RdmaOpCode.ACKNOWLEDGE
        assert resp.common_header.F_HAS_NEXT_FRAG == 0
        assert resp.F_PRE_BITMAP_LOW == 0xFFFFFFFF_FFFFFFFF
        assert resp.F_PRE_BITMAP_HIGH == 0xFFFFFFFF_FFFFFFFF


@ cocotb.test(timeout_time=1500, timeout_unit="ns")
async def small_desc_fp_test(dut):

    tb = TB(dut)

    await cocotb.start(Clock(tb.clock, 2, "ns").start())

    await tb.gen_reset_and_do_hw_init()

    await tb.start_single_card_loop_back()

    await tb.testcase_send_simple_write_loopback_req()

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
