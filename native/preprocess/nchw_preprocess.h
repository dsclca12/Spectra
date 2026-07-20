// SPDX-License-Identifier: Apache-2.0

/**
 * nchw_preprocess.h
 * 
 * High-performance RGBA → NCHW Float32 conversion for ONNX Runtime inference.
 * Written in C for maximum speed — processes megapixels in microseconds.
 * 
 * Usage:
 *   #include "nchw_preprocess.h"
 *   
 *   // Allocate output buffer: 3 * width * height * sizeof(float)
 *   float* nchw = malloc(3 * width * height * sizeof(float));
 *   nchw_rgba_to_planar(rgba_bytes, width, height, nchw);
 *   // nchw is now: [R plane][G plane][B plane], normalized to [0,1]
 */

#ifndef NCHW_PREPROCESS_H
#define NCHW_PREPROCESS_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Convert interleaved RGBA uint8 pixels to NCHW float32 planar format.
 * 
 * @param rgba      Input RGBA uint8 buffer (4 * width * height bytes)
 * @param width     Image width in pixels
 * @param height    Image height in pixels
 * @param nchw_out  Output NCHW float32 buffer (3 * width * height floats)
 *                  Layout: [R plane (W*H)] [G plane (W*H)] [B plane (W*H)]
 *                  All values normalized to [0.0, 1.0]
 * @param normalize If non-zero, divide by 255.0 (set to 0 if already [0,1])
 */
void nchw_rgba_to_planar(
    const uint8_t* rgba,
    int width,
    int height,
    float* nchw_out,
    int normalize
);

/**
 * Compute image statistics for auto-enhance directly in C.
 * Faster than doing it in Dart for large images.
 * 
 * @param rgba     Input RGBA uint8 buffer
 * @param width    Image width
 * @param height   Image height
 * @param stats    Output: [avg_r, avg_g, avg_b, avg_lum, std_lum, 
 *                          p5_lum, p50_lum, p95_lum, 
 *                          highlight_clip_ratio, shadow_clip_ratio,
 *                          neutral_pixel_ratio, avg_saturation]
 *                 Array of 12 doubles
 */
void compute_image_stats(
    const uint8_t* rgba,
    int width,
    int height,
    double stats[12]
);

#ifdef __cplusplus
}
#endif

#endif /* NCHW_PREPROCESS_H */
