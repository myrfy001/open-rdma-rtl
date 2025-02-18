# coding utf-8

import sys
import os

out_path = sys.argv[1]

MAX_QP_CNT = 1024


def gen_init_bram_psn_merge_storage():
    '''
    typedef struct {
        tData                               data;
        tBoundary                           leftBound;
        KeyQP                               qpnKeyPart;
    } BitmapWindowStorageEntry#(type tData, type tBoundary) deriving(Bits, FShow);
    '''

    with open(os.path.join(out_path, f"init_bram_psn_merge_storage.bin"), "w") as fo:
        for i in range(MAX_QP_CNT):
            data_part = "1" * 128                       # -1
            left_boundary_part = "1" * 20               # -1
            qpn_key_part = "0" * 14                     # 0
            fo.write(data_part + left_boundary_part +
                     qpn_key_part + "\n")


def gen_init_bram_auto_ack_meta_storage():

    with open(os.path.join(out_path, f"init_bram_auto_ack_meta_storage.bin"), "w") as fo:
        for i in range(MAX_QP_CNT):
            last_entry_receive_time = "0" * 32
            ack_msn = "0" * 16
            has_reported = "1" * 1

            fo.write(last_entry_receive_time + ack_msn +
                     has_reported + "\n")


def gen_init_bram_last_report_time():
    with open(os.path.join(out_path, f"init_bram_auto_ack_last_report_time.bin"), "w") as fo:
        for i in range(MAX_QP_CNT):
            last_report_time = "0" * 32
            fo.write(last_report_time + "\n")


if __name__ == "__main__":
    gen_init_bram_psn_merge_storage()
    gen_init_bram_auto_ack_meta_storage()
    gen_init_bram_last_report_time()
