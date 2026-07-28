use hbb_common::{config::Config, get_time, log};
use serde_derive::{Deserialize, Serialize};
use std::{
    collections::VecDeque,
    fs::{self, File, OpenOptions},
    io::Write,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Mutex,
    },
    time::{SystemTime, UNIX_EPOCH},
};

pub(crate) const REQUEST_FILE_NAME: &str = "kq-ios-voice-call-request.json";
pub(crate) const RESPONSE_FILE_NAME: &str = "kq-ios-voice-call-response.json";
pub(crate) const STATE_FILE_NAME: &str = "kq-ios-voice-call-state.json";
pub(crate) const AUDIO_FILE_NAME: &str = "kq-ios-voice-call-audio.bin";
const HOST_CAPTURE_DIRECTORY_NAME: &str = "kq-ios-voice-call-mic";
const HOST_CLOSE_FILE_NAME: &str = "kq-ios-voice-call-close.json";
const BROADCAST_MIC_ACTIVE_FILE_NAME: &str = "kq-ios-voice-call-replaykit-mic-active";

const REQUEST_TTL_SECS: i64 = 45;
const AUDIO_MAGIC: u32 = 0x4156_514B; // "KQVA" in little endian.
const AUDIO_HEADER_LEN: usize = 16;
const MAX_AUDIO_FILE_BYTES: u64 = 1_024 * 1_024;
const MAX_AUDIO_SAMPLES: usize = 11_520;
const HOST_AUDIO_FRAME_SAMPLES: usize = 960;
const MAX_QUEUED_HOST_AUDIO_SAMPLES: usize = HOST_AUDIO_FRAME_SAMPLES * 25;

pub(crate) const ERR_VOICE_CALL_INACTIVE: i32 = 7;
pub(crate) const ERR_INVALID_VOICE_AUDIO: i32 = 8;

static VOICE_CALL_ACTIVE: AtomicBool = AtomicBool::new(false);
static BROADCAST_MIC_MARKER_PUBLISHED: AtomicBool = AtomicBool::new(false);
static BROADCAST_FALLBACK_CLEARED: AtomicBool = AtomicBool::new(false);
static BROADCAST_MIC_FRAMES_QUEUED: AtomicU64 = AtomicU64::new(0);
static BROADCAST_MIC_FRAMES_DRAINED: AtomicU64 = AtomicU64::new(0);

lazy_static::lazy_static! {
    static ref BROADCAST_HOST_AUDIO: Mutex<VecDeque<f32>> = Mutex::new(VecDeque::new());
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct PendingVoiceCall {
    pub request_id: String,
    pub request_timestamp: i64,
    pub expires_at: i64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct VoiceCallResponse {
    request_id: String,
    accepted: bool,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct VoiceCallState {
    request_id: String,
    active: bool,
    updated_at: i64,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct HostVoiceCallClose {
    request_id: String,
}

fn path(name: &str) -> PathBuf {
    Config::path(name)
}

fn remove_file(name: &str) {
    if let Err(err) = fs::remove_file(path(name)) {
        if err.kind() != std::io::ErrorKind::NotFound {
            log::warn!("Failed to remove iOS voice call file {name}: {err}");
        }
    }
}

fn host_capture_directory() -> PathBuf {
    path(HOST_CAPTURE_DIRECTORY_NAME)
}

fn clear_host_capture_directory() {
    if let Err(err) = fs::remove_dir_all(host_capture_directory()) {
        if err.kind() != std::io::ErrorKind::NotFound {
            log::warn!("Failed to clear iOS host voice capture queue: {err}");
        }
    }
}

fn clear_broadcast_host_audio() {
    if let Ok(mut samples) = BROADCAST_HOST_AUDIO.lock() {
        samples.clear();
    }
    BROADCAST_MIC_FRAMES_QUEUED.store(0, Ordering::Release);
    BROADCAST_MIC_FRAMES_DRAINED.store(0, Ordering::Release);
    BROADCAST_MIC_MARKER_PUBLISHED.store(false, Ordering::Release);
    BROADCAST_FALLBACK_CLEARED.store(false, Ordering::Release);
    #[cfg(target_os = "ios")]
    remove_file(BROADCAST_MIC_ACTIVE_FILE_NAME);
}

#[cfg(target_os = "ios")]
fn publish_broadcast_mic_marker() {
    if BROADCAST_MIC_MARKER_PUBLISHED
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return;
    }
    let destination = path(BROADCAST_MIC_ACTIVE_FILE_NAME);
    let result = destination
        .parent()
        .ok_or_else(|| {
            std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "ReplayKit microphone marker has no parent directory",
            )
        })
        .and_then(fs::create_dir_all)
        .and_then(|_| File::create(&destination))
        .and_then(|file| file.sync_all());
    if let Err(err) = result {
        BROADCAST_MIC_MARKER_PUBLISHED.store(false, Ordering::Release);
        log::warn!("Failed to publish ReplayKit microphone marker: {err}");
    }
}

#[cfg(not(target_os = "ios"))]
fn publish_broadcast_mic_marker() {}

fn write_json<T: serde::Serialize>(name: &str, value: &T) -> std::io::Result<()> {
    let destination = path(name);
    let Some(parent) = destination.parent() else {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "iOS voice call file has no parent directory",
        ));
    };
    fs::create_dir_all(parent)?;
    let payload = serde_json::to_vec(value).map_err(std::io::Error::other)?;
    let temporary = destination.with_extension(format!("{}.tmp", std::process::id()));
    {
        let mut file = File::create(&temporary)?;
        file.write_all(&payload)?;
        file.sync_all()?;
    }
    fs::rename(temporary, destination)
}

