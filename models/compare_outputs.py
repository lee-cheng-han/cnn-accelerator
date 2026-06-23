import sys
import numpy as np

expected = np.loadtxt(sys.argv[1], dtype=int)
actual = np.loadtxt(sys.argv[2], dtype=int)
if expected.shape != actual.shape:
    raise SystemExit(f'FAIL shape mismatch expected {expected.shape}, actual {actual.shape}')
errors = np.nonzero(expected != actual)[0]
if len(errors):
    print(f'FAIL {len(errors)} mismatches')
    for idx in errors[:20]:
        print(idx, expected[idx], actual[idx])
    raise SystemExit(1)
print('PASS outputs match')
