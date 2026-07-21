#include "sleep.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xiltimer.h"
#include "xtimer_config.h"
#include <stddef.h>
#include <stdint.h>

#include "cnn_accel_abi.h"
#include "generated/golden_dma_job.h"

#define CNN_BASE 0x43C00000U
#define DMA_BASE 0x40400000U

#define REG_CONTROL 0x000U
#define REG_STATUS 0x004U
#define REG_IRQ_STATUS 0x008U
#define REG_IRQ_ENABLE 0x00CU
#define REG_IMAGE_WIDTH 0x010U
#define REG_IMAGE_HEIGHT 0x014U
#define REG_MODE_FLAGS 0x018U
#define REG_ERROR_CODE 0x01CU
#define REG_STREAM_STATE 0x020U
#define REG_PACKET_WORDS 0x024U
#define REG_PERF_JOB_CYCLES 0x080U
#define REG_PERF_PACKET_CYCLES 0x084U
#define REG_PERF_COMPUTE_CYCLES 0x088U
#define REG_PERF_PREFETCH_CYCLES 0x08CU
#define REG_PERF_LAYER0_CYCLES 0x090U
#define REG_PERF_LAYER1_CYCLES 0x094U
#define REG_PERF_LAYER2_CYCLES 0x098U
#define REG_PERF_INPUT_WORDS 0x09CU
#define REG_PERF_INPUT_STALLS 0x0A0U
#define REG_PERF_OUTPUT_WORDS 0x0A4U
#define REG_PERF_OUTPUT_STALLS 0x0A8U
#define REG_VERSION 0x0FCU
#define REG_CAP_HEADER (CNN_REG_CAPABILITY_BASE + 0x00U)
#define REG_CAP_HW_VERSION (CNN_REG_CAPABILITY_BASE + 0x04U)
#define REG_CAP_ABI_DMA (CNN_REG_CAPABILITY_BASE + 0x08U)
#define REG_CAP_FEATURES (CNN_REG_CAPABILITY_BASE + 0x0CU)
#define REG_CAP_LIMITS0 (CNN_REG_CAPABILITY_BASE + 0x2CU)
#define REG_CAP_MAX_ELEMENTS (CNN_REG_CAPABILITY_BASE + 0x40U)
#define REG_CAP_PARALLELISM (CNN_REG_CAPABILITY_BASE + 0x58U)
#define REG_CAP_CLOCK_HZ (CNN_REG_CAPABILITY_BASE + 0x5CU)

#define CONTROL_START 0x00000001U
#define CONTROL_CLEAR 0x00000002U

#define STATUS_BUSY 0x00000001U
#define STATUS_DONE 0x00000002U
#define STATUS_ERROR 0x00000004U
#define STATUS_PERF_COUNTING 0x00000008U

#define MODE_FINAL_RESIDUAL 0x00000001U
#define IRQ_DONE 0x00000001U
#define IRQ_ERROR 0x00000002U
#define EXPECTED_VERSION CNN_REGISTER_MAP_VERSION
#define REQUIRED_FIXED_FEATURES (CNN_FEATURE_CAPABILITY_QUERY | \
 CNN_FEATURE_STRUCTURED_ERRORS | CNN_FEATURE_INTERRUPTS | \
 CNN_FEATURE_FIXED_NETWORK)

#define DMA_MM2S_DMACR 0x00U
#define DMA_MM2S_DMASR 0x04U
#define DMA_MM2S_SA 0x18U
#define DMA_MM2S_LENGTH 0x28U

#define DMA_S2MM_DMACR 0x30U
#define DMA_S2MM_DMASR 0x34U
#define DMA_S2MM_DA 0x48U
#define DMA_S2MM_LENGTH 0x58U

#define DMA_CR_RUNSTOP 0x00000001U
#define DMA_CR_RESET 0x00000004U

#define DMA_SR_HALTED 0x00000001U
#define DMA_SR_IDLE 0x00000002U
#define DMA_SR_SG_INCLD 0x00000008U
#define DMA_SR_DMA_INT_ERR 0x00000010U
#define DMA_SR_DMA_SLV_ERR 0x00000020U
#define DMA_SR_DMA_DEC_ERR 0x00000040U
#define DMA_SR_SG_INT_ERR 0x00000100U
#define DMA_SR_SG_SLV_ERR 0x00000200U
#define DMA_SR_SG_DEC_ERR 0x00000400U
#define DMA_SR_IOC_IRQ 0x00001000U
#define DMA_SR_DLY_IRQ 0x00002000U
#define DMA_SR_ERR_IRQ 0x00004000U
#define DMA_SR_IRQ_ALL (DMA_SR_IOC_IRQ | DMA_SR_DLY_IRQ | DMA_SR_ERR_IRQ)
#define DMA_SR_ERR_ALL (DMA_SR_DMA_INT_ERR | DMA_SR_DMA_SLV_ERR | DMA_SR_DMA_DEC_ERR | \
 DMA_SR_SG_INT_ERR | DMA_SR_SG_SLV_ERR | DMA_SR_SG_DEC_ERR | \
 DMA_SR_ERR_IRQ)

