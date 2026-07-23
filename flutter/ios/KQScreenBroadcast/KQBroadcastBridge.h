#ifndef KQ_BROADCAST_BRIDGE_H
#define KQ_BROADCAST_BRIDGE_H

#include <stdint.h>

int32_t kq_ios_broadcast_start(
    const uint8_t *config_dir,
    uintptr_t config_dir_len);

int32_t kq_ios_broadcast_registration_state(void);

int32_t kq_ios_broadcast_push_bgra(
    const void *data,
    uintptr_t data_len,
    uintptr_t width,
    uintptr_t height,
    uintptr_t stride);

int32_t kq_ios_broadcast_push_audio_f32(
    const float *data,
    uintptr_t sample_count);

uintptr_t kq_ios_broadcast_active_viewer_count(void);

void kq_ios_broadcast_pause(void);
void kq_ios_broadcast_resume(void);
void kq_ios_broadcast_stop(void);

#endif
