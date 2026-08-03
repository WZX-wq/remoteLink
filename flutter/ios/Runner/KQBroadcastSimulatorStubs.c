#include <stdint.h>
#include <string.h>
#include <TargetConditionals.h>

#if TARGET_OS_SIMULATOR
#define KQ_SIM_STUB __attribute__((weak))

static const int32_t KQ_SIMULATOR_BROADCAST_UNAVAILABLE = 4;

KQ_SIM_STUB int32_t kq_ios_broadcast_start(
    const uint8_t *config_dir,
    uintptr_t config_dir_len) {
  return KQ_SIMULATOR_BROADCAST_UNAVAILABLE;
}

KQ_SIM_STUB int32_t kq_ios_broadcast_registration_state(void) {
  return 0;
}

KQ_SIM_STUB int64_t kq_ios_broadcast_registration_rejection(void) {
  return 0;
}

KQ_SIM_STUB int32_t kq_ios_broadcast_last_auth_result(void) {
  return 0;
}

KQ_SIM_STUB uintptr_t kq_ios_broadcast_copy_device_id(
    uint8_t *buffer,
    uintptr_t buffer_len) {
  if (buffer != NULL && buffer_len > 0) {
    buffer[0] = '\0';
  }
  return 0;
}

KQ_SIM_STUB int32_t kq_ios_broadcast_push_bgra(
    const void *data,
    uintptr_t data_len,
    uintptr_t width,
    uintptr_t height,
    uintptr_t stride) {
  return KQ_SIMULATOR_BROADCAST_UNAVAILABLE;
}

KQ_SIM_STUB int32_t kq_ios_broadcast_push_audio_f32(
    const float *data,
    uintptr_t sample_count) {
  return KQ_SIMULATOR_BROADCAST_UNAVAILABLE;
}

KQ_SIM_STUB int32_t kq_ios_broadcast_push_voice_audio_f32(
    const float *data,
    uintptr_t sample_count) {
  return KQ_SIMULATOR_BROADCAST_UNAVAILABLE;
}

KQ_SIM_STUB uintptr_t kq_ios_broadcast_active_viewer_count(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_voice_frames_sent(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_voice_frames_received(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_captured_video_frames(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_video_service_starts(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_video_service_failures(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_fetched_video_frames(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_converted_video_frames(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_encoded_video_frames(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_sent_video_frames(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_network_written_video_frames(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_client_acked_video_frames(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_video_conversion_failures(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_video_encoding_failures(void) {
  return 0;
}

KQ_SIM_STUB int32_t kq_ios_broadcast_last_video_error(void) {
  return 0;
}

KQ_SIM_STUB int32_t kq_ios_broadcast_first_video_diagnostic_state(void) {
  return 0;
}

KQ_SIM_STUB int32_t kq_ios_broadcast_first_video_key_frame(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_first_video_encoded_bytes(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_first_video_encoded_width(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_first_video_encoded_height(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_first_video_decoded_width(void) {
  return 0;
}

KQ_SIM_STUB uint64_t kq_ios_broadcast_first_video_decoded_height(void) {
  return 0;
}

KQ_SIM_STUB int32_t kq_ios_broadcast_video_ack_required(void) {
  return 0;
}

KQ_SIM_STUB void kq_ios_broadcast_pause(void) {}

KQ_SIM_STUB void kq_ios_broadcast_resume(void) {}

KQ_SIM_STUB void kq_ios_broadcast_stop(void) {}
#endif
