import numpy as np
from golden_conv import conv2d_int8

IC, OC, H, W = 3, 4, 8, 8
rng = np.random.default_rng(7)
x = rng.integers(-8, 8, size=(IC, H, W), dtype=np.int8)
w = rng.integers(-3, 4, size=(OC, IC, 3, 3), dtype=np.int8)
b = rng.integers(-16, 16, size=(OC,), dtype=np.int32)
y = conv2d_int8(x, w, b, relu=True, shift=2, quant=True)

np.savetxt('vectors/input_feature_map.mem', x.flatten(), fmt='%d')
np.savetxt('vectors/weights.mem', w.flatten(), fmt='%d')
np.savetxt('vectors/bias.mem', b.flatten(), fmt='%d')
np.savetxt('vectors/expected_output.mem', y.flatten(), fmt='%d')
print('Generated vectors for IC=3 OC=4 H=8 W=8')