#define DMA_TIMEOUT 20000000U
#define CNN_TIMEOUT 20000000U

static uint32_t input_buffer[INPUT_PACKET_WORDS] __attribute__((aligned(64)));
static int32_t output_buffer[OUTPUT_WORDS] __attribute__((aligned(64)));

static inline void cnn_write(uint32_t offset, uint32_t value)
{
 Xil_Out32(CNN_BASE + offset, value);
}

static inline uint32_t cnn_read(uint32_t offset)
{
 return Xil_In32(CNN_BASE + offset);
}

static int validate_runtime_capabilities(void)
{
 uint32_t header = cnn_read(REG_CAP_HEADER);
 uint32_t hardware_version = cnn_read(REG_CAP_HW_VERSION);
 uint32_t abi_dma = cnn_read(REG_CAP_ABI_DMA);
 uint32_t features = cnn_read(REG_CAP_FEATURES);
 uint32_t limits = cnn_read(REG_CAP_LIMITS0);
 uint32_t max_elements = cnn_read(REG_CAP_MAX_ELEMENTS);
 uint32_t parallelism = cnn_read(REG_CAP_PARALLELISM);
 uint32_t clock_hz = cnn_read(REG_CAP_CLOCK_HZ);

 xil_printf(" capability record: version=%d size=%d bytes\r\n",
 header & 0xFFFFU, header >> 16);
 xil_printf(" hardware interface: 0x%08x model ABI=%d DMA bytes=%d\r\n",
 hardware_version, abi_dma & 0xFFFFU, abi_dma >> 16);
 xil_printf(" features=0x%08x layers=%d tensors=%d max_elements=%d\r\n",
 features, limits & 0xFFFFU, limits >> 16, max_elements);
 xil_printf(" parallelism PC=%d PK=%d clock=%d Hz\r\n",
 parallelism & 0xFFFFU, parallelism >> 16, clock_hz);

 if (header != ((CNN_CAPABILITY_RECORD_SIZE << 16) | CNN_ABI_VERSION)) {
  xil_printf("[FAIL] Invalid capability record header\r\n");
  return -1;
 }
 if (hardware_version != EXPECTED_VERSION ||
     (abi_dma & 0xFFFFU) != CNN_ABI_VERSION ||
     (features & REQUIRED_FIXED_FEATURES) != REQUIRED_FIXED_FEATURES ||
     (features & CNN_FEATURE_MODEL_PACKAGES) != 0U) {
  xil_printf("[FAIL] Bitstream capability profile does not match fixed app\r\n");
  return -1;
 }
 return 0;
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
 if ((status & DMA_SR_HALTED) != 0U) xil_printf(" halted");
 if ((status & DMA_SR_IDLE) != 0U) xil_printf(" idle");
 if ((status & DMA_SR_SG_INCLD) != 0U) xil_printf(" sg-included");
 if ((status & DMA_SR_DMA_INT_ERR) != 0U) xil_printf(" dma-internal-error");
 if ((status & DMA_SR_DMA_SLV_ERR) != 0U) xil_printf(" dma-slave-error");
 if ((status & DMA_SR_DMA_DEC_ERR) != 0U) xil_printf(" dma-decode-error");
 if ((status & DMA_SR_SG_INT_ERR) != 0U) xil_printf(" sg-internal-error");
 if ((status & DMA_SR_SG_SLV_ERR) != 0U) xil_printf(" sg-slave-error");
 if ((status & DMA_SR_SG_DEC_ERR) != 0U) xil_printf(" sg-decode-error");
 if ((status & DMA_SR_IOC_IRQ) != 0U) xil_printf(" complete");
 if ((status & DMA_SR_DLY_IRQ) != 0U) xil_printf(" delay-irq");
 if ((status & DMA_SR_ERR_IRQ) != 0U) xil_printf(" error-irq");
 xil_printf("\r\n");
}

static void print_dma_status(const char *name, uint32_t status)
{
 xil_printf("%s status = 0x%08x\r\n", name, status);
 print_dma_status_bits(name, status);
}

