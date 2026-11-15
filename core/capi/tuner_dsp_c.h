#ifndef TUNER_DSP_C_H
#define TUNER_DSP_C_H

/* C ABI over the C++ core: the only surface Swift (and later JNI) sees. */

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { TDSP_ALGORITHM_MPM = 0, TDSP_ALGORITHM_YIN = 1 } tdsp_algorithm;

typedef struct {
    float sample_rate;
    int window;
    float min_hz;
    float max_hz;
    float clarity_threshold;
    float gate_db;
} tdsp_detector_config;

typedef struct {
    float hz;
    float clarity;
    float rms_db;
    bool voiced;
} tdsp_pitch;

typedef struct {
    float a4_hz;
    float tolerance_cents;
    float release_margin_cents;
    double lock_hold_sec;
    double idle_after_sec;
    float ema_slow_alpha;
    float ema_fast_alpha;
    float ema_fast_cents;
} tdsp_tuner_config;

typedef struct {
    int midi;
    int string_index;
    float hz;
    float cents;
    bool voiced;
    bool locked;
    bool idle;
} tdsp_tuner_state;

typedef struct tdsp_detector tdsp_detector;
typedef struct tdsp_tuner tdsp_tuner;

tdsp_detector_config tdsp_detector_config_default(void);
/* Returns NULL if allocation fails. */
tdsp_detector *tdsp_detector_create(tdsp_algorithm algorithm, const tdsp_detector_config *config);
void tdsp_detector_destroy(tdsp_detector *detector);
/* Real-time safe: no allocation, no locks. Analyses the last `window` samples. */
tdsp_pitch tdsp_detector_process(tdsp_detector *detector, const float *samples, size_t count);

tdsp_tuner_config tdsp_tuner_config_default(void);
tdsp_tuner *tdsp_tuner_create(const tdsp_tuner_config *config);
void tdsp_tuner_destroy(tdsp_tuner *tuner);
/* Empty tuning = chromatic mode. */
void tdsp_tuner_set_tuning(tdsp_tuner *tuner, const float *string_hz, size_t count);
void tdsp_tuner_set_reference(tdsp_tuner *tuner, float a4_hz);
void tdsp_tuner_set_tolerance(tdsp_tuner *tuner, float cents);
/* -1 = auto string detection. */
void tdsp_tuner_set_manual_string(tdsp_tuner *tuner, int index);
void tdsp_tuner_reset(tdsp_tuner *tuner);
/* Real-time safe. */
tdsp_tuner_state tdsp_tuner_push(tdsp_tuner *tuner, tdsp_pitch pitch, double timestamp_sec);

#ifdef __cplusplus
}
#endif

#endif
