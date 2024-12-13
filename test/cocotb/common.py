import os
from collections import deque, OrderedDict
from abc import ABC
import logging

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
        self.__dict__["_members"] = OrderedDict()
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

    def __setattr__(self, name, value):
        if name in self._members:
            self._members[name] = self._members_def[name].unpack(value)
            return
        return super().__setattr__(name, value)

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

    def __call__(self):
        ret = super().__call__()
        return ret == 1


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


class SimplePcieBehaviorModel(object):
    def __init__(self, dut, requester_ifc_base_names, completer_ifc_base_name):
        self.dut = dut

        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.INFO)

        self.clock = dut.CLK
        self.resetn = dut.RST_N

        self.requester_write_meta_pipes = []
        self.requester_write_data_pipes = []
        self.requester_read_meta_pipes = []
        self.requester_read_data_pipes = []

        for base_name in requester_ifc_base_names:
            self.requester_write_meta_pipes.append(BluespecPipeOut(
                dut, f"{base_name}_writePipeIfc_writeMetaPipeOut", self.clock))
            self.requester_write_data_pipes.append(BluespecPipeOut(
                dut, f"{base_name}_writePipeIfc_writeDataPipeOut", self.clock))
            self.requester_read_meta_pipes.append(BluespecPipeOut(
                dut, f"{base_name}_readPipeIfc_readMetaPipeOut", self.clock))
            self.requester_read_data_pipes.append(BluespecPipeIn(
                dut, f"{base_name}_readPipeIfc_readDataPipeIn", self.clock))

        self.channel_cnt = len(requester_ifc_base_names)

        self.mem = [0] * (1 << 25)

        for channel_idx in range(self.channel_cnt):
            cocotb.start_soon(self.handle_requester_write_req(channel_idx))
            cocotb.start_soon(self.handle_requester_read_req(channel_idx))

    async def handle_requester_write_req(self, channel_idx):
        # loop to handle each request
        while True:
            if await self.requester_write_meta_pipes[channel_idx].not_empty():
                write_meta_raw = await self.requester_write_meta_pipes[channel_idx].first()
                await self.requester_write_meta_pipes[channel_idx].deq()
                write_meta = BlueRdmaDtldStreamMemAccessMeta.unpack(
                    write_meta_raw)

                cur_write_addr = write_meta.addr()
                total_len = 0

                self.log.debug(
                    f"cur_write_addr={hex(cur_write_addr)}, total_len={hex(write_meta.total_len())}")
                # loop to handle each beat in a request
                while True:
                    if await self.requester_write_data_pipes[channel_idx].not_empty():
                        write_data_raw = await self.requester_write_data_pipes[channel_idx].first()
                        await self.requester_write_data_pipes[channel_idx].deq()
                        write_data = BlueRdmaDataStream256.unpack(
                            write_data_raw)

                        data = write_data.data()
                        if (write_data.is_first()):
                            data >>= (write_data.start_byte_index() * 8)

                        old_write_addr = cur_write_addr
                        for _ in range(write_data.byte_num()):
                            self.mem[cur_write_addr] = data & 0xff
                            data >>= 8
                            cur_write_addr += 1

                        total_len += write_data.byte_num()
                        self.log.debug(
                            f"write_addr = {hex(old_write_addr)}, write_data={write_data}", )

                        if (write_data.is_last()):
                            assert total_len == write_meta.total_len()
                            break
                    await RisingEdge(self.clock)  # wait for next beat

            await RisingEdge(self.clock)  # wait for next write req

    async def handle_requester_read_req(self, channel_idx):
        # loop to handle each request
        while True:
            if await self.requester_read_meta_pipes[channel_idx].not_empty():
                read_meta_raw = await self.requester_read_meta_pipes[channel_idx].first()
                await self.requester_read_meta_pipes[channel_idx].deq()
                read_meta = BlueRdmaDtldStreamMemAccessMeta.unpack(
                    read_meta_raw)

                cur_read_addr = read_meta.addr()
                bytes_left = read_meta.total_len()
                is_first = True
                self.log.debug(
                    f"cur_read_addr={hex(cur_read_addr)}, bytes_left={hex(bytes_left)}")
                # loop to handle each beat in a request
                while True:
                    if await self.requester_read_data_pipes[channel_idx].not_full():
                        data = 0

                        if is_first:
                            start_byte_index = cur_read_addr & 0x03
                        else:
                            start_byte_index = 0

                        if bytes_left + start_byte_index <= 32:
                            is_last = True
                            byte_num = bytes_left
                        else:
                            is_last = False
                            byte_num = 32 - start_byte_index

                        old_read_addr = cur_read_addr
                        for byte_idx in range(byte_num):
                            data |= (self.mem[cur_read_addr] << (byte_idx * 8))
                            cur_read_addr += 1

                        if (is_first):
                            data <<= (start_byte_index * 8)

                        read_data = BlueRdmaDataStream256(
                            data=data.to_bytes(32, byteorder="little"),
                            byte_num=byte_num,
                            start_byte_index=start_byte_index,
                            is_first=is_first,
                            is_last=is_last
                        )
                        await self.requester_read_data_pipes[channel_idx].enq(read_data.pack())
                        self.log.debug(
                            f"addr={hex(old_read_addr)}, read_data={read_data}")

                        is_first = False
                        bytes_left -= byte_num

                        if (is_last):
                            break
                    await RisingEdge(self.clock)  # wait for next beat

            await RisingEdge(self.clock)  # wait for next read req
