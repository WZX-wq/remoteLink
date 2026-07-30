use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};

static CAPTURED_VIDEO_FRAMES: AtomicU64 = AtomicU64::new(0);
static VIDEO_SERVICE_STARTS: AtomicU64 = AtomicU64::new(0);
static VIDEO_SERVICE_FAILURES: AtomicU64 = AtomicU64::new(0);
static FETCHED_VIDEO_FRAMES: AtomicU64 = AtomicU64::new(0);
static CONVERTED_VIDEO_FRAMES: AtomicU64 = AtomicU64::new(0);
static ENCODED_VIDEO_FRAMES: AtomicU64 = AtomicU64::new(0);
static SENT_VIDEO_FRAMES: AtomicU64 = AtomicU64::new(0);
static NETWORK_WRITTEN_VIDEO_FRAMES: AtomicU64 = AtomicU64::new(0);
static CLIENT_ACKED_VIDEO_FRAMES: AtomicU64 = AtomicU64::new(0);
static VIDEO_CONVERSION_FAILURES: AtomicU64 = AtomicU64::new(0);
static VIDEO_ENCODING_FAILURES: AtomicU64 = AtomicU64::new(0);
static LAST_VIDEO_ERROR: AtomicI32 = AtomicI32::new(0);
static FIRST_VIDEO_DIAGNOSTIC_STATE: AtomicI32 = AtomicI32::new(0);
static FIRST_VIDEO_KEY_FRAME: AtomicI32 = AtomicI32::new(0);
static FIRST_VIDEO_ENCODED_BYTES: AtomicU64 = AtomicU64::new(0);
static FIRST_VIDEO_ENCODED_WIDTH: AtomicU64 = AtomicU64::new(0);
static FIRST_VIDEO_ENCODED_HEIGHT: AtomicU64 = AtomicU64::new(0);
static FIRST_VIDEO_DECODED_WIDTH: AtomicU64 = AtomicU64::new(0);
static FIRST_VIDEO_DECODED_HEIGHT: AtomicU64 = AtomicU64::new(0);
static VIDEO_ACK_REQUIRED: AtomicI32 = AtomicI32::new(0);

pub(crate) const VIDEO_ERROR_NONE: i32 = 0;
pub(crate) const VIDEO_ERROR_CONVERSION: i32 = 1;
pub(crate) const VIDEO_ERROR_ENCODING: i32 = 2;

pub(crate) fn viewer_count_for(active: bool, connection_count: usize) -> usize {
    if active {
        connection_count
    } else {
        0
    }
}

pub(crate) fn reset_video_diagnostics() {
    CAPTURED_VIDEO_FRAMES.store(0, Ordering::Release);
    VIDEO_SERVICE_STARTS.store(0, Ordering::Release);
    VIDEO_SERVICE_FAILURES.store(0, Ordering::Release);
    FETCHED_VIDEO_FRAMES.store(0, Ordering::Release);
    CONVERTED_VIDEO_FRAMES.store(0, Ordering::Release);
    ENCODED_VIDEO_FRAMES.store(0, Ordering::Release);
    SENT_VIDEO_FRAMES.store(0, Ordering::Release);
    NETWORK_WRITTEN_VIDEO_FRAMES.store(0, Ordering::Release);
    CLIENT_ACKED_VIDEO_FRAMES.store(0, Ordering::Release);
    VIDEO_CONVERSION_FAILURES.store(0, Ordering::Release);
    VIDEO_ENCODING_FAILURES.store(0, Ordering::Release);
    LAST_VIDEO_ERROR.store(VIDEO_ERROR_NONE, Ordering::Release);
    FIRST_VIDEO_DIAGNOSTIC_STATE.store(0, Ordering::Release);
    FIRST_VIDEO_KEY_FRAME.store(0, Ordering::Release);
    FIRST_VIDEO_ENCODED_BYTES.store(0, Ordering::Release);
    FIRST_VIDEO_ENCODED_WIDTH.store(0, Ordering::Release);
    FIRST_VIDEO_ENCODED_HEIGHT.store(0, Ordering::Release);
    FIRST_VIDEO_DECODED_WIDTH.store(0, Ordering::Release);
    FIRST_VIDEO_DECODED_HEIGHT.store(0, Ordering::Release);
    VIDEO_ACK_REQUIRED.store(0, Ordering::Release);
}

pub(crate) fn begin_first_video_diagnostic() -> bool {
    FIRST_VIDEO_DIAGNOSTIC_STATE
        .compare_exchange(0, -2, Ordering::AcqRel, Ordering::Acquire)
        .is_ok()
}

pub(crate) fn finish_first_video_diagnostic(
    key_frame: bool,
    encoded_bytes: usize,
    encoded_width: usize,
    encoded_height: usize,
    decoded_size: Option<(usize, usize)>,
) {
    FIRST_VIDEO_KEY_FRAME.store(if key_frame { 2 } else { 1 }, Ordering::Release);
    FIRST_VIDEO_ENCODED_BYTES.store(encoded_bytes as u64, Ordering::Release);
    FIRST_VIDEO_ENCODED_WIDTH.store(encoded_width as u64, Ordering::Release);
    FIRST_VIDEO_ENCODED_HEIGHT.store(encoded_height as u64, Ordering::Release);
    if let Some((width, height)) = decoded_size {
        FIRST_VIDEO_DECODED_WIDTH.store(width as u64, Ordering::Release);
        FIRST_VIDEO_DECODED_HEIGHT.store(height as u64, Ordering::Release);
        FIRST_VIDEO_DIAGNOSTIC_STATE.store(1, Ordering::Release);
    } else {
        FIRST_VIDEO_DIAGNOSTIC_STATE.store(-1, Ordering::Release);
    }
}

