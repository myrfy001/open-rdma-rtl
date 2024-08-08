# coding utf-8

import sys
import os

out_path = sys.argv[1]


def gen_init_bram_psn_merge_storage():
    with open(os.path.join(out_path, "init_bram_psn_merge_storage.bin"), "w") as fo:
        '''
        typedef struct {
            tData       data;
            tBoundary   leftBound;
        } BitmapWindowStorageEntry#(type tData, type tBoundary) deriving(Bits, FShow);
        '''
        for i in range(512):
            data_part = "1" * 128              # -1
            left_boundary_part = "1" * 20      # -1
            fo.write(data_part + left_boundary_part + "\n")


if __name__ == "__main__":
    gen_init_bram_psn_merge_storage()
