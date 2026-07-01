#include "xil_io.h"
#include "xil_printf.h"
#include "xil_cache.h"
#include "xparameters.h"
#include "xuartps.h"
#include "sleep.h"

#include <stdint.h>
#include <stddef.h>

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

#define NUM_INPUT_CHANNELS   3U
#define NUM_OUTPUT_CHANNELS  4U
#define KERNEL_TAPS          9U
#define NUM_WEIGHTS          (NUM_INPUT_CHANNELS * NUM_OUTPUT_CHANNELS * KERNEL_TAPS)

#define MAX_WIDTH            64U
#define MAX_HEIGHT           64U
#define MAX_INPUT_PIXELS     (MAX_WIDTH * MAX_HEIGHT)
#define MAX_OUTPUT_WORDS     (MAX_WIDTH * MAX_HEIGHT * NUM_OUTPUT_CHANNELS)

#define UART_BAUD            115200U

#define DMA_MM2S_DMACR       0x00U
#define DMA_MM2S_DMASR       0x04U
#define DMA_MM2S_SA          0x18U
#define DMA_MM2S_LENGTH      0x28U

#define DMA_S2MM_DMACR       0x30U
#define DMA_S2MM_DMASR       0x34U
#define DMA_S2MM_DA          0x48U
#define DMA_S2MM_LENGTH      0x58U

#define DMA_CR_RUNSTOP       0x00000001U
#define DMA_CR_RESET         0x00000004U

#define DMA_SR_IOC_IRQ       0x00001000U
#define DMA_SR_ERR_ALL       0x00007000U

#define DMA_TIMEOUT          10000000U

#define INPUT_MAGIC_0        'C'
#define INPUT_MAGIC_1        'N'
#define INPUT_MAGIC_2        'N'
#define INPUT_MAGIC_3        'I'

#define OUTPUT_MAGIC_0       'C'
#define OUTPUT_MAGIC_1       'N'
#define OUTPUT_MAGIC_2       'N'
#define OUTPUT_MAGIC_3       'O'

static XUartPs Uart;

static uint32_t input_buffer[MAX_INPUT_PIXELS] __attribute__((aligned(64)));
static int32_t  output_buffer[MAX_OUTPUT_WORDS] __attribute__((aligned(64)));

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

static int uart_init(void)
{
    XUartPs_Config *cfg = XUartPs_LookupConfig(XPAR_XUARTPS_0_BASEADDR);
    if (cfg == NULL) {
        return -1;
    }

    int status = XUartPs_CfgInitialize(&Uart, cfg, cfg->BaseAddress);
    if (status != XST_SUCCESS) {
        return -1;
    }

    XUartPs_SetBaudRate(&Uart, UART_BAUD);
    return 0;
}

static void uart_send_bytes(const uint8_t *data, uint32_t len)
{
    uint32_t sent = 0;

    while (sent < len) {
        sent += XUartPs_Send(&Uart, (uint8_t *)&data[sent], len - sent);
    }
}

static void uart_recv_bytes(uint8_t *data, uint32_t len)
{
    uint32_t received = 0;

    while (received < len) {
        received += XUartPs_Recv(&Uart, &data[received], len - received);
    }
}

static uint32_t read_u32_le(void)
{
    uint8_t b[4];
    uart_recv_bytes(b, 4);

    return ((uint32_t)b[0]) |
           ((uint32_t)b[1] << 8) |
           ((uint32_t)b[2] << 16) |
           ((uint32_t)b[3] << 24);
}

static void write_u32_le(uint32_t value)
{
    uint8_t b[4];

    b[0] = (uint8_t)((value >> 0) & 0xffU);
    b[1] = (uint8_t)((value >> 8) & 0xffU);
    b[2] = (uint8_t)((value >> 16) & 0xffU);
    b[3] = (uint8_t)((value >> 24) & 0xffU);

    uart_send_bytes(b, 4);
}

static void write_i32_le(int32_t value)
{
    write_u32_le((uint32_t)value);
}

static int wait_for_input_magic(void)
{
    uint8_t b;

    while (1) {
        uart_recv_bytes(&b, 1);

        if (b != INPUT_MAGIC_0) {
            continue;
        }

        uart_recv_bytes(&b, 1);
        if (b != INPUT_MAGIC_1) {
            continue;
        }

        uart_recv_bytes(&b, 1);
        if (b != INPUT_MAGIC_2) {
            continue;
        }

        uart_recv_bytes(&b, 1);
        if (b != INPUT_MAGIC_3) {
            continue;
        }

        return 0;
    }
}

static void load_weights_identity_like(uint32_t kernel_mode)
{
    for (uint32_t i = 0; i < NUM_WEIGHTS; i++) {
        cnn_write(REG_WEIGHT_BASE + (i * 4U), 0U);
    }

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

    return -1;
}

static int dma_wait_done(uint32_t status_offset)
{
    for (uint32_t i = 0; i < DMA_TIMEOUT; i++) {
        uint32_t status = dma_read(status_offset);

        if ((status & DMA_SR_ERR_ALL) != 0U) {
            return -1;
        }

        if ((status & DMA_SR_IOC_IRQ) != 0U) {
            return 0;
        }
    }

    return -1;
}

