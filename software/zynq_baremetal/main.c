#include "xil_io.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xiltimer.h"
#include "xtimer_config.h"
#include "sleep.h"
#include <stdint.h>
#include <stddef.h>

#include "generated/test_image.h"
#include "generated/expected_output.h"

#define CNN_BASE        0x43C00000U
#define DMA_BASE        0x40400000U

#define REG_CONTROL     0x000U
#define REG_STATUS      0x004U
#define REG_WIDTH       0x008U
#define REG_HEIGHT      0x00CU
#define REG_MODE_FLAGS  0x010U
#define REG_RESULT_STAT 0x034U
#define REG_WEIGHT_BASE 0x100U
#define REG_BIAS_BASE   0x400U

#define CNN_CONTROL_START 0x00000001U
#define CNN_CONTROL_CLEAR 0x00000002U

#define CNN_STATUS_BUSY         0x00000002U
#define CNN_STATUS_DONE         0x00000004U
#define CNN_STATUS_RESULT_VALID 0x00000008U
#define CNN_STATUS_RESULT_LAST  0x00000010U

#define CNN_RESULT_VALID        0x00000001U
#define CNN_RESULT_LAST         0x00000002U

#define NUM_INPUT_CHANNELS   3U
#define NUM_OUTPUT_CHANNELS  4U
#define KERNEL_TAPS          9U
#define NUM_WEIGHTS          (NUM_INPUT_CHANNELS * NUM_OUTPUT_CHANNELS * KERNEL_TAPS)

/*
 * AXI DMA simple-mode register map.
 * MM2S = memory to stream: DDR input image -> CNN input stream.
 * S2MM = stream to memory: CNN output stream -> DDR output buffer.
 */
#define DMA_MM2S_DMACR   0x00U
#define DMA_MM2S_DMASR   0x04U
#define DMA_MM2S_SA      0x18U
#define DMA_MM2S_LENGTH  0x28U

#define DMA_S2MM_DMACR   0x30U
#define DMA_S2MM_DMASR   0x34U
#define DMA_S2MM_DA      0x48U
#define DMA_S2MM_LENGTH  0x58U

#define DMA_CR_RUNSTOP   0x00000001U
#define DMA_CR_RESET     0x00000004U

#define DMA_SR_HALTED      0x00000001U
#define DMA_SR_IDLE        0x00000002U
#define DMA_SR_SG_INCLD    0x00000008U
#define DMA_SR_DMA_INT_ERR 0x00000010U
#define DMA_SR_DMA_SLV_ERR 0x00000020U
#define DMA_SR_DMA_DEC_ERR 0x00000040U
#define DMA_SR_SG_INT_ERR  0x00000100U
#define DMA_SR_SG_SLV_ERR  0x00000200U
#define DMA_SR_SG_DEC_ERR  0x00000400U
#define DMA_SR_IOC_IRQ     0x00001000U
#define DMA_SR_DLY_IRQ     0x00002000U
#define DMA_SR_ERR_IRQ     0x00004000U
#define DMA_SR_IRQ_ALL     (DMA_SR_IOC_IRQ | DMA_SR_DLY_IRQ | DMA_SR_ERR_IRQ)
#define DMA_SR_ERR_ALL     (DMA_SR_DMA_INT_ERR | DMA_SR_DMA_SLV_ERR | DMA_SR_DMA_DEC_ERR | \
                            DMA_SR_SG_INT_ERR | DMA_SR_SG_SLV_ERR | DMA_SR_SG_DEC_ERR | \
                            DMA_SR_ERR_IRQ)

#define DMA_TIMEOUT      10000000U
#define CNN_TIMEOUT      10000000U

#define MAX_INPUT_PIXELS  IMAGE_PIXELS
#define MAX_OUTPUT_WORDS  EXPECTED_OUTPUT_WORDS

static uint32_t input_buffer[MAX_INPUT_PIXELS] __attribute__((aligned(64)));
static int32_t  output_buffer[MAX_OUTPUT_WORDS] __attribute__((aligned(64)));
static uint32_t last_dma_cnn_cycles;
static uint32_t last_dma_cnn_usec;

