#include "xil_io.h"
#include "xil_printf.h"
#include "sleep.h"
#include <stdint.h>

#define CNN_BASE        0x43C00000U

#define REG_CONTROL     0x000U
#define REG_STATUS      0x004U
#define REG_WIDTH       0x008U
#define REG_HEIGHT      0x00CU
#define REG_MODE_FLAGS  0x010U
#define REG_PIXEL_IN    0x020U
#define REG_PIXEL_INDEX 0x024U
#define REG_RESULT_DATA 0x030U
#define REG_RESULT_STAT 0x034U
#define REG_WEIGHT_BASE 0x100U
#define REG_BIAS_BASE   0x400U

#define NUM_INPUT_CHANNELS   3
#define NUM_OUTPUT_CHANNELS  4
#define KERNEL_TAPS          9
#define NUM_WEIGHTS          (NUM_INPUT_CHANNELS * NUM_OUTPUT_CHANNELS * KERNEL_TAPS)

static inline void cnn_write(uint32_t offset, uint32_t value)
{
    Xil_Out32(CNN_BASE + offset, value);
}

static inline uint32_t cnn_read(uint32_t offset)
{
    return Xil_In32(CNN_BASE + offset);
}

static void load_weights_identity_like(void)
{
    for (uint32_t i = 0; i < NUM_WEIGHTS; i++) {
        cnn_write(REG_WEIGHT_BASE + (i * 4), 0);
    }

    /*
     * Simple 1x1-style test weights.
     * Center tap = index 4 in each 3x3 kernel.
     *
     * oc0 reads input channel 0
     * oc1 reads input channel 1
     * oc2 reads input channel 2
     * oc3 adds all 3 input channels
     */
    uint32_t idx;

    idx = (((0 * NUM_INPUT_CHANNELS) + 0) * KERNEL_TAPS) + 4;
    cnn_write(REG_WEIGHT_BASE + (idx * 4), 1);

    idx = (((1 * NUM_INPUT_CHANNELS) + 1) * KERNEL_TAPS) + 4;
    cnn_write(REG_WEIGHT_BASE + (idx * 4), 1);

    idx = (((2 * NUM_INPUT_CHANNELS) + 2) * KERNEL_TAPS) + 4;
    cnn_write(REG_WEIGHT_BASE + (idx * 4), 1);

    idx = (((3 * NUM_INPUT_CHANNELS) + 0) * KERNEL_TAPS) + 4;
    cnn_write(REG_WEIGHT_BASE + (idx * 4), 1);

    idx = (((3 * NUM_INPUT_CHANNELS) + 1) * KERNEL_TAPS) + 4;
    cnn_write(REG_WEIGHT_BASE + (idx * 4), 1);

    idx = (((3 * NUM_INPUT_CHANNELS) + 2) * KERNEL_TAPS) + 4;
    cnn_write(REG_WEIGHT_BASE + (idx * 4), 1);
}

static void load_bias_zero(void)
{
    for (uint32_t oc = 0; oc < NUM_OUTPUT_CHANNELS; oc++) {
        cnn_write(REG_BIAS_BASE + (oc * 4), 0);
    }
}

int main(void)
{
    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf(" Zynq CNN Accelerator Bare-Metal Test\r\n");
    xil_printf("========================================\r\n");

    xil_printf("CNN base address: 0x%08x\r\n", CNN_BASE);

    xil_printf("Clearing accelerator...\r\n");
    cnn_write(REG_CONTROL, 0x2);
    usleep(1000);

    xil_printf("Configuring image size...\r\n");
    cnn_write(REG_WIDTH,  4);
    cnn_write(REG_HEIGHT, 4);

    /*
     * mode flags:
     * bit 0 = kernel_mode
     * bit 1 = relu_enable
     * bit 2 = bias_enable
     * bit 3 = quant_enable
     *
     * Start simple:
     * relu on, bias off, quant off.
     */
    cnn_write(REG_MODE_FLAGS, 0x2);

    xil_printf("Loading weights...\r\n");
    load_weights_identity_like();

    xil_printf("Loading bias...\r\n");
    load_bias_zero();

    xil_printf("Starting accelerator...\r\n");
    cnn_write(REG_CONTROL, 0x1);
    usleep(1000);

    xil_printf("Writing 4x4 RGB test image...\r\n");

    for (uint32_t y = 0; y < 4; y++) {
        for (uint32_t x = 0; x < 4; x++) {
            uint32_t r = x + 1;
            uint32_t g = y + 1;
            uint32_t b = x + y + 1;

            cnn_write(REG_PIXEL_IN, r);
            cnn_write(REG_PIXEL_IN, g);
            cnn_write(REG_PIXEL_IN, b);
        }
    }

    usleep(10000);

    uint32_t status = cnn_read(REG_STATUS);
    uint32_t result_stat = cnn_read(REG_RESULT_STAT);

    xil_printf("Status      = 0x%08x\r\n", status);
    xil_printf("Result stat = 0x%08x\r\n", result_stat);

    uint32_t expected_results = 0;

    if ((cnn_read(REG_WIDTH) >= 3) && (cnn_read(REG_HEIGHT) >= 3)) {
        expected_results = (cnn_read(REG_WIDTH) - 2) *
                           (cnn_read(REG_HEIGHT) - 2) *
                           NUM_OUTPUT_CHANNELS;
    }

    xil_printf("Expected results = %d\r\n", expected_results);
    xil_printf("Reading result words:\r\n");

    for (uint32_t i = 0; i < expected_results; i++) {
        uint32_t result = cnn_read(REG_RESULT_DATA);
        xil_printf("result[%02d] = 0x%08x\r\n", i, result);
    }

    xil_printf("Test done.\r\n");

    while (1) {
        sleep(1);
    }

    return 0;
}
