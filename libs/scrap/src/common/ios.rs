use crate::external_frame::{ExternalFrame, FrameMailbox, FrameSubmitError};
use crate::{Frame, Pixfmt, TraitCapturer, TraitPixelBuffer};
use lazy_static::lazy_static;
use std::{io, time::Duration};

lazy_static! {
    static ref FRAME_MAILBOX: FrameMailbox = FrameMailbox::default();
}

pub fn submit_bgra_frame(
    data: &[u8],
    width: usize,
    height: usize,
    stride: usize,
) -> Result<u64, FrameSubmitError> {
    FRAME_MAILBOX.submit_bgra(data, width, height, stride)
}

pub fn clear_bgra_frames() {
    FRAME_MAILBOX.clear();
}

pub fn current_frame_size() -> Option<(usize, usize)> {
    FRAME_MAILBOX.latest_size()
}

pub struct Capturer {
    display: Display,
    current: Option<ExternalFrame>,
}

impl Capturer {
    pub fn new(display: Display) -> io::Result<Self> {
        Ok(Self {
            display,
            current: None,
        })
    }

    pub fn width(&self) -> usize {
        self.display.width()
    }

    pub fn height(&self) -> usize {
        self.display.height()
    }
}

impl TraitCapturer for Capturer {
    fn frame<'a>(&'a mut self, _timeout: Duration) -> io::Result<Frame<'a>> {
        self.current = FRAME_MAILBOX.take_latest();
        let frame = self
            .current
            .as_ref()
            .ok_or_else(|| io::Error::from(io::ErrorKind::WouldBlock))?;
        if frame.width() != self.display.width() || frame.height() != self.display.height() {
            // Force VideoService to announce the new display geometry and rebuild its encoder.
            // Encoding a landscape ReplayKit frame with the portrait encoder causes a blank view.
            return Err(io::Error::from(io::ErrorKind::Interrupted));
        }
        Ok(Frame::PixelBuffer(PixelBuffer { frame }))
    }
}

pub struct PixelBuffer<'a> {
    frame: &'a ExternalFrame,
}

impl TraitPixelBuffer for PixelBuffer<'_> {
    fn data(&self) -> &[u8] {
        self.frame.data()
    }

    fn width(&self) -> usize {
        self.frame.width()
    }

    fn height(&self) -> usize {
        self.frame.height()
    }

    fn stride(&self) -> Vec<usize> {
        vec![self.frame.stride()]
    }

    fn pixfmt(&self) -> Pixfmt {
        Pixfmt::BGRA
    }
}

pub struct Display {
    width: usize,
    height: usize,
}

impl Display {
    pub fn primary() -> io::Result<Self> {
        let (width, height) = current_frame_size()
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no ReplayKit frame"))?;
        Ok(Self { width, height })
    }

    pub fn all() -> io::Result<Vec<Self>> {
        Ok(vec![Self::primary()?])
    }

    pub fn width(&self) -> usize {
        self.width
    }

    pub fn height(&self) -> usize {
        self.height
    }

    pub fn scale(&self) -> f64 {
        1.0
    }

    pub fn name(&self) -> String {
        "iOS Screen".to_owned()
    }

    pub fn is_online(&self) -> bool {
        true
    }

    pub fn origin(&self) -> (i32, i32) {
        (0, 0)
    }

    pub fn is_primary(&self) -> bool {
        true
    }
}