static inline void cnn_write(uint32_t offset, uint32_t value)
{
    Xil_Out32(CNN_BASE + offset, value);
}

static inline uint32_t cnn_read(uint32_t offset)
{
    return Xil_In32(CNN_BASE + offset);
}

static inline void dma_write(uint32_t offset, uint32_t value)
{
    Xil_Out32(DMA_BASE + offset, value);
}

static inline uint32_t dma_read(uint32_t offset)
{
    return Xil_In32(DMA_BASE + offset);
}

static void print_dma_status_bits(const char *name, uint32_t status)
{
    xil_printf("%s status decode:", name);

    if ((status & DMA_SR_HALTED) != 0U) {
        xil_printf(" halted");
    }
    if ((status & DMA_SR_IDLE) != 0U) {
        xil_printf(" idle");
    }
    if ((status & DMA_SR_SG_INCLD) != 0U) {
        xil_printf(" sg-included");
    }
    if ((status & DMA_SR_DMA_INT_ERR) != 0U) {
        xil_printf(" dma-internal-error");
    }
    if ((status & DMA_SR_DMA_SLV_ERR) != 0U) {
        xil_printf(" dma-slave-error");
    }
    if ((status & DMA_SR_DMA_DEC_ERR) != 0U) {
        xil_printf(" dma-decode-error");
    }
    if ((status & DMA_SR_SG_INT_ERR) != 0U) {
        xil_printf(" sg-internal-error");
    }
    if ((status & DMA_SR_SG_SLV_ERR) != 0U) {
        xil_printf(" sg-slave-error");
    }
    if ((status & DMA_SR_SG_DEC_ERR) != 0U) {
        xil_printf(" sg-decode-error");
    }
    if ((status & DMA_SR_IOC_IRQ) != 0U) {
        xil_printf(" complete");
    }
    if ((status & DMA_SR_DLY_IRQ) != 0U) {
        xil_printf(" delay-irq");
    }
    if ((status & DMA_SR_ERR_IRQ) != 0U) {
        xil_printf(" error-irq");
    }

    xil_printf("\r\n");
}

static void print_dma_status(const char *name, uint32_t status)
{
    xil_printf("%s status = 0x%08x\r\n", name, status);
    print_dma_status_bits(name, status);
}

static void print_cnn_status(uint32_t status, uint32_t result_stat)
{
    xil_printf("CNN status      = 0x%08x\r\n", status);
    xil_printf("CNN result stat = 0x%08x\r\n", result_stat);

    xil_printf("CNN status decode:");
    if ((status & CNN_STATUS_BUSY) != 0U) {
        xil_printf(" busy");
    }
    if ((status & CNN_STATUS_DONE) != 0U) {
        xil_printf(" done");
    }
    if ((status & CNN_STATUS_RESULT_VALID) != 0U) {
        xil_printf(" result-valid");
    }
    if ((status & CNN_STATUS_RESULT_LAST) != 0U) {
        xil_printf(" result-last");
    }
    xil_printf("\r\n");

    xil_printf("CNN result decode:");
    if ((result_stat & CNN_RESULT_VALID) != 0U) {
        xil_printf(" valid");
    }
    if ((result_stat & CNN_RESULT_LAST) != 0U) {
        xil_printf(" last");
    }
    xil_printf("\r\n");
}