fn read_json<T: for<'a> serde::Deserialize<'a>>(name: &str) -> Option<T> {
    let source = fs::read(path(name)).ok()?;
    serde_json::from_slice(&source).ok()
}

fn make_audio_record(sample_rate: u32, channels: u32, samples: &[f32]) -> Vec<u8> {
    let mut payload =
        Vec::with_capacity(AUDIO_HEADER_LEN + samples.len() * std::mem::size_of::<f32>());
    payload.extend_from_slice(&AUDIO_MAGIC.to_le_bytes());
    payload.extend_from_slice(&sample_rate.to_le_bytes());
    payload.extend_from_slice(&(channels as u16).to_le_bytes());
    payload.extend_from_slice(&0u16.to_le_bytes());
    payload.extend_from_slice(&(samples.len() as u32).to_le_bytes());
    for sample in samples {
        payload.extend_from_slice(&sample.to_bits().to_le_bytes());
    }
    payload
}

pub(crate) fn publish_incoming_voice_call(request_timestamp: i64) -> Option<PendingVoiceCall> {
    if read_json::<VoiceCallState>(STATE_FILE_NAME)
        .map(|state| state.active)
        .unwrap_or(false)
    {
        log::warn!("Ignoring iOS voice call request while another call is active");
        return None;
    }
    if let Some(existing) = read_json::<PendingVoiceCall>(REQUEST_FILE_NAME) {
        if existing.expires_at > get_time() {
            log::warn!(
                "Ignoring iOS voice call request while {} is still pending",
                existing.request_id
            );
            return None;
        }
        remove_file(REQUEST_FILE_NAME);
    }
    remove_file(RESPONSE_FILE_NAME);

    let request = PendingVoiceCall {
        request_id: uuid::Uuid::new_v4().to_string(),
        request_timestamp,
        expires_at: get_time() + REQUEST_TTL_SECS,
    };
    match write_json(REQUEST_FILE_NAME, &request) {
        Ok(()) => Some(request),
        Err(err) => {
            log::error!("Failed to publish iOS voice call request: {err}");
            None
        }
    }
}

pub(crate) fn take_voice_call_response(request_id: &str) -> Option<bool> {
    let request = read_json::<PendingVoiceCall>(REQUEST_FILE_NAME)?;
    if request.request_id != request_id {
        return None;
    }
    if request.expires_at <= get_time() {
        remove_file(REQUEST_FILE_NAME);
        remove_file(RESPONSE_FILE_NAME);
        return Some(false);
    }
    let response = read_json::<VoiceCallResponse>(RESPONSE_FILE_NAME)?;
    if response.request_id != request_id {
        return None;
    }
    remove_file(RESPONSE_FILE_NAME);
    remove_file(REQUEST_FILE_NAME);
    log::info!(
        "Received iOS voice call response for request {request_id}: accepted={}",
        response.accepted
    );
    Some(response.accepted)
}