pub(crate) fn note_video_ack_required(required: bool) {
    VIDEO_ACK_REQUIRED.store(if required { 1 } else { 0 }, Ordering::Release);
}

pub(crate) fn note_video_frame_captured() {
    CAPTURED_VIDEO_FRAMES.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn note_video_service_started() {
    VIDEO_SERVICE_STARTS.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn note_video_service_failure() {
    VIDEO_SERVICE_FAILURES.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn note_video_frame_fetched() {
    FETCHED_VIDEO_FRAMES.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn note_video_frame_converted() {
    CONVERTED_VIDEO_FRAMES.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn note_video_conversion_failure() -> u64 {
    LAST_VIDEO_ERROR.store(VIDEO_ERROR_CONVERSION, Ordering::Release);
    VIDEO_CONVERSION_FAILURES.fetch_add(1, Ordering::Relaxed) + 1
}

pub(crate) fn note_video_frame_encoded(sent: bool) {
    ENCODED_VIDEO_FRAMES.fetch_add(1, Ordering::Relaxed);
    if sent {
        SENT_VIDEO_FRAMES.fetch_add(1, Ordering::Relaxed);
    }
    LAST_VIDEO_ERROR.store(VIDEO_ERROR_NONE, Ordering::Release);
}

pub(crate) fn note_video_encoding_failure() -> u64 {
    LAST_VIDEO_ERROR.store(VIDEO_ERROR_ENCODING, Ordering::Release);
    VIDEO_ENCODING_FAILURES.fetch_add(1, Ordering::Relaxed) + 1
}

pub(crate) fn note_video_frame_network_written() {
    NETWORK_WRITTEN_VIDEO_FRAMES.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn note_video_frame_client_acked() {
    CLIENT_ACKED_VIDEO_FRAMES.fetch_add(1, Ordering::Relaxed);
}

pub(crate) fn captured_video_frames() -> u64 {
    CAPTURED_VIDEO_FRAMES.load(Ordering::Acquire)
}

pub(crate) fn video_service_starts() -> u64 {
    VIDEO_SERVICE_STARTS.load(Ordering::Acquire)
}

pub(crate) fn video_service_failures() -> u64 {
    VIDEO_SERVICE_FAILURES.load(Ordering::Acquire)
}

pub(crate) fn fetched_video_frames() -> u64 {
    FETCHED_VIDEO_FRAMES.load(Ordering::Acquire)
}

pub(crate) fn converted_video_frames() -> u64 {
    CONVERTED_VIDEO_FRAMES.load(Ordering::Acquire)
}

pub(crate) fn encoded_video_frames() -> u64 {
    ENCODED_VIDEO_FRAMES.load(Ordering::Acquire)
}

pub(crate) fn sent_video_frames() -> u64 {
    SENT_VIDEO_FRAMES.load(Ordering::Acquire)
}

pub(crate) fn network_written_video_frames() -> u64 {
    NETWORK_WRITTEN_VIDEO_FRAMES.load(Ordering::Acquire)
}

pub(crate) fn client_acked_video_frames() -> u64 {
    CLIENT_ACKED_VIDEO_FRAMES.load(Ordering::Acquire)
}

pub(crate) fn video_conversion_failures() -> u64 {
    VIDEO_CONVERSION_FAILURES.load(Ordering::Acquire)
}

pub(crate) fn video_encoding_failures() -> u64 {
    VIDEO_ENCODING_FAILURES.load(Ordering::Acquire)
}

pub(crate) fn last_video_error() -> i32 {
    LAST_VIDEO_ERROR.load(Ordering::Acquire)
}

pub(crate) fn first_video_diagnostic_state() -> i32 {
    FIRST_VIDEO_DIAGNOSTIC_STATE.load(Ordering::Acquire)
}

pub(crate) fn first_video_key_frame() -> i32 {
    FIRST_VIDEO_KEY_FRAME.load(Ordering::Acquire)
}

pub(crate) fn first_video_encoded_bytes() -> u64 {
    FIRST_VIDEO_ENCODED_BYTES.load(Ordering::Acquire)
}

pub(crate) fn first_video_encoded_width() -> u64 {
    FIRST_VIDEO_ENCODED_WIDTH.load(Ordering::Acquire)
}

pub(crate) fn first_video_encoded_height() -> u64 {
    FIRST_VIDEO_ENCODED_HEIGHT.load(Ordering::Acquire)
}

pub(crate) fn first_video_decoded_width() -> u64 {
    FIRST_VIDEO_DECODED_WIDTH.load(Ordering::Acquire)
}

pub(crate) fn first_video_decoded_height() -> u64 {
    FIRST_VIDEO_DECODED_HEIGHT.load(Ordering::Acquire)
}

pub(crate) fn video_ack_required() -> i32 {
    VIDEO_ACK_REQUIRED.load(Ordering::Acquire)
}

#[cfg(test)]
mod tests {
    use super::viewer_count_for;

    #[test]
    fn viewer_count_is_hidden_when_broadcast_is_inactive() {
        assert_eq!(viewer_count_for(false, 3), 0);
        assert_eq!(viewer_count_for(true, 3), 3);
    }
}