static int run_dma_transfer(uint32_t input_bytes, uint32_t output_bytes)
{
    if (dma_reset() != 0) {
        return -1;
    }

    dma_write(DMA_MM2S_DMASR, DMA_SR_IOC_IRQ | DMA_SR_ERR_ALL);
    dma_write(DMA_S2MM_DMASR, DMA_SR_IOC_IRQ | DMA_SR_ERR_ALL);

    Xil_DCacheFlushRange((UINTPTR)input_buffer, input_bytes);
    Xil_DCacheFlushRange((UINTPTR)output_buffer, output_bytes);

    dma_write(DMA_S2MM_DMACR, DMA_CR_RUNSTOP);
    dma_write(DMA_MM2S_DMACR, DMA_CR_RUNSTOP);

    dma_write(DMA_S2MM_DA, (uint32_t)(UINTPTR)output_buffer);
    dma_write(DMA_MM2S_SA, (uint32_t)(UINTPTR)input_buffer);

    dma_write(DMA_S2MM_LENGTH, output_bytes);
    dma_write(DMA_MM2S_LENGTH, input_bytes);

    if (dma_wait_done(DMA_MM2S_DMASR) != 0) {
        return -1;
    }

    if (dma_wait_done(DMA_S2MM_DMASR) != 0) {
        return -1;
    }

    Xil_DCacheInvalidateRange((UINTPTR)output_buffer, output_bytes);
    return 0;
}

static void send_error_response(uint32_t code)
{
    uint8_t magic[4] = {'C', 'N', 'N', 'E'};
    uart_send_bytes(magic, 4);
    write_u32_le(code);
}

static void send_output_packet(uint32_t out_w, uint32_t out_h, uint32_t out_words)
{
    uint8_t magic[4] = {
        OUTPUT_MAGIC_0,
        OUTPUT_MAGIC_1,
        OUTPUT_MAGIC_2,
        OUTPUT_MAGIC_3
    };

    uart_send_bytes(magic, 4);
    write_u32_le(out_w);
    write_u32_le(out_h);
    write_u32_le(NUM_OUTPUT_CHANNELS);
    write_u32_le(out_words);

    for (uint32_t i = 0; i < out_words; i++) {
        write_i32_le(output_buffer[i]);
    }
}

static int process_one_image(void)
{
    uint32_t width;
    uint32_t height;
    uint32_t kernel_mode;
    uint32_t pixel_count;

    wait_for_input_magic();

    width       = read_u32_le();
    height      = read_u32_le();
    kernel_mode = read_u32_le();
    pixel_count = read_u32_le();

    if ((width == 0U) || (height == 0U) ||
        (width > MAX_WIDTH) || (height > MAX_HEIGHT)) {
        send_error_response(1U);
        return -1;
    }

    if ((kernel_mode != 0U) && (kernel_mode != 1U)) {
        send_error_response(2U);
        return -1;
    }

    if ((kernel_mode == 1U) && ((width < 3U) || (height < 3U))) {
        send_error_response(3U);
        return -1;
    }

    if (pixel_count != (width * height)) {
        send_error_response(4U);
        return -1;
    }

    if (pixel_count > MAX_INPUT_PIXELS) {
        send_error_response(5U);
        return -1;
    }

    for (uint32_t i = 0; i < pixel_count; i++) {
        input_buffer[i] = read_u32_le();
    }

    uint32_t out_w = kernel_mode ? (width - 2U) : width;
    uint32_t out_h = kernel_mode ? (height - 2U) : height;
    uint32_t out_words = out_w * out_h * NUM_OUTPUT_CHANNELS;

    if (out_words > MAX_OUTPUT_WORDS) {
        send_error_response(6U);
        return -1;
    }

    for (uint32_t i = 0; i < out_words; i++) {
        output_buffer[i] = 0;
    }

    cnn_write(REG_CONTROL, 0x2U);
    usleep(1000);

    cnn_write(REG_WIDTH, width);
    cnn_write(REG_HEIGHT, height);

    uint32_t mode_flags = (kernel_mode & 0x1U) | 0x2U;
    cnn_write(REG_MODE_FLAGS, mode_flags);

    load_weights_identity_like(kernel_mode);
    load_bias_zero();

    cnn_write(REG_CONTROL, 0x1U);
    usleep(1000);

    uint32_t input_bytes = pixel_count * sizeof(uint32_t);
    uint32_t output_bytes = out_words * sizeof(int32_t);

    if (run_dma_transfer(input_bytes, output_bytes) != 0) {
        send_error_response(7U);
        return -1;
    }

    send_output_packet(out_w, out_h, out_words);
    return 0;
}

int main(void)
{
    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf(" Zynq CNN UART Image Streaming App\r\n");
    xil_printf("========================================\r\n");
    xil_printf("CNN base: 0x%08x\r\n", CNN_BASE);
    xil_printf("DMA base: 0x%08x\r\n", DMA_BASE);
    xil_printf("Max image: %dx%d\r\n", MAX_WIDTH, MAX_HEIGHT);

    if (uart_init() != 0) {
        xil_printf("[FAIL] UART init failed\r\n");
        while (1) {
            sleep(1);
        }
    }

    xil_printf("UART ready. Waiting for CNNI packets...\r\n");

    while (1) {
        int status = process_one_image();

        if (status == 0) {
            xil_printf("Processed image successfully. Waiting for next image...\r\n");
        } else {
            xil_printf("Image processing failed. Waiting for next packet...\r\n");
        }
    }

    return 0;
}
