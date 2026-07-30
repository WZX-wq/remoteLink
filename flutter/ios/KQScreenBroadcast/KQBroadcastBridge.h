#ifndef KQ_BROADCAST_BRIDGE_H
#define KQ_BROADCAST_BRIDGE_H

#include <stdint.h>

int32_t kq_ios_broadcast_start(
    const uint8_t *config_dir,
    uintptr_t config_dir_len);

int32_t kq_ios_broadcast_registration_state(void);
int64_t kq_ios_broadcast_registration_rejection(void);

int32_t kq_ios_broadcast_last_auth_result(void);

uintptr_t kq_ios_broadcast_copy_device_id(
    uint8_t *buffer,
    uintptr_t buffer_len);

int32_t kq_ios_broadcast_push_bgra(
    const void *data,
    uintptr_t data_len,
    uintptr_t width,
    uintptr_t height,
    uintptr_t stride);

int32_t kq_ios_broadcast_push_audio_f32(
    const float *data,
    uintptr_t sample_count);

int32_t kq_ios_broadcast_push_voice_audio_f32(
    const float *data,
    uintptr_t sample_count);

uintptr_t kq_ios_broadcast_active_viewer_count(void);

uint64_t kq_ios_broadcast_voice_frames_sent(void);
uint64_t kq_ios_broadcast_voice_frames_received(void);
uint64_t kq_ios_broadcast_captured_video_frames(void);
uint64_t kq_ios_broadcast_video_service_starts(void);
uint64_t kq_ios_broadcast_video_service_failures(void);
uint64_t kq_ios_broadcast_fetched_video_frames(void);
uint64_t kq_ios_broadcast_converted_video_frames(void);
uint64_t kq_ios_broadcast_encoded_video_frames(void);
uint64_t kq_ios_broadcast_sent_video_frames(void);
uint64_t kq_ios_broadcast_network_written_video_frames(void);
uint64_t kq_ios_broadcast_client_acked_video_frames(void);
uint64_t kq_ios_broadcast_video_conversion_failures(void);
uint64_t kq_ios_broadcast_video_encoding_failures(void);
int32_t kq_ios_broadcast_last_video_error(void);
int32_t kq_ios_broadcast_first_video_diagnostic_state(void);
int32_t kq_ios_broadcast_first_video_key_frame(void);
uint64_t kq_ios_broadcast_first_video_encoded_bytes(void);
uint64_t kq_ios_broadcast_first_video_encoded_width(void);
uint64_t kq_ios_broadcast_first_video_encoded_height(void);
uint64_t kq_ios_broadcast_first_video_decoded_width(void);
uint64_t kq_ios_broadcast_first_video_decoded_height(void);
int32_t kq_ios_broadcast_video_ack_required(void);

void kq_ios_broadcast_pause(void);
void kq_ios_broadcast_resume(void);
void kq_ios_broadcast_stop(void);

#endif