static void load_weights_identity_like(uint32_t kernel_mode)
{
    for (uint32_t i = 0; i < NUM_WEIGHTS; i++) {
        cnn_write(REG_WEIGHT_BASE + (i * 4U), 0U);
    }

    /*
     * kernel_mode = 1: 3x3 mode, use center tap index 4.
     * kernel_mode = 0: 1x1 mode, RTL uses tap index 0.
     */
    uint32_t active_tap = kernel_mode ? 4U : 0U;
    uint32_t idx;

    idx = (((0U * NUM_INPUT_CHANNELS) + 0U) * KERNEL_TAPS) + active_tap;
    cnn_write(REG_WEIGHT_BASE + (idx * 4U), 1U);

    idx = (((1U * NUM_INPUT_CHANNELS) + 1U) * KERNEL_TAPS) + active_tap;
    cnn_write(REG_WEIGHT_BASE + (idx * 4U), 1U);

    idx = (((2U * NUM_INPUT_CHANNELS) + 2U) * KERNEL_TAPS) + active_tap;
    cnn_write(REG_WEIGHT_BASE + (idx * 4U), 1U);

    idx = (((3U * NUM_INPUT_CHANNELS) + 0U) * KERNEL_TAPS) + active_tap;
    cnn_write(REG_WEIGHT_BASE + (idx * 4U), 1U);

    idx = (((3U * NUM_INPUT_CHANNELS) + 1U) * KERNEL_TAPS) + active_tap;
    cnn_write(REG_WEIGHT_BASE + (idx * 4U), 1U);

    idx = (((3U * NUM_INPUT_CHANNELS) + 2U) * KERNEL_TAPS) + active_tap;
    cnn_write(REG_WEIGHT_BASE + (idx * 4U), 1U);
}

static void load_bias_zero(void)
{
    for (uint32_t oc = 0; oc < NUM_OUTPUT_CHANNELS; oc++) {
        cnn_write(REG_BIAS_BASE + (oc * 4U), 0U);
    }
}

static uint32_t expected_result_words(void)
{
    if (TEST_KERNEL_MODE == 0U) {
        return IMAGE_WIDTH * IMAGE_HEIGHT * NUM_OUTPUT_CHANNELS;
    }

    if ((IMAGE_WIDTH < 3U) || (IMAGE_HEIGHT < 3U)) {
        return 0U;
    }

    return (IMAGE_WIDTH - 2U) * (IMAGE_HEIGHT - 2U) * NUM_OUTPUT_CHANNELS;
}

static int dma_reset(void)
{
    dma_write(DMA_MM2S_DMACR, DMA_CR_RESET);
    dma_write(DMA_S2MM_DMACR, DMA_CR_RESET);

    for (uint32_t i = 0; i < DMA_TIMEOUT; i++) {
        uint32_t mm2s_cr = dma_read(DMA_MM2S_DMACR);
        uint32_t s2mm_cr = dma_read(DMA_S2MM_DMACR);

        if (((mm2s_cr & DMA_CR_RESET) == 0U) &&
            ((s2mm_cr & DMA_CR_RESET) == 0U)) {
            return 0;
        }
    }

    print_dma_status("DMA MM2S reset-timeout", dma_read(DMA_MM2S_DMASR));
    print_dma_status("DMA S2MM reset-timeout", dma_read(DMA_S2MM_DMASR));
    return -1;
}

static int dma_wait_done(uint32_t status_offset, const char *name)
{
    for (uint32_t i = 0; i < DMA_TIMEOUT; i++) {
        uint32_t status = dma_read(status_offset);

        if ((status & DMA_SR_ERR_ALL) != 0U) {
            xil_printf("[FAIL] %s DMA error while waiting for completion\r\n", name);
            print_dma_status(name, status);
            return -1;
        }

        if ((status & DMA_SR_IOC_IRQ) != 0U) {
            return 0;
        }
    }

    xil_printf("[FAIL] %s DMA timeout while waiting for completion\r\n", name);
    print_dma_status(name, dma_read(status_offset));
    return -1;
}

static int cnn_wait_done(void)
{
    for (uint32_t i = 0; i < CNN_TIMEOUT; i++) {
        uint32_t status = cnn_read(REG_STATUS);

        if ((status & CNN_STATUS_DONE) != 0U) {
            return 0;
        }
    }

    xil_printf("[FAIL] CNN accelerator done timeout\r\n");
    print_cnn_status(cnn_read(REG_STATUS), cnn_read(REG_RESULT_STAT));
    print_dma_status("DMA MM2S at CNN timeout", dma_read(DMA_MM2S_DMASR));
    print_dma_status("DMA S2MM at CNN timeout", dma_read(DMA_S2MM_DMASR));
    return -1;
}