pub(crate) fn request_expired(request_id: &str) -> bool {
    let Some(request) = read_json::<PendingVoiceCall>(REQUEST_FILE_NAME) else {
        return false;
    };
    request.request_id == request_id && request.expires_at <= get_time()
}

pub(crate) fn activate_voice_call(request_id: &str) {
    if let Err(err) = write_json(
        STATE_FILE_NAME,
        &VoiceCallState {
            request_id: request_id.to_owned(),
            active: true,
            updated_at: get_time(),
        },
    ) {
        log::warn!("Failed to mark iOS voice call active: {err}");
    }
    remove_file(AUDIO_FILE_NAME);
    remove_file(HOST_CLOSE_FILE_NAME);
    clear_host_capture_directory();
    clear_broadcast_host_audio();
    VOICE_CALL_ACTIVE.store(true, Ordering::Release);
}

pub(crate) fn close_voice_call(request_id: &str) {
    VOICE_CALL_ACTIVE.store(false, Ordering::Release);
    if let Err(err) = write_json(
        STATE_FILE_NAME,
        &VoiceCallState {
            request_id: request_id.to_owned(),
            active: false,
            updated_at: get_time(),
        },
    ) {
        log::warn!("Failed to mark iOS voice call closed: {err}");
    }
    remove_file(REQUEST_FILE_NAME);
    remove_file(RESPONSE_FILE_NAME);
    remove_file(AUDIO_FILE_NAME);
    remove_file(HOST_CLOSE_FILE_NAME);
    clear_host_capture_directory();
    clear_broadcast_host_audio();
}

pub(crate) fn reset_voice_call() {
    VOICE_CALL_ACTIVE.store(false, Ordering::Release);
    if let Err(err) = write_json(
        STATE_FILE_NAME,
        &VoiceCallState {
            request_id: String::new(),
            active: false,
            updated_at: get_time(),
        },
    ) {
        log::warn!("Failed to reset iOS voice call state: {err}");
    }
    remove_file(REQUEST_FILE_NAME);
    remove_file(RESPONSE_FILE_NAME);
    remove_file(AUDIO_FILE_NAME);
    remove_file(HOST_CLOSE_FILE_NAME);
    clear_host_capture_directory();
    clear_broadcast_host_audio();
}

pub(crate) fn push_broadcast_host_voice_audio(samples: &[f32]) -> i32 {
    if !VOICE_CALL_ACTIVE.load(Ordering::Acquire) {
        return ERR_VOICE_CALL_INACTIVE;
    }
    if samples.is_empty() || samples.iter().any(|sample| !sample.is_finite()) {
        return ERR_INVALID_VOICE_AUDIO;
    }

    let Ok(mut queued) = BROADCAST_HOST_AUDIO.lock() else {
        return ERR_INVALID_VOICE_AUDIO;
    };
    if !VOICE_CALL_ACTIVE.load(Ordering::Acquire) {
        return ERR_VOICE_CALL_INACTIVE;
    }
    let complete_frames_before = queued.len() / HOST_AUDIO_FRAME_SAMPLES;
    let overflow = queued
        .len()
        .saturating_add(samples.len())
        .saturating_sub(MAX_QUEUED_HOST_AUDIO_SAMPLES);
    for _ in 0..overflow {
        queued.pop_front();
    }
    queued.extend(samples.iter().copied());

    let completed_frames =
        (queued.len() / HOST_AUDIO_FRAME_SAMPLES).saturating_sub(complete_frames_before);
    drop(queued);
    publish_broadcast_mic_marker();
    if completed_frames > 0 {
        let previous =
            BROADCAST_MIC_FRAMES_QUEUED.fetch_add(completed_frames as u64, Ordering::AcqRel);
        let total = previous + completed_frames as u64;
        if previous == 0 || previous / 500 != total / 500 {
            log::info!("iOS ReplayKit microphone queued {total} voice frames");
        }
    }
    0
}

