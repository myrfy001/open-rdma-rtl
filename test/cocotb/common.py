import os
from collections import deque
from abc import ABC

import asyncio

import cocotb
from cocotb.triggers import RisingEdge, ReadWrite
from cocotb.binary import BinaryValue


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


class BluespecType(ABC):
    def pack(self) -> int:
        return 0

    def unpack(self, val):
        pass

    def width(self):
        pass


class BluespecBits(BluespecType):
    def __init__(self, value=None, width=None):
        self._inner = BinaryValue(value, n_bits=width)

    def pack(self):
        return self._inner.integer

    def width(self):
        return self._inner.n_bits


class BluespecStruct(BluespecType):
    def __init__(self, **members):
        self.members = members
        self._width = 0
        for member in members.values():
            self._width += member.width()

    def pack(self):
        packed_val = 0
        for member in self.members.values():
            member_packed_val = member.pack()
            packed_val = (packed_val << member.width()) | member_packed_val
        return packed_val

    def width(self):
        return self._width


class BluespecDataStream256(BluespecStruct):
    def __init__(self, data, byte_num, start_byte_index, is_first, is_last):
        data = BluespecBits(data, width=256)
        byte_num = BluespecBits(byte_num, width=6)
        start_byte_index = BluespecBits(start_byte_index, width=5)
        is_first = BluespecBits(is_first, width=1)
        is_last = BluespecBits(is_last, width=1)
        super().__init__(data=data, byte_num=byte_num,
                         start_byte_index=start_byte_index, is_first=is_first, is_last=is_last)


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

    async def not_empty(self):
        return await self.bsv_not_empty()

    async def deq(self):
        await self.bsv_deq()

    async def first(self):
        return await self.bsv_first()


class BluespecPipeIn:
    def __init__(self, dut, signal_base_name, clk):
        self.dut = dut
        self.clk = clk
        self.signal_base_name = signal_base_name

        self.bsv_not_full = BluespecValueMethod(
            dut, signal_base_name + "_notFull", clk)
        self.bsv_enq = BluespecActionMethod(
            dut, signal_base_name + "_enq", clk)

    async def not_full(self):
        return await self.bsv_not_full()

    async def enq(self, data):
        await self.bsv_enq(data=data)