static void print_status(void)
{
 uint32_t status = cnn_read(REG_STATUS);
 uint32_t error_code = cnn_read(REG_ERROR_CODE);
 uint32_t stream_state = cnn_read(REG_STREAM_STATE);
 uint32_t packet_words = cnn_read(REG_PACKET_WORDS);
 uint32_t irq_status = cnn_read(REG_IRQ_STATUS);

 xil_printf(" status = 0x%08x\r\n", status);
 xil_printf(" irq_status = 0x%08x\r\n", irq_status);
 xil_printf(" error_code = 0x%08x\r\n", error_code);
 xil_printf(" stream_state = 0x%08x\r\n", stream_state);
 xil_printf(" packet_words = %d\r\n", packet_words);

 xil_printf(" status decode:");
 if ((status & STATUS_BUSY) != 0U) xil_printf(" busy");
 if ((status & STATUS_DONE) != 0U) xil_printf(" done");
 if ((status & STATUS_ERROR) != 0U) xil_printf(" error");
 if ((status & STATUS_PERF_COUNTING) != 0U) xil_printf(" perf-counting");
 xil_printf("\r\n");
}

static void print_performance_counters(void)
{
 xil_printf(" perf job cycles = %d\r\n", cnn_read(REG_PERF_JOB_CYCLES));
 xil_printf(" perf packet cycles = %d\r\n", cnn_read(REG_PERF_PACKET_CYCLES));
 xil_printf(" perf compute cycles = %d\r\n", cnn_read(REG_PERF_COMPUTE_CYCLES));
 xil_printf(" perf prefetch cycles = %d\r\n", cnn_read(REG_PERF_PREFETCH_CYCLES));
 xil_printf(" perf layer0 cycles = %d\r\n", cnn_read(REG_PERF_LAYER0_CYCLES));
 xil_printf(" perf layer1 cycles = %d\r\n", cnn_read(REG_PERF_LAYER1_CYCLES));
 xil_printf(" perf layer2 cycles = %d\r\n", cnn_read(REG_PERF_LAYER2_CYCLES));
 xil_printf(" perf input words = %d\r\n", cnn_read(REG_PERF_INPUT_WORDS));
 xil_printf(" perf input stalls = %d\r\n", cnn_read(REG_PERF_INPUT_STALLS));
 xil_printf(" perf output words = %d\r\n", cnn_read(REG_PERF_OUTPUT_WORDS));
 xil_printf(" perf output stalls = %d\r\n", cnn_read(REG_PERF_OUTPUT_STALLS));
}

static uint32_t cycles_to_usec(uint64_t cycles)
{
 return (uint32_t)((cycles * 1000000ULL) / COUNTS_PER_SECOND);
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
 print_status();
 return -1;
 }

 if ((status & DMA_SR_IOC_IRQ) != 0U) {
 return 0;
 }
 }

 xil_printf("[FAIL] %s DMA timeout while waiting for completion\r\n", name);
 print_dma_status(name, dma_read(status_offset));
 print_status();
 return -1;
}

static int cnn_wait_done(void)
{
 for (uint32_t i = 0; i < CNN_TIMEOUT; i++) {
 uint32_t status = cnn_read(REG_STATUS);

 if ((status & STATUS_ERROR) != 0U) {
 xil_printf("[FAIL] accelerator reported an error\r\n");
 print_status();
 return -1;
 }

 if ((status & STATUS_DONE) != 0U) {
 return 0;
 }
 }

 xil_printf("[FAIL] accelerator done timeout\r\n");
 print_status();
 print_dma_status("DMA MM2S at timeout", dma_read(DMA_MM2S_DMASR));
 print_dma_status("DMA S2MM at timeout", dma_read(DMA_S2MM_DMASR));
 return -1;
}

static void prepare_buffers(void)
{
 for (uint32_t i = 0; i < INPUT_PACKET_WORDS; i++) {
 input_buffer[i] = input_packet_words[i];
 }

 for (uint32_t i = 0; i < OUTPUT_WORDS; i++) {
 output_buffer[i] = (int32_t)0x55555555;
 }
}

static int compare_output(const int32_t *expected)
{
 uint32_t mismatches = 0;

 for (uint32_t i = 0; i < OUTPUT_WORDS; i++) {
 if (output_buffer[i] == expected[i]) {
 xil_printf("[PASS] output[%02d] = %d\r\n", i, output_buffer[i]);
 } else {
 xil_printf("[FAIL] output[%02d] expected=%d got=%d\r\n",
 i, expected[i], output_buffer[i]);
 mismatches++;
 }
 }

 if (mismatches != 0U) {
 xil_printf("[FAIL] output mismatch count = %d\r\n", mismatches);
 return -1;
 }

 return 0;
}

