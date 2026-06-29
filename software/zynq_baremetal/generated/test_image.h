#ifndef TEST_IMAGE_H
#define TEST_IMAGE_H

#include <stdint.h>

#define IMAGE_WIDTH 4U
#define IMAGE_HEIGHT 4U
#define IMAGE_PIXELS 16U

static const uint32_t input_image[IMAGE_PIXELS] = {
    0x00010101U,
    0x00020102U,
    0x00030103U,
    0x00040104U,
    0x00020201U,
    0x00030202U,
    0x00040203U,
    0x00050204U,
    0x00030301U,
    0x00040302U,
    0x00050303U,
    0x00060304U,
    0x00040401U,
    0x00050402U,
    0x00060403U,
    0x00070404U
};

#endif
