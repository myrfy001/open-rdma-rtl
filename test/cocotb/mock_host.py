# coding:utf-8
import os
import gc
import socket
from ctypes import *
from enum import IntEnum
from multiprocessing import shared_memory
import threading
import time
import json
import errno
import base64
import collections

from abc import ABC, abstractmethod


class MockHostMem:
    def __init__(self, shared_mem_name, shared_mem_size) -> None:
        self.shared_mem_name = shared_mem_name
        self.shared_mem_size = shared_mem_size

        try:
            self.shared_mem_obj = shared_memory.SharedMemory(
                shared_mem_name, True, shared_mem_size)
            print("create new shared memory file")
        except FileExistsError:
            self.shared_mem_obj = shared_memory.SharedMemory(
                shared_mem_name, False, shared_mem_size)
            print("open exist shared memory file")

        self.buf = self.shared_mem_obj.buf

        self.buf[:] = b"\0" * shared_mem_size

    def close(self):
        gc.collect()
        self.shared_mem_obj.close()
        self.shared_mem_obj.unlink()


def open_shared_mem_to_hw_simulator(mem_size, shared_mem_file=None):
    if shared_mem_file is None:
        shared_mem_file = "/bluesim1"
    host_mem = MockHostMem(shared_mem_file, mem_size)
    return host_mem


class UserspaceDriverServer:
    def __init__(self, listen_addr, listen_port: int, csr_write_cb, csr_read_cb) -> None:
        self.listen_addr = listen_addr
        self.driver_listen_port = listen_port
        self.csr_write_cb = csr_write_cb
        self.csr_read_cb = csr_read_cb

    def run(self):
        self.stop_flag = False

        self.server_thread = threading.Thread(target=self._run, args=(
            self.listen_addr, self.driver_listen_port))
        self.server_thread.start()

    def stop(self):
        self.stop_flag = True

    def _run(self, listen_addr, listen_port):

        server_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind((listen_addr, listen_port))
        server_socket.settimeout(0.5)
        while not self.stop_flag:
            try:
                recv_raw, resp_addr = server_socket.recvfrom(1024)
            except:
                continue
            recv_req = json.loads(recv_raw)
            if recv_req["is_write"]:
                self.csr_write_cb(
                    recv_req["addr"], recv_req["value"])
            else:
                value = self.csr_read_cb(recv_req["addr"])
                server_socket.sendto(json.dumps(
                    {"value": value, "addr": recv_req["addr"], "is_write": False}).encode("utf-8"), resp_addr)

        server_socket.close()


class EthPacketRpc:
    def __init__(self, inst_id):
        self.inst_id = inst_id
        self.peer_inst_id = "1" if self.inst_id == "2" else "2"

        self.to_peer_pipe_name = f"/tmp/bluerdma-sim-eth-rpc-pipe-{self.inst_id}-to-{self.peer_inst_id}"
        self.from_peer_pipe_name = f"/tmp/bluerdma-sim-eth-rpc-pipe-{self.peer_inst_id}-to-{self.inst_id}"

        try:
            os.mkfifo(self.to_peer_pipe_name)
        except OSError as e:
            if e.errno != errno.EEXIST:  # ignore exist
                raise

        try:
            os.mkfifo(self.from_peer_pipe_name)
        except OSError as e:
            if e.errno != errno.EEXIST:  # ignore exist
                raise

        self.read_buf = collections.deque()
        self.write_buf = collections.deque()

        self.read_thread = threading.Thread(target=self._get_packet_task)
        self.write_thread = threading.Thread(target=self._put_packet_task)
        self.read_thread.start()
        self.write_thread.start()

    def send_packet(self, buf):
        self.write_buf.append(base64.standard_b64encode(buf).decode() + "\n")

    def recv_packet(self):
        if len(self.read_buf) == 0:
            return None
        return self.read_buf.popleft()

    def _get_packet_task(self):
        self.from_peer_pipe = open(self.from_peer_pipe_name, "r")
        while True:
            packet_b64 = self.from_peer_pipe.readline()
            packet_bytes = base64.standard_b64decode(packet_b64)
            self.read_buf.append(packet_bytes)

    def _put_packet_task(self):
        self.to_peer_pipe = open(self.to_peer_pipe_name, "w")
        while True:
            if len(self.write_buf) == 0:
                time.sleep(0.001)
                continue
            packet_b64 = self.write_buf.popleft()
            self.to_peer_pipe.write(packet_b64)