static int run_job(const char *name, uint32_t final_residual_enable)
{
 const int32_t *expected = final_residual_enable ?
 expected_residual_words :
 expected_no_residual_words;
 uint32_t input_bytes = INPUT_PACKET_WORDS * sizeof(uint32_t);
 uint32_t output_bytes = OUTPUT_WORDS * sizeof(int32_t);
 XTime transfer_start;
 XTime transfer_end;

 xil_printf("\r\n");
 xil_printf("[TEST] %s\r\n", name);

 prepare_buffers();

 if (dma_reset() != 0) {
 xil_printf("[FAIL] AXI DMA reset timeout\r\n");
 return -1;
 }

 dma_write(DMA_MM2S_DMASR, DMA_SR_IRQ_ALL);
 dma_write(DMA_S2MM_DMASR, DMA_SR_IRQ_ALL);

 xil_printf("Clearing accelerator...\r\n");
 cnn_write(REG_CONTROL, CONTROL_CLEAR);
 usleep(1000);

 cnn_write(REG_IMAGE_WIDTH, IMAGE_WIDTH);
 cnn_write(REG_IMAGE_HEIGHT, IMAGE_HEIGHT);
 cnn_write(REG_MODE_FLAGS, final_residual_enable ? MODE_FINAL_RESIDUAL : 0U);
 cnn_write(REG_IRQ_STATUS, IRQ_DONE | IRQ_ERROR);

 xil_printf("Image size = %d x %d\r\n", IMAGE_WIDTH, IMAGE_HEIGHT);
 xil_printf("Input words = %d\r\n", INPUT_PACKET_WORDS);
 xil_printf("Output words = %d\r\n", OUTPUT_WORDS);
 xil_printf("Final residual = %d\r\n", final_residual_enable);

 Xil_DCacheFlushRange((UINTPTR)input_buffer, input_bytes);
 Xil_DCacheFlushRange((UINTPTR)output_buffer, output_bytes);

 dma_write(DMA_S2MM_DMACR, DMA_CR_RUNSTOP);
 dma_write(DMA_MM2S_DMACR, DMA_CR_RUNSTOP);
 dma_write(DMA_S2MM_DA, (uint32_t)(UINTPTR)output_buffer);
 dma_write(DMA_MM2S_SA, (uint32_t)(UINTPTR)input_buffer);

 xil_printf("Input buffer = 0x%08x\r\n", (uint32_t)(UINTPTR)input_buffer);
 xil_printf("Output buffer = 0x%08x\r\n", (uint32_t)(UINTPTR)output_buffer);

 xil_printf("Starting accelerator and AXI DMA...\r\n");
 XTime_GetTime(&transfer_start);
 cnn_write(REG_CONTROL, CONTROL_START);
 dma_write(DMA_S2MM_LENGTH, output_bytes);
 dma_write(DMA_MM2S_LENGTH, input_bytes);

 if (dma_wait_done(DMA_MM2S_DMASR, "MM2S") != 0) {
 return -1;
 }

 if (dma_wait_done(DMA_S2MM_DMASR, "S2MM") != 0) {
 return -1;
 }

 XTime_GetTime(&transfer_end);
 Xil_DCacheInvalidateRange((UINTPTR)output_buffer, output_bytes);

 if (cnn_wait_done() != 0) {
 return -1;
 }

 print_dma_status("DMA MM2S final", dma_read(DMA_MM2S_DMASR));
 print_dma_status("DMA S2MM final", dma_read(DMA_S2MM_DMASR));
 print_status();
 print_performance_counters();

 uint64_t cycles = (uint64_t)(transfer_end - transfer_start);
 xil_printf("DMA+ transfer cycles = %d\r\n", (uint32_t)cycles);
 xil_printf("DMA+ transfer usec = %d\r\n", cycles_to_usec(cycles));

 if (compare_output(expected) != 0) {
 return -1;
 }

 xil_printf("[PASS] %s passed\r\n", name);
 return 0;
}

int main(void)
{
 xil_printf("\r\n");
 xil_printf("========================================\r\n");
 xil_printf(" Zynq Image-to-Image CNN DMA Test\r\n");
 xil_printf("========================================\r\n");
 xil_printf("CNN base address: 0x%08x\r\n", CNN_BASE);
 xil_printf("AXI DMA base address: 0x%08x\r\n", DMA_BASE);

 uint32_t version = cnn_read(REG_VERSION);
 xil_printf(" register version: 0x%08x\r\n", version);

 if (version != EXPECTED_VERSION) {
 xil_printf("[FAIL] Unexpected register version, expected 0x%08x\r\n",
 EXPECTED_VERSION);
 while (1) {
 sleep(1);
 }

 if (validate_runtime_capabilities() != 0) {
  while (1) {
   sleep(1);
  }
 }
 }

 int rc = 0;
 rc |= run_job("golden_full_network_residual", 1U);
 rc |= run_job("golden_full_network_no_residual", 0U);

 if (rc == 0) {
 xil_printf("\r\n[PASS] image-to-image DMA golden test passed\r\n");
 } else {
 xil_printf("\r\n[FAIL] image-to-image DMA golden test failed\r\n");
 }

 xil_printf("Test done.\r\n");

 while (1) {
 sleep(1);
 }

 return 0;
}
