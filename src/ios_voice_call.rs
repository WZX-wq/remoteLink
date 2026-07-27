#[cfg(target_os = "ios")]
use hbb_common::tokio::sync::mpsc;
use hbb_common::{config::Config, get_time, log};
use serde_derive::{Deserialize, Serialize};
#[cfg(target_os = "ios")]
use std::sync::Mutex;
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::PathBuf,
};

pub(crate) const REQUEST_FILE_NAME: &str = "kq-ios-voice-call-request.json";
pub(crate) const RESPONSE_FILE_NAME: &str = "kq-ios-voice-call-response.json";
pub(crate) const STATE_FILE_NAME: &str = "kq-ios-voice-call-state.json";
pub(crate) const AUDIO_FILE_NAME: &str = "kq-ios-voice-call-audio.bin";

const REQUEST_TTL_SECS: i64 = 45;
const AUDIO_MAGIC: u32 = 0x4156_514B; // "KQVA" in little endian.
const AUDIO_HEADER_LEN: usize = 16;
const MAX_AUDIO_FILE_BYTES: u64 = 1_024 * 1_024;
const MAX_AUDIO_SAMPLES: usize = 11_520;

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

#[cfg(target_os = "ios")]
struct HostVoiceCallSender {
    request_id: String,
    tx: mpsc::UnboundedSender<crate::ipc::Data>,
}

#[cfg(target_os = "ios")]
lazy_static::lazy_static! {
    static ref HOST_VOICE_CALL_SENDER: Mutex<Option<HostVoiceCallSender>> = Mutex::new(None);
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
}

pub(crate) fn close_voice_call(request_id: &str) {
    #[cfg(target_os = "ios")]
    clear_host_voice_call_sender(request_id);
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
}

pub(crate) fn reset_voice_call() {
    #[cfg(target_os = "ios")]
    clear_all_host_voice_call_senders();
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
}

#[cfg(target_os = "ios")]
pub(crate) fn bind_host_voice_call_sender(
    request_id: &str,
    tx: mpsc::UnboundedSender<crate::ipc::Data>,
) {
    let mut sender = HOST_VOICE_CALL_SENDER.lock().unwrap();
    *sender = Some(HostVoiceCallSender {
        request_id: request_id.to_owned(),
        tx,
    });
}

#[cfg(target_os = "ios")]
pub(crate) fn clear_host_voice_call_sender(request_id: &str) {
    let mut sender = HOST_VOICE_CALL_SENDER.lock().unwrap();
    if sender
        .as_ref()
        .map(|current| current.request_id == request_id)
        .unwrap_or(false)
    {
        *sender = None;
    }
}

#[cfg(target_os = "ios")]
fn clear_all_host_voice_call_senders() {
    *HOST_VOICE_CALL_SENDER.lock().unwrap() = None;
}

#[cfg(target_os = "ios")]
pub(crate) fn send_host_voice_call_audio(samples: Vec<f32>) {
    const SAMPLES_PER_FRAME: usize = 960;
    if samples.len() != SAMPLES_PER_FRAME {
        log::warn!(
            "Ignoring iOS host voice PCM frame with unexpected length {}",
            samples.len()
        );
        return;
    }

    let tx = HOST_VOICE_CALL_SENDER
        .lock()
        .unwrap()
        .as_ref()
        .map(|sender| sender.tx.clone());
    if let Some(tx) = tx {
        if tx
            .send(crate::ipc::Data::IOSVoiceCallAudio(samples))
            .is_err()
        {
            log::warn!("iOS host voice call is no longer connected");
            clear_all_host_voice_call_senders();
        }
    }
}

#[cfg(target_os = "ios")]
pub(crate) fn close_host_voice_call_from_ui() -> bool {
    let tx = HOST_VOICE_CALL_SENDER
        .lock()
        .unwrap()
        .as_ref()
        .map(|sender| sender.tx.clone());
    let Some(tx) = tx else {
        return false;
    };
    tx.send(crate::ipc::Data::CloseVoiceCall(
        "Closed by iOS host".to_owned(),
    ))
    .is_ok()
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
