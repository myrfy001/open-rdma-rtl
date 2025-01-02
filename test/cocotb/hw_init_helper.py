import logging
from ringbufs import RingbufCommandReqQueue, RingbufCommandRespQueue, RingbufSendQueue, RingbufMetaReportQueue, RingbufSimpleNicTxQueue, RingbufSimpleNicRxQueue


class HardwareInitHelper:
    def __init__(self, pcie_bfm):
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        self.pcie_bfm = pcie_bfm
        self.ringbuf_buffer_size = 0x20000

        buffer_block_idx = 0
        self.cmd_req_queue = RingbufCommandReqQueue(
            self.pcie_bfm.mem,
            self.ringbuf_buffer_size * buffer_block_idx,
            self.pcie_bfm
        )
        buffer_block_idx += 1
        self.cmd_resp_queue = RingbufCommandRespQueue(
            self.pcie_bfm.mem,
            self.ringbuf_buffer_size * buffer_block_idx,
            self.pcie_bfm
        )
        buffer_block_idx += 1

        self.send_queues = []
        self.meta_report_queues = []

        for channel_idx in range(4):
            self.send_queues.append(
                RingbufSendQueue(
                    self.pcie_bfm.mem,
                    self.ringbuf_buffer_size * buffer_block_idx,
                    self.pcie_bfm,
                    channel_idx
                )
            )
            buffer_block_idx += 1

            self.meta_report_queues.append(
                RingbufMetaReportQueue(
                    self.pcie_bfm.mem,
                    self.ringbuf_buffer_size * buffer_block_idx,
                    self.pcie_bfm
                )
            )
            buffer_block_idx += 1

        self.simple_nix_tx_queue = RingbufSimpleNicTxQueue(
            self.pcie_bfm.mem,
            self.ringbuf_buffer_size * buffer_block_idx,
            self.pcie_bfm
        )
        buffer_block_idx += 1
        self.simple_nix_rx_queue = RingbufSimpleNicRxQueue(
            self.pcie_bfm.mem,
            self.ringbuf_buffer_size * buffer_block_idx,
            self.pcie_bfm
        )
        buffer_block_idx += 1

    async def do_init(self):
        self.cmd_req_queue.put_desc_set_udp_param(
            0x00000000,
            0xFFFFFF00,
            0x11223344,
            0xAABBCCDDEEFF
        )
        await self.cmd_req_queue.sync_pointers()
        resp = await self.cmd_resp_queue.deq_blocking()
        self.log.info(f"cmd resp queue got desc: {resp}")
