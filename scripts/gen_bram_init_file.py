# coding utf-8

import sys
import os

out_path = sys.argv[1]


def gen_init_bram_psn_merge_storage():
    '''
    typedef struct {
        tData       data;
        tBoundary   leftBound;
        OooWindowBitmapStorageEntryEpoch    epoch;
        OooWindowBitmapStorageChannelIdx    channelIdx;
        KeyQP                               qpnKeyPart;
    } BitmapWindowStorageEntry#(type tData, type tBoundary) deriving(Bits, FShow);
    '''
    for channel_idx in range(2):
        with open(os.path.join(out_path, f"init_bram_psn_merge_storage_ch{channel_idx}.bin"), "w") as fo:
            for i in range(512):
                data_part = "1" * 128                       # -1
                left_boundary_part = "1" * 20               # -1
                epoch_part = "0" * 4                        # 0
                qpn_key_part = "0" * 14                     # 0
                channel_idx_part = f"{channel_idx}" * 1
                fo.write(data_part + left_boundary_part +
                         epoch_part + channel_idx_part + qpn_key_part + "\n")


def gen_init_bram_auto_ack_meta_storage():
    for channel_idx in range(2):
        with open(os.path.join(out_path, f"init_bram_auto_ack_meta_storage_ch{channel_idx}.bin"), "w") as fo:
            for i in range(512):
                last_entry_receive_time = "0" * 32
                ack_msn = "0" * 16
                has_reported = "0" * 1
                epoch_part = "0" * 4                        # 0
                channel_idx_part = f"{channel_idx}" * 1
                fo.write(last_entry_receive_time + ack_msn +
                         has_reported + epoch_part + channel_idx_part + "\n")


def gen_init_bram_last_report_time():
    with open(os.path.join(out_path, f"init_bram_auto_ack_last_report_time.bin"), "w") as fo:
        for i in range(512):
            last_report_time = "0" * 32
            fo.write(last_report_time + "\n")


if __name__ == "__main__":
    gen_init_bram_psn_merge_storage()
    gen_init_bram_auto_ack_meta_storage()
    gen_init_bram_last_report_time()