fn take_broadcast_host_voice_audio() -> Vec<Vec<f32>> {
    const MAX_BATCH: usize = 8;
    if !VOICE_CALL_ACTIVE.load(Ordering::Acquire) {
        return Vec::new();
    }
    let Ok(mut queued) = BROADCAST_HOST_AUDIO.lock() else {
        return Vec::new();
    };
    let frame_count = (queued.len() / HOST_AUDIO_FRAME_SAMPLES).min(MAX_BATCH);
    let mut output = Vec::with_capacity(frame_count);
    for _ in 0..frame_count {
        output.push(queued.drain(..HOST_AUDIO_FRAME_SAMPLES).collect());
    }
    drop(queued);

    if !output.is_empty() {
        let previous =
            BROADCAST_MIC_FRAMES_DRAINED.fetch_add(output.len() as u64, Ordering::AcqRel);
        let total = previous + output.len() as u64;
        if previous == 0 || previous / 500 != total / 500 {
            log::info!("iOS ReplayKit microphone drained {total} voice frames");
        }
    }
    output
}

#[cfg(target_os = "ios")]
pub(crate) fn send_host_voice_call_audio(samples: Vec<f32>) {
    if samples.len() != HOST_AUDIO_FRAME_SAMPLES {
        log::warn!(
            "Ignoring iOS host voice PCM frame with unexpected length {}",
            samples.len()
        );
        return;
    }
    if path(BROADCAST_MIC_ACTIVE_FILE_NAME).is_file() {
        return;
    }

    let directory = host_capture_directory();
    if let Err(err) = fs::create_dir_all(&directory) {
        log::warn!("Failed to create iOS host voice capture queue: {err}");
        return;
    }
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    let destination = directory.join(format!("{timestamp:020}-{}.bin", uuid::Uuid::new_v4()));
    let temporary = destination.with_extension("tmp");
    let payload = make_audio_record(48_000, 1, &samples);
    match File::create(&temporary)
        .and_then(|mut file| {
            file.write_all(&payload)?;
            file.sync_all()
        })
        .and_then(|_| fs::rename(&temporary, &destination))
    {
        Ok(()) => {}
        Err(err) => {
            let _ = fs::remove_file(&temporary);
            log::warn!("Failed to enqueue iOS host voice capture frame: {err}");
        }
    }
}

#[cfg(target_os = "ios")]
pub(crate) fn take_host_voice_call_audio() -> Vec<Vec<f32>> {
    const MAX_BATCH: usize = 8;
    let broadcast_frames = take_broadcast_host_voice_audio();
    if !broadcast_frames.is_empty() {
        // ReplayKit is the authoritative microphone source while broadcasting.
        // Discard fallback files so the same microphone is never sent twice.
        if BROADCAST_FALLBACK_CLEARED
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
        {
            clear_host_capture_directory();
        }
        return broadcast_frames;
    }
    let directory = host_capture_directory();
    let Ok(entries) = fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut frames = entries
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().and_then(|ext| ext.to_str()) == Some("bin"))
        .collect::<Vec<_>>();
    frames.sort();

    let mut output = Vec::new();
    for frame_path in frames.into_iter().take(MAX_BATCH) {
        let data = fs::read(&frame_path).ok();
        let _ = fs::remove_file(&frame_path);
        let Some(data) = data else {
            continue;
        };
        if let Some(samples) = decode_host_capture_audio(&data) {
            output.push(samples);
        } else {
            log::warn!("Ignoring malformed iOS host voice capture frame");
        }
    }
    output
}

#[cfg(target_os = "ios")]
fn decode_host_capture_audio(data: &[u8]) -> Option<Vec<f32>> {
    if data.len() != AUDIO_HEADER_LEN + HOST_AUDIO_FRAME_SAMPLES * std::mem::size_of::<f32>() {
        return None;
    }
    let read_u32 = |offset: usize| -> Option<u32> {
        let bytes: [u8; 4] = data.get(offset..offset + 4)?.try_into().ok()?;
        Some(u32::from_le_bytes(bytes))
    };
    let read_u16 = |offset: usize| -> Option<u16> {
        let bytes: [u8; 2] = data.get(offset..offset + 2)?.try_into().ok()?;
        Some(u16::from_le_bytes(bytes))
    };
    if read_u32(0)? != AUDIO_MAGIC
        || read_u32(4)? != 48_000
        || read_u16(8)? != 1
        || read_u32(12)? as usize != HOST_AUDIO_FRAME_SAMPLES
    {
        return None;
    }
    (0..HOST_AUDIO_FRAME_SAMPLES)
        .map(|index| {
            read_u32(AUDIO_HEADER_LEN + index * std::mem::size_of::<u32>()).map(f32::from_bits)
        })
        .collect()
}

