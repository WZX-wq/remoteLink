use std::{
    collections::VecDeque,
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
};

pub(crate) const ERR_PAUSED: i32 = 4;
pub(crate) const ERR_INVALID_AUDIO: i32 = 5;
pub(crate) const ERR_TRANSPORT_INACTIVE: i32 = 6;

/// 10 ms of interleaved 48 kHz stereo floating-point PCM.
pub(crate) const AUDIO_FRAME_SAMPLES: usize = 960;
const MAX_QUEUED_AUDIO_SAMPLES: usize = AUDIO_FRAME_SAMPLES * 120;

static ACTIVE: AtomicBool = AtomicBool::new(false);
static PAUSED: AtomicBool = AtomicBool::new(false);

lazy_static::lazy_static! {
    // The broadcast extension's Rust host owns these copies. Do not retain
    // CoreMedia-owned buffers after `processSampleBuffer` returns.
    static ref AUDIO_SAMPLES: Mutex<VecDeque<f32>> = Mutex::new(VecDeque::new());
}

fn clear() {
    if let Ok(mut samples) = AUDIO_SAMPLES.lock() {
        samples.clear();
    }
}

pub(crate) fn start() {
    PAUSED.store(false, Ordering::Release);
    ACTIVE.store(true, Ordering::Release);
    clear();
}

pub(crate) fn pause() {
    PAUSED.store(true, Ordering::Release);
    clear();
}

pub(crate) fn resume() {
    PAUSED.store(false, Ordering::Release);
    clear();
}

pub(crate) fn stop() {
    ACTIVE.store(false, Ordering::Release);
    PAUSED.store(false, Ordering::Release);
    clear();
}

pub(crate) fn push_audio_samples(samples: &[f32]) -> i32 {
    if PAUSED.load(Ordering::Acquire) {
        return ERR_PAUSED;
    }
    if !ACTIVE.load(Ordering::Acquire) {
        return ERR_TRANSPORT_INACTIVE;
    }
    if samples.is_empty()
        || samples.len() % 2 != 0
        || samples.iter().any(|sample| !sample.is_finite())
    {
        return ERR_INVALID_AUDIO;
    }

    let Ok(mut queued) = AUDIO_SAMPLES.lock() else {
        return ERR_INVALID_AUDIO;
    };
    let overflow = queued
        .len()
        .saturating_add(samples.len())
        .saturating_sub(MAX_QUEUED_AUDIO_SAMPLES);
    for _ in 0..overflow {
        queued.pop_front();
    }
    queued.extend(samples.iter().copied());
    0
}

/// Returns one Opus-compatible 10 ms PCM block for the iOS audio service.
pub(crate) fn take_audio_frame(dst: &mut Vec<f32>) -> bool {
    if PAUSED.load(Ordering::Acquire) || !ACTIVE.load(Ordering::Acquire) {
        return false;
    }
    let Ok(mut queued) = AUDIO_SAMPLES.lock() else {
        return false;
    };
    if queued.len() < AUDIO_FRAME_SAMPLES {
        return false;
    }
    dst.clear();
    dst.extend(queued.drain(..AUDIO_FRAME_SAMPLES));
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn queued_ios_audio_is_emitted_as_10ms_stereo_frames() {
        let _guard = TEST_LOCK.lock().unwrap();
        start();

        let source: Vec<f32> = (0..(AUDIO_FRAME_SAMPLES + 8))
            .map(|value| value as f32 / 100.0)
            .collect();
        assert_eq!(push_audio_samples(&source), 0);

        let mut frame = Vec::new();
        assert!(take_audio_frame(&mut frame));
        assert_eq!(frame.len(), AUDIO_FRAME_SAMPLES);
        assert_eq!(frame, source[..AUDIO_FRAME_SAMPLES]);

        stop();
    }

    #[test]
    fn ios_audio_rejects_unpaired_or_non_finite_samples() {
        let _guard = TEST_LOCK.lock().unwrap();
        start();

        assert_eq!(push_audio_samples(&[0.0]), ERR_INVALID_AUDIO);
        assert_eq!(push_audio_samples(&[0.0, f32::NAN]), ERR_INVALID_AUDIO);

        stop();
    }
}