static uint32_t cycles_to_usec(uint64_t cycles)
{
    return (uint32_t)((cycles * 1000000ULL) / COUNTS_PER_SECOND);
}

static int run_dma_transfer(uint32_t input_bytes, uint32_t output_bytes)
{
    XTime transfer_start;
    XTime transfer_end;

    xil_printf("Resetting AXI DMA...\r\n");

    if (dma_reset() != 0) {
        xil_printf("[FAIL] AXI DMA reset timeout\r\n");
        return -1;
    }

    print_dma_status("DMA MM2S after reset", dma_read(DMA_MM2S_DMASR));
    print_dma_status("DMA S2MM after reset", dma_read(DMA_S2MM_DMASR));

    /*
     * Clear old completion/error bits by writing 1s.
     */
    dma_write(DMA_MM2S_DMASR, DMA_SR_IRQ_ALL);
    dma_write(DMA_S2MM_DMASR, DMA_SR_IRQ_ALL);

    /*
     * Flush input so DMA sees latest CPU-written pixels.
     * Flush output too so cache does not hold dirty stale data.
     */
    Xil_DCacheFlushRange((UINTPTR)input_buffer, input_bytes);
    Xil_DCacheFlushRange((UINTPTR)output_buffer, output_bytes);

    /*
     * Start both DMA channels.
     * Start S2MM first so it is ready to receive CNN outputs.
     */
    dma_write(DMA_S2MM_DMACR, DMA_CR_RUNSTOP);
    dma_write(DMA_MM2S_DMACR, DMA_CR_RUNSTOP);

    dma_write(DMA_S2MM_DA, (uint32_t)(UINTPTR)output_buffer);
    dma_write(DMA_MM2S_SA, (uint32_t)(UINTPTR)input_buffer);

    xil_printf("Input buffer  address = 0x%08x\r\n", (uint32_t)(UINTPTR)input_buffer);
    xil_printf("Output buffer address = 0x%08x\r\n", (uint32_t)(UINTPTR)output_buffer);
    xil_printf("Input bytes  = %d\r\n", input_bytes);
    xil_printf("Output bytes = %d\r\n", output_bytes);

    /*
     * Writing LENGTH starts each simple-mode transfer.
     */
    XTime_GetTime(&transfer_start);

    dma_write(DMA_S2MM_LENGTH, output_bytes);
    dma_write(DMA_MM2S_LENGTH, input_bytes);

    if (dma_wait_done(DMA_MM2S_DMASR, "MM2S") != 0) {
        print_dma_status("S2MM peer at MM2S failure", dma_read(DMA_S2MM_DMASR));
        return -1;
    }

    if (dma_wait_done(DMA_S2MM_DMASR, "S2MM") != 0) {
        print_dma_status("MM2S peer at S2MM failure", dma_read(DMA_MM2S_DMASR));
        return -1;
    }

    XTime_GetTime(&transfer_end);
    uint64_t transfer_cycles = (uint64_t)(transfer_end - transfer_start);
    last_dma_cnn_cycles = (uint32_t)transfer_cycles;
    last_dma_cnn_usec = cycles_to_usec(transfer_cycles);

    Xil_DCacheInvalidateRange((UINTPTR)output_buffer, output_bytes);

    print_dma_status("DMA MM2S final", dma_read(DMA_MM2S_DMASR));
    print_dma_status("DMA S2MM final", dma_read(DMA_S2MM_DMASR));
    xil_printf("DMA+CNN transfer cycles = %d\r\n", last_dma_cnn_cycles);
    xil_printf("DMA+CNN transfer usec   = %d\r\n", last_dma_cnn_usec);

    return 0;
}

