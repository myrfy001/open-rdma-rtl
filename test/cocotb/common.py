import os
from collections import deque

import asyncio

import cocotb
from cocotb.triggers import RisingEdge, ReadWrite
import cocotb.utils


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


class BluespecValueMethod:
    def __init__(self, dut, signal_base_name, clk, ready_prefix="RDY_"):
        self.dut = dut
        self.clk = clk
        self.signal_base_name = signal_base_name

        ready_signal_name = ready_prefix + signal_base_name
        return_value_signal_name = signal_base_name

        self.ready_signal = getattr(dut, ready_signal_name)
        self.return_value_signal = getattr(dut, return_value_signal_name)

    async def __call__(self, **kwargs):
        await ReadWrite()
        while not self.ready_signal.value:
            await RisingEdge(self.ready_signal)

        for (arg_name, arg_val) in kwargs.items():
            getattr(self.dut, self.signal_base_name +
                    f"_{arg_name}").value = arg_val

        return self.return_value_signal.value


class BluespecActionValueMethod:
    def __init__(self, dut, signal_base_name, clk, ready_prefix="RDY_", enable_prefix="EN_"):
        self.dut = dut
        self.clk = clk
        self.signal_base_name = signal_base_name

        ready_signal_name = ready_prefix + signal_base_name
        enable_signal_name = enable_prefix + signal_base_name
        return_value_signal_name = signal_base_name

        self.ready_signal = getattr(dut, ready_signal_name)
        self.enable_signal = getattr(dut, enable_signal_name)
        self.return_value_signal = getattr(dut, return_value_signal_name, None)

        self.enable_signal.setimmediatevalue(0)

    async def __call__(self, **kwargs):
        async def _deassert_en_signal():
            await RisingEdge(self.clk)
            self.enable_signal.value = 0

        await ReadWrite()
        while not self.ready_signal.value:
            await RisingEdge(self.ready_signal)
        self.enable_signal.value = 1
        for (arg_name, arg_val) in kwargs.items():
            getattr(self.dut, self.signal_base_name +
                    f"_{arg_name}").value = arg_val
        await cocotb.start(_deassert_en_signal())
        if self.return_value_signal is not None:
            return self.return_value_signal.value


class BluespecActionMethod(BluespecActionValueMethod):
    def __init__(self, dut, signal_base_name, clk, ready_prefix="RDY_", enable_prefix="EN_"):
        super().__init__(dut, signal_base_name, clk, ready_prefix, enable_prefix)
        self.return_value_signal = None


class BluespecDataStream:

    def __init__(self, data, byte_num, start_byte_index, is_first, is_last):
        self.data = data
        self.byte_num = byte_num
        self.start_byte_index = start_byte_index
        self.is_first = is_first
        self.is_last = is_last


class BluespecPipeOut:
    def __init__(self, dut, signal_base_name, clk):
        self.dut = dut
        self.clk = clk
        self.signal_base_name = signal_base_name

        self.bsv_not_empty = BluespecValueMethod(
            dut, signal_base_name + "_notEmpty", clk)
        self.bsv_first = BluespecValueMethod(
            dut, signal_base_name + "_first", clk)
        self.bsv_deq = BluespecActionMethod(
            dut, signal_base_name + "_deq", clk)

        # self.not_empty_signal_name = signal_base_name + "_notEmpty"
        # self.not_empty_rdy_signal_name = "RDY_" + self.not_empty_signal_name

        # self.first_signal_name = signal_base_name + "_first"
        # self.first_rdy_signal_name = "RDY_ " + self.first_signal_name

        # self.deq_signal_name = signal_base_name + "_deq"
        # self.deq_rdy_signal_name = "RDY_" + self.deq_signal_name
        # self.deq_en_signal_name = "EN_" + self.deq_signal_name

    async def not_empty(self):
        return await self.bsv_not_empty()
        # not_empty_signal = getattr(self.dut, self.not_empty_signal_name)
        # return not_empty_signal.value

    async def deq(self):
        await self.bsv_deq()
        # deq_rdy_signal = getattr(self.dut, self.deq_rdy_signal_name)
        # deq_en_signal = getattr(self.dut, self.deq_en_signal_name)

        # async def _deassert_en_signal():
        #     print("_deassert_en_signal in pipe out run")
        #     await RisingEdge(self.clk)
        #     deq_en_signal.value = 0
        #     print("_deassert_en_signal pipe out set en to 0")

        # while not deq_rdy_signal.value:
        #     print("pipeout deq waiting ready signal")
        #     await RisingEdge(deq_rdy_signal)
        # deq_en_signal.value = 1
        # await cocotb.start(_deassert_en_signal())

    async def first(self):
        return await self.bsv_first()
        # first_rdy_signal = getattr(self.dut, self.first_rdy_signal_name)
        # first_signal = getattr(self.dut, self.first_signal_name)
        # while not first_rdy_signal.value:
        #     await RisingEdge(first_rdy_signal)
        # return first_signal.value


class BluespecPipeIn:
    def __init__(self, dut, signal_base_name, clk):
        self.dut = dut
        self.clk = clk
        self.signal_base_name = signal_base_name

        self.bsv_not_full = BluespecValueMethod(
            dut, signal_base_name + "_notFull", clk)
        self.bsv_enq = BluespecActionMethod(
            dut, signal_base_name + "_enq", clk)

        # self.not_full_signal_name = signal_base_name + "_notFull"
        # self.not_full_rdy_signal_name = "RDY_" + self.not_full_signal_name

        # self.enq_signal_name = signal_base_name + "_enq"
        # self.enq_data_signal_name = self.enq_signal_name + "_data"
        # self.enq_rdy_signal_name = "RDY_" + self.enq_signal_name
        # self.enq_en_signal_name = "EN_" + self.enq_signal_name

    async def not_full(self):
        return await self.bsv_not_full()
        # not_full_signal = getattr(self.dut, self.not_full_signal_name)
        # return not_full_signal.value

    async def enq(self, data):
        await self.bsv_enq(data=data)
        # enq_data_signal = getattr(self.dut, self.enq_data_signal_name)
        # enq_rdy_signal = getattr(self.dut, self.enq_rdy_signal_name)
        # enq_en_signal = getattr(self.dut, self.enq_en_signal_name)

        # async def _deassert_en_signal():
        #     print("_deassert_en_signal in pipe in run, ",
        #           cocotb.utils.get_sim_time(units='ns'))
        #     await RisingEdge(self.clk)
        #     enq_en_signal.value = 0
        #     print("_deassert_en_signal pipe in set en to 0 ",
        #           cocotb.utils.get_sim_time(units='ns'))

        # while not enq_rdy_signal.value:
        #     await RisingEdge(enq_rdy_signal)
        # enq_en_signal.value = 1
        # enq_data_signal.value = data
        # print("aaaaaaa=", cocotb.utils.get_sim_time(units='ns'))
        # await cocotb.start(_deassert_en_signal())
        # print("bbbbbbb=", cocotb.utils.get_sim_time(units='ns'))
