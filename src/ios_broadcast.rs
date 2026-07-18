use hbb_common::config::{self, Config};
use std::{
    ffi::c_void,
    slice,
    sync::{
        atomic::{AtomicBool, Ordering},
        Once,
    },
};

const OK: i32 = 0;
const ERR_INVALID_CONFIG_DIR: i32 = 1;
const ERR_INVALID_FRAME: i32 = 2;
const ERR_FRAME_TOO_LARGE: i32 = 3;
const ERR_PAUSED: i32 = crate::ios_broadcast_audio::ERR_PAUSED;

static INITIALIZE: Once = Once::new();
static HOST_THREAD_STARTED: AtomicBool = AtomicBool::new(false);
static ACTIVE: AtomicBool = AtomicBool::new(false);
static PAUSED: AtomicBool = AtomicBool::new(false);

fn bytes_to_string(ptr: *const u8, len: usize) -> Option<String> {
    if ptr.is_null() || len == 0 {
        return None;
    }
    let bytes = unsafe { slice::from_raw_parts(ptr, len) };
    String::from_utf8(bytes.to_vec()).ok()
}

#[no_mangle]
pub extern "C" fn kq_ios_broadcast_start(config_dir: *const u8, config_dir_len: usize) -> i32 {
    let Some(config_dir) = bytes_to_string(config_dir, config_dir_len) else {
        return ERR_INVALID_CONFIG_DIR;
    };
    if config_dir.trim().is_empty() {
        return ERR_INVALID_CONFIG_DIR;
    }

    *config::APP_DIR.write().unwrap() = config_dir;
    INITIALIZE.call_once(|| {
        crate::load_custom_client();
        let _ = crate::common::global_init();
    });

    Config::set_option("stop-service".to_owned(), String::new());
    PAUSED.store(false, Ordering::Release);
    ACTIVE.store(true, Ordering::Release);
    crate::ios_broadcast_audio::start();

    if HOST_THREAD_STARTED
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_ok()
    {
        std::thread::spawn(|| crate::start_server(true));
    } else {
        crate::RendezvousMediator::restart();
    }
    OK
}

#[no_mangle]
pub extern "C" fn kq_ios_broadcast_push_bgra(
    data: *const c_void,
    data_len: usize,
    width: usize,
    height: usize,
    stride: usize,
) -> i32 {
    if PAUSED.load(Ordering::Acquire) {
        return ERR_PAUSED;
    }
    if data.is_null() || data_len == 0 {
        return ERR_INVALID_FRAME;
    }

    let previous_size = scrap::current_frame_size();
    let data = unsafe { slice::from_raw_parts(data.cast::<u8>(), data_len) };
    match scrap::submit_bgra_frame(data, width, height, stride) {
        Ok(_) => {
            if ACTIVE.load(Ordering::Acquire)
                && previous_size.is_some()
                && previous_size != Some((width, height))
            {
                crate::server::video_service::refresh();
            }
            OK
        }
        Err(scrap::external_frame::FrameSubmitError::FrameTooLarge) => ERR_FRAME_TOO_LARGE,
        Err(_) => ERR_INVALID_FRAME,
    }
}

#[no_mangle]
pub extern "C" fn kq_ios_broadcast_push_audio_f32(data: *const f32, sample_count: usize) -> i32 {
    if data.is_null() || sample_count == 0 {
        return crate::ios_broadcast_audio::ERR_INVALID_AUDIO;
    }
    let samples = unsafe { slice::from_raw_parts(data, sample_count) };
    crate::ios_broadcast_audio::push_audio_samples(samples)
}

#[no_mangle]
pub extern "C" fn kq_ios_broadcast_pause() {
    PAUSED.store(true, Ordering::Release);
    crate::ios_broadcast_audio::pause();
}

#[no_mangle]
pub extern "C" fn kq_ios_broadcast_resume() {
    PAUSED.store(false, Ordering::Release);
    crate::ios_broadcast_audio::resume();
    if ACTIVE.load(Ordering::Acquire) {
        crate::server::video_service::refresh();
    }
}

#[no_mangle]
pub extern "C" fn kq_ios_broadcast_stop() {
    ACTIVE.store(false, Ordering::Release);
    PAUSED.store(false, Ordering::Release);
    crate::ios_broadcast_audio::stop();
    scrap::clear_bgra_frames();
    Config::set_option("stop-service".to_owned(), "Y".to_owned());
    crate::RendezvousMediator::restart();
}
