import numpy as np


def sat_int8(x: int) -> int:
    return max(-128, min(127, int(x)))


def conv2d_int8(x, w, b, relu=True, shift=0, quant=True):
    """x: ICxHxW int8, w: OCxICx3x3 int8, b: OC int32"""
    x = np.asarray(x, dtype=np.int32)
    w = np.asarray(w, dtype=np.int32)
    b = np.asarray(b, dtype=np.int32)
    ic, h, width = x.shape
    oc = w.shape[0]
    out_h = h - 2
    out_w = width - 2
    y = np.zeros((oc, out_h, out_w), dtype=np.int32)
    for o in range(oc):
        for r in range(out_h):
            for c in range(out_w):
                acc = 0
                for i in range(ic):
                    acc += int(np.sum(x[i, r:r+3, c:c+3] * w[o, i]))
                acc += int(b[o])
                if relu and acc < 0:
                    acc = 0
                if quant:
                    acc >>= shift
                y[o, r, c] = sat_int8(acc)
    return y.astype(np.int8)