#[cfg(target_os = "ios")]
pub(crate) fn request_host_voice_call_close() -> bool {
    let Some(state) = read_json::<VoiceCallState>(STATE_FILE_NAME) else {
        return false;
    };
    if !state.active || state.request_id.is_empty() {
        return false;
    }
    match write_json(
        HOST_CLOSE_FILE_NAME,
        &HostVoiceCallClose {
            request_id: state.request_id,
        },
    ) {
        Ok(()) => true,
        Err(err) => {
            log::warn!("Failed to request iOS host voice call close: {err}");
            false
        }
    }
}

#[cfg(target_os = "ios")]
pub(crate) fn take_host_voice_call_close(request_id: &str) -> bool {
    let Some(close) = read_json::<HostVoiceCallClose>(HOST_CLOSE_FILE_NAME) else {
        return false;
    };
    if close.request_id != request_id {
        return false;
    }
    remove_file(HOST_CLOSE_FILE_NAME);
    true
}

pub(crate) fn append_playback_audio(sample_rate: u32, channels: u32, samples: &[f32]) {
    if sample_rate == 0
        || channels == 0
        || channels > 2
        || samples.is_empty()
        || samples.len() > MAX_AUDIO_SAMPLES
        || samples.len() % channels as usize != 0
    {
        log::warn!(
            "Ignoring invalid iOS voice audio frame: rate={sample_rate}, channels={channels}, samples={}",
            samples.len()
        );
        return;
    }

    let destination = path(AUDIO_FILE_NAME);
    let Some(parent) = destination.parent() else {
        return;
    };
    if let Err(err) = fs::create_dir_all(parent) {
        log::warn!("Failed to create iOS voice audio directory: {err}");
        return;
    }
    if destination
        .metadata()
        .map(|metadata| metadata.len() >= MAX_AUDIO_FILE_BYTES)
        .unwrap_or(false)
    {
        if let Err(err) = File::create(&destination) {
            log::warn!("Failed to rotate iOS voice audio buffer: {err}");
            return;
        }
    }

    let payload = make_audio_record(sample_rate, channels, samples);

    match OpenOptions::new()
        .create(true)
        .append(true)
        .open(destination)
    {
        Ok(mut file) => {
            if let Err(err) = file.write_all(&payload).and_then(|_| file.flush()) {
                log::warn!("Failed to append iOS voice audio frame: {err}");
            }
        }
        Err(err) => log::warn!("Failed to open iOS voice audio buffer: {err}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    fn reset_broadcast_audio(active: bool) {
        VOICE_CALL_ACTIVE.store(active, Ordering::Release);
        clear_broadcast_host_audio();
    }

    #[test]
    fn replaykit_microphone_is_chunked_into_twenty_millisecond_frames() {
        let _guard = TEST_LOCK.lock().unwrap();
        reset_broadcast_audio(true);

        let samples = vec![0.25; HOST_AUDIO_FRAME_SAMPLES * 2 + 17];
        assert_eq!(push_broadcast_host_voice_audio(&samples), 0);
        let frames = take_broadcast_host_voice_audio();

        assert_eq!(frames.len(), 2);
        assert!(frames
            .iter()
            .all(|frame| frame.len() == HOST_AUDIO_FRAME_SAMPLES));
        assert!(take_broadcast_host_voice_audio().is_empty());
        reset_broadcast_audio(false);
    }

    #[test]
    fn replaykit_microphone_rejects_inactive_or_invalid_audio() {
        let _guard = TEST_LOCK.lock().unwrap();
        reset_broadcast_audio(false);
        assert_eq!(
            push_broadcast_host_voice_audio(&[0.0; HOST_AUDIO_FRAME_SAMPLES]),
            ERR_VOICE_CALL_INACTIVE
        );

        reset_broadcast_audio(true);
        assert_eq!(
            push_broadcast_host_voice_audio(&[f32::NAN]),
            ERR_INVALID_VOICE_AUDIO
        );
        reset_broadcast_audio(false);
    }
}
