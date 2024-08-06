# coding utf-8

import sys

out_fn = sys.argv[1]
bit_width = int(sys.argv[2])
depth = int(sys.argv[3])

data = "0" * int(bit_width)
out = "\n".join([data] * depth)

with open(out_fn, "w") as fo:
    fo.write(out)
