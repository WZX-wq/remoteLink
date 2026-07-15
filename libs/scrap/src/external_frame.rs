use std::sync::Mutex;

pub const MAX_FRAME_BYTES: usize = 64 * 1024 * 1024;

#[derive(Clone, Debug)]
pub struct ExternalFrame {
    data: Vec<u8>,
    width: usize,
    height: usize,
    stride: usize,
    sequence: u64,
}

impl ExternalFrame {
    pub fn data(&self) -> &[u8] {
        &self.data
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    pub fn stride(&self) -> usize {
        self.stride
    }

    pub fn sequence(&self) -> u64 {
        self.sequence
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrameSubmitError {
    InvalidDimensions,
    StrideTooSmall,
    DataTooShort,
    FrameTooLarge,
}

#[derive(Default)]
struct FrameMailboxState {
    latest: Option<ExternalFrame>,
    latest_size: Option<(usize, usize)>,
    sequence: u64,
}

#[derive(Default)]
pub struct FrameMailbox {
    state: Mutex<FrameMailboxState>,
}

impl FrameMailbox {
    pub fn submit_bgra(
        &self,
        data: &[u8],
        width: usize,
        height: usize,
        stride: usize,
    ) -> Result<u64, FrameSubmitError> {
        if width == 0 || height == 0 {
            return Err(FrameSubmitError::InvalidDimensions);
        }
        let minimum_stride = width
            .checked_mul(4)
            .ok_or(FrameSubmitError::FrameTooLarge)?;
        if stride < minimum_stride {
            return Err(FrameSubmitError::StrideTooSmall);
        }
        let frame_len = stride
            .checked_mul(height)
            .ok_or(FrameSubmitError::FrameTooLarge)?;
        if frame_len > MAX_FRAME_BYTES {
            return Err(FrameSubmitError::FrameTooLarge);
        }
        if data.len() < frame_len {
            return Err(FrameSubmitError::DataTooShort);
        }

        let mut state = self.state.lock().unwrap();
        state.sequence = state.sequence.wrapping_add(1).max(1);
        let sequence = state.sequence;
        state.latest_size = Some((width, height));
        state.latest = Some(ExternalFrame {
            data: data[..frame_len].to_vec(),
            width,
            height,
            stride,
            sequence,
        });
        Ok(sequence)
    }

    pub fn take_latest(&self) -> Option<ExternalFrame> {
        self.state.lock().unwrap().latest.take()
    }

    pub fn latest_size(&self) -> Option<(usize, usize)> {
        self.state.lock().unwrap().latest_size
    }

    pub fn clear(&self) {
        let mut state = self.state.lock().unwrap();
        state.latest = None;
        state.latest_size = None;
    }
}

#[cfg(test)]
mod tests {
    use super::{FrameMailbox, FrameSubmitError, MAX_FRAME_BYTES};

    #[test]
    fn accepts_bgra_frame_with_padded_stride() {
        let mailbox = FrameMailbox::default();
        let data = (0u8..24).collect::<Vec<_>>();

        let sequence = mailbox.submit_bgra(&data, 2, 2, 12).unwrap();
        let frame = mailbox.take_latest().unwrap();

        assert_eq!(sequence, 1);
        assert_eq!(frame.sequence(), 1);
        assert_eq!(frame.width(), 2);
        assert_eq!(frame.height(), 2);
        assert_eq!(frame.stride(), 12);
        assert_eq!(frame.data(), data);
        assert_eq!(mailbox.latest_size(), Some((2, 2)));
    }

    #[test]
    fn rejects_invalid_bgra_layouts() {
        let mailbox = FrameMailbox::default();

        assert_eq!(
            mailbox.submit_bgra(&[], 0, 1, 4),
            Err(FrameSubmitError::InvalidDimensions)
        );
        assert_eq!(
            mailbox.submit_bgra(&[0; 8], 2, 1, 4),
            Err(FrameSubmitError::StrideTooSmall)
        );
        assert_eq!(
            mailbox.submit_bgra(&[0; 15], 2, 2, 8),
            Err(FrameSubmitError::DataTooShort)
        );
        assert_eq!(
            mailbox.submit_bgra(&[0; 4], 1, MAX_FRAME_BYTES / 4 + 1, 4),
            Err(FrameSubmitError::FrameTooLarge)
        );
    }

    #[test]
    fn keeps_only_the_newest_frame() {
        let mailbox = FrameMailbox::default();

        assert_eq!(mailbox.submit_bgra(&[1; 4], 1, 1, 4), Ok(1));
        assert_eq!(mailbox.submit_bgra(&[2; 4], 1, 1, 4), Ok(2));

        let frame = mailbox.take_latest().unwrap();
        assert_eq!(frame.sequence(), 2);
        assert_eq!(frame.data(), &[2; 4]);
        assert!(mailbox.take_latest().is_none());
    }

    #[test]
    fn clear_removes_frame_and_dimensions_without_reusing_sequence() {
        let mailbox = FrameMailbox::default();
        assert_eq!(mailbox.submit_bgra(&[3; 4], 1, 1, 4), Ok(1));

        mailbox.clear();

        assert!(mailbox.take_latest().is_none());
        assert_eq!(mailbox.latest_size(), None);
        assert_eq!(mailbox.submit_bgra(&[4; 4], 1, 1, 4), Ok(2));
    }
}
