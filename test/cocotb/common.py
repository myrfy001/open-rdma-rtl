import os
from collections import deque, OrderedDict
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
    _width = 0

    def __init__(self, value=None):
        if not isinstance(value, BluespecBits):
            self._inner = BinaryValue(
                value, n_bits=self._width, bigEndian=False)
        else:
            self._inner = BinaryValue(
                value.pack(), n_bits=value.width(), bigEndian=False)

    def pack(self):
        return self._inner.integer

    @classmethod
    def unpack(cls, val):
        return cls(val)

    @classmethod
    def width(cls):
        return cls._width

    def __str__(self):
        return str(hex(self._inner.integer))

    def __call__(self):
        return self.pack()


class BluespecStruct(BluespecType):
    _members_def = OrderedDict()

    def __init__(self, *members):
        self._members = OrderedDict()
        self._width = 0

        for ((member_name, member_type), member_inst) in zip(self._members_def.items(), members):
            assert isinstance(member_inst, member_type)
            self._members[member_name] = member_inst
            self._width += member_type.width()

    def pack(self):
        packed_val = 0
        for member in self._members.values():
            member_packed_val = member.pack()
            packed_val = (packed_val << member.width()) | member_packed_val
        return packed_val

    def width(self):
        return self._width

    def __getattr__(self, name):
        if name in self._members:
            return self._members[name]
        return super().__getattribute__(name)

    @classmethod
    def unpack(cls, val):
        args = []
        for member_type in reversed(cls._members_def.values()):
            mask = (1 << member_type.width()) - 1
            member_val = val & mask
            args.append(member_type.unpack(member_val))
            val = val >> member_type.width()

        args.reverse()
        ret = cls(*args)
        return ret


class BluespecBool(BluespecBits):
    _width = 1


class BlueRdmaData256(BluespecBits):
    _width = 256


class BlueRdmaData256ByteNum(BluespecBits):
    _width = 6


class BlueRdmaData256ByteIndex(BluespecBits):
    _width = 5


class BlueRdmaLength(BluespecBits):
    _width = 32


class BlueRdmaAddr(BluespecBits):
    _width = 64


class BlueRdmaDataStream256(BluespecStruct):
    _members_def = OrderedDict(
        data=BlueRdmaData256,
        byte_num=BlueRdmaData256ByteNum,
        start_byte_index=BlueRdmaData256ByteIndex,
        is_first=BluespecBool,
        is_last=BluespecBool
    )

    def __init__(self, data, byte_num, start_byte_index, is_first, is_last):
        data = BlueRdmaData256(data)
        byte_num = BlueRdmaData256ByteNum(byte_num)
        start_byte_index = BlueRdmaData256ByteIndex(start_byte_index)
        is_first = BluespecBool(is_first)
        is_last = BluespecBool(is_last)
        super().__init__(data, byte_num, start_byte_index, is_first, is_last)

    def __str__(self):
        return (
            f"< BlueRdmaDataStream256 "
            f"data={self.data}, "
            f"byte_num={self.byte_num}, "
            f"start_byte_index={self.start_byte_index}, "
            f"is_first={self.is_first}, "
            f"is_last={self.is_last} >"
        )


class BlueRdmaDtldStreamMemAccessMeta(BluespecStruct):
    _members_def = OrderedDict(
        addr=BlueRdmaAddr,
        total_len=BlueRdmaLength,
    )

    def __init__(self, addr, total_len):
        addr = BlueRdmaAddr(addr)
        total_len = BlueRdmaLength(total_len)

        super().__init__(addr, total_len)

    def __str__(self):
        return (
            f"< BlueRdmaDtldStreamMemAccessMeta "
            f"addr={self.addr}, "
            f"total_len={self.total_len} >"
        )


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