int main(void)
{
    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf(" Zynq CNN Accelerator DMA Test\r\n");
    xil_printf("========================================\r\n");

    xil_printf("CNN base address: 0x%08x\r\n", CNN_BASE);
    xil_printf("DMA base address: 0x%08x\r\n", DMA_BASE);

    xil_printf("Kernel mode = %s\r\n", TEST_KERNEL_NAME);
    xil_printf("Image size  = %d x %d\r\n", IMAGE_WIDTH, IMAGE_HEIGHT);
    xil_printf("Image pixels = %d\r\n", IMAGE_PIXELS);

    uint32_t expected_results = expected_result_words();

    xil_printf("Expected output words = %d\r\n", expected_results);
    xil_printf("Header output words   = %d\r\n", EXPECTED_OUTPUT_WORDS);

    if (expected_results != EXPECTED_OUTPUT_WORDS) {
        xil_printf("[FAIL] Output count mismatch: computed=%d header=%d\r\n",
                   expected_results, EXPECTED_OUTPUT_WORDS);
        while (1) {
            sleep(1);
        }
    }

    for (uint32_t i = 0; i < IMAGE_PIXELS; i++) {
        input_buffer[i] = input_image[i];
    }

    for (uint32_t i = 0; i < EXPECTED_OUTPUT_WORDS; i++) {
        output_buffer[i] = 0x55555555;
    }

    xil_printf("Clearing accelerator...\r\n");
    cnn_write(REG_CONTROL, CNN_CONTROL_CLEAR);
    usleep(1000);

    xil_printf("Configuring accelerator...\r\n");
    cnn_write(REG_WIDTH,  IMAGE_WIDTH);
    cnn_write(REG_HEIGHT, IMAGE_HEIGHT);

    uint32_t mode_flags = (TEST_KERNEL_MODE & 0x1U) | 0x2U;
    cnn_write(REG_MODE_FLAGS, mode_flags);

    xil_printf("Mode flags = 0x%08x\r\n", mode_flags);

    xil_printf("Loading weights...\r\n");
    load_weights_identity_like(TEST_KERNEL_MODE);

    xil_printf("Loading bias...\r\n");
    load_bias_zero();

    xil_printf("Starting accelerator...\r\n");
    cnn_write(REG_CONTROL, CNN_CONTROL_START);
    usleep(1000);

    uint32_t input_bytes = IMAGE_PIXELS * sizeof(uint32_t);
    uint32_t output_bytes = EXPECTED_OUTPUT_WORDS * sizeof(int32_t);

    xil_printf("Starting DMA transfer...\r\n");

    int dma_ok = run_dma_transfer(input_bytes, output_bytes);

    if (dma_ok != 0) {
        xil_printf("[FAIL] DMA transfer failed\r\n");
        print_cnn_status(cnn_read(REG_STATUS), cnn_read(REG_RESULT_STAT));
        while (1) {
            sleep(1);
        }
    }

    if (cnn_wait_done() != 0) {
        while (1) {
            sleep(1);
        }
    }

    uint32_t status = cnn_read(REG_STATUS);
    uint32_t result_stat = cnn_read(REG_RESULT_STAT);

    print_cnn_status(status, result_stat);

    xil_printf("Checking DMA output buffer against golden output...\r\n");

    uint32_t mismatches = 0;

    for (uint32_t i = 0; i < EXPECTED_OUTPUT_WORDS; i++) {
        int32_t result = output_buffer[i];

        if (result == expected_output[i]) {
            xil_printf("[PASS] result[%02d] = %d\r\n", i, result);
        } else {
            xil_printf("[FAIL] result[%02d] expected=%d got=%d\r\n",
                       i, expected_output[i], result);
            mismatches++;
        }
    }

    if (mismatches == 0U) {
        xil_printf("[PASS] CNN DMA accelerator test passed\r\n");
    } else {
        xil_printf("[FAIL] CNN DMA accelerator test failed, mismatches=%d\r\n", mismatches);
    }

    xil_printf("Test done.\r\n");

    while (1) {
        sleep(1);
    }

    return 0;
}
