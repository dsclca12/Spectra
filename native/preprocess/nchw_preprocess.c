// SPDX-License-Identifier: Apache-2.0

/**
 * nchw_preprocess.c
 * 
 * Optimized C implementation of RGBA → NCHW conversion and image statistics.
 * Uses SIMD-friendly memory access patterns.
 */



#include "nchw_preprocess.h"
#include <string.h>
#include <math.h>

// ─── RGBA → NCHW Planar Conversion ─────────────────────────

void nchw_rgba_to_planar(
    const uint8_t* rgba,
    int width,
    int height,
    float* nchw_out,
    int normalize
) {
    const int total_pixels = width * height;
    const float inv_255 = 1.0f / 255.0f;

    // Planar output pointers
    float* r_plane = nchw_out;
    float* g_plane = nchw_out + total_pixels;
    float* b_plane = nchw_out + 2 * total_pixels;

    if (normalize) {
        for (int i = 0; i < total_pixels; i++) {
            const int src_idx = i * 4;
            r_plane[i] = (float)rgba[src_idx] * inv_255;
            g_plane[i] = (float)rgba[src_idx + 1] * inv_255;
            b_plane[i] = (float)rgba[src_idx + 2] * inv_255;
        }
    } else {
        for (int i = 0; i < total_pixels; i++) {
            const int src_idx = i * 4;
            r_plane[i] = (float)rgba[src_idx];
            g_plane[i] = (float)rgba[src_idx + 1];
            b_plane[i] = (float)rgba[src_idx + 2];
        }
    }
}


// ─── Image Statistics Computation ───────────────────────────

#define HIST_BINS 256

void compute_image_stats(
    const uint8_t* rgba,
    int width,
    int height,
    double stats[12]
) {
    const int total_pixels = width * height;
    const double n = (double)total_pixels;
    const double inv_255 = 1.0 / 255.0;

    // Accumulators
    double sum_r = 0.0, sum_g = 0.0, sum_b = 0.0;
    double sum_lum = 0.0, sum_lum2 = 0.0;
    double sum_sat = 0.0;
    int hist[HIST_BINS];
    memset(hist, 0, sizeof(hist));

    int highlight_clip = 0;
    int shadow_clip = 0;
    int neutral_count = 0;

    for (int i = 0; i < total_pixels; i++) {
        const int idx = i * 4;
        const double r = rgba[idx] * inv_255;
        const double g = rgba[idx + 1] * inv_255;
        const double b = rgba[idx + 2] * inv_255;

        sum_r += r;
        sum_g += g;
        sum_b += b;

        // Rec.709 luminance
        const double lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        sum_lum += lum;
        sum_lum2 += lum * lum;

        // Histogram
        int bin = (int)(lum * 255.0);
        if (bin < 0) bin = 0;
        if (bin > 255) bin = 255;
        hist[bin]++;

        // Highlight/Shadow clip
        if (lum > 0.99) highlight_clip++;
        if (lum < 0.01) shadow_clip++;

        // Saturation (HSL model)
        double max_val = r;
        if (g > max_val) max_val = g;
        if (b > max_val) max_val = b;
        double min_val = r;
        if (g < min_val) min_val = g;
        if (b < min_val) min_val = b;
        double sat = max_val > 0.0 ? (max_val - min_val) / max_val : 0.0;
        sum_sat += sat;

        // Neutral pixel detection
        if (sat < 0.08) neutral_count++;
    }

    // Derived statistics
    const double avg_r = sum_r / n;
    const double avg_g = sum_g / n;
    const double avg_b = sum_b / n;
    const double avg_lum = sum_lum / n;
    const double var_lum = (sum_lum2 / n) - (avg_lum * avg_lum);
    const double std_lum = sqrt(var_lum > 0.0 ? var_lum : 0.0);

    // Percentiles from histogram
    double p5_lum = 0.0, p50_lum = 0.0, p95_lum = 0.0;
    double cumulative = 0.0;
    const double p5_target = n * 0.05;
    const double p50_target = n * 0.50;
    const double p95_target = n * 0.95;
    int found_p5 = 0, found_p50 = 0, found_p95 = 0;

    for (int i = 0; i < HIST_BINS; i++) {
        cumulative += hist[i];
        if (!found_p5 && cumulative >= p5_target) {
            p5_lum = i / 255.0;
            found_p5 = 1;
        }
        if (!found_p50 && cumulative >= p50_target) {
            p50_lum = i / 255.0;
            found_p50 = 1;
        }
        if (!found_p95 && cumulative >= p95_target) {
            p95_lum = i / 255.0;
            found_p95 = 1;
        }
    }

    // Output stats array
    stats[0] = avg_r;
    stats[1] = avg_g;
    stats[2] = avg_b;
    stats[3] = avg_lum;
    stats[4] = std_lum;
    stats[5] = p5_lum;
    stats[6] = p50_lum;
    stats[7] = p95_lum;
    stats[8] = highlight_clip / n;
    stats[9] = shadow_clip / n;
    stats[10] = neutral_count / n;
    stats[11] = sum_sat / n;
}

