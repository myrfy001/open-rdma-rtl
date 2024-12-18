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
    } BitmapWindowStorageEntry#(type tData, type tBoundary) deriving(Bits, FShow);
    '''
    for channel_idx in range(2):
        with open(os.path.join(out_path, f"init_bram_psn_merge_storage_ch{channel_idx}.bin"), "w") as fo:
            for i in range(512):
                data_part = "1" * 128                       # -1
                left_boundary_part = "1" * 20               # -1
                epoch_part = "0" * 4                        # 0
                channel_idx_part = f"{channel_idx}" * 1
                fo.write(data_part + left_boundary_part +
                         epoch_part + channel_idx_part + "\n")


def gen_init_bram_psn_incr_storage():
    with open(os.path.join(out_path, "init_bram_psn_incr_storage.bin"), "w") as fo:
        for i in range(512):
            data_part = "0" * 24
            fo.write(data_part + "\n")


if __name__ == "__main__":
    gen_init_bram_psn_merge_storage()
    gen_init_bram_psn_incr_storage()
