#![allow(non_camel_case_types)]
#![allow(non_snake_case)]
#![allow(non_upper_case_globals)]
#![allow(improper_ctypes)]
#![allow(dead_code)]

include!(concat!(env!("OUT_DIR"), "/yuv_ffi.rs"));

use crate::PixelBuffer;
use crate::{generate_call_macro, EncodeYuvFormat, Pixfmt, TraitPixelBuffer};
use hbb_common::{bail, log, ResultType};

generate_call_macro!(call_yuv, false);

struct FrameData<'a> {
    data: &'a [u8],
    stride: &'a [usize],
    pixfmt: Pixfmt,
    width: usize,
    height: usize,
}

pub fn convert_to_yuv(
    captured: &PixelBuffer,
    dst_fmt: EncodeYuvFormat,
    dst: &mut Vec<u8>,
    mid_data: &mut Vec<u8>,
) -> ResultType<()> {
    let stride = captured.stride();
    convert_frame_data_to_yuv(
        FrameData {
            data: captured.data(),
            stride: &stride,
            pixfmt: captured.pixfmt(),
            width: captured.width(),
            height: captured.height(),
        },
        &dst_fmt,
        dst,
        mid_data,
    )
}

/// Convert a captured frame to the encoder's dimensions, scaling down before
/// color conversion when the selected stream profile has a smaller frame size.
pub fn convert_to_yuv_with_scale(
    captured: &PixelBuffer,
    dst_fmt: EncodeYuvFormat,
    dst: &mut Vec<u8>,
    mid_data: &mut Vec<u8>,
    scale_data: &mut Vec<u8>,
) -> ResultType<()> {
    let src_width = captured.width();
    let src_height = captured.height();
    if src_width == dst_fmt.w && src_height == dst_fmt.h {
        return convert_to_yuv(captured, dst_fmt, dst, mid_data);
    }
    if src_width < dst_fmt.w || src_height < dst_fmt.h {
        bail!(
            "cannot scale captured frame up: ({src_width}, {src_height}) -> ({}, {})",
            dst_fmt.w,
            dst_fmt.h
        );
    }

    let src = captured.data();
    let src_stride = captured.stride();
    let src_pixfmt = captured.pixfmt();
    validate_rgb_input(src, &src_stride, src_pixfmt, src_width, src_height)?;

    let dst_stride = dst_fmt
        .w
        .checked_mul(4)
        .ok_or_else(|| hbb_common::anyhow::anyhow!("scaled frame stride overflow"))?;
    let dst_len = dst_stride
        .checked_mul(dst_fmt.h)
        .ok_or_else(|| hbb_common::anyhow::anyhow!("scaled frame buffer overflow"))?;
    scale_data.resize(dst_len, 0);

    let mut scale = |input: &[u8], input_stride: usize| -> ResultType<()> {
        call_yuv!(ARGBScale(
            input.as_ptr(),
            input_stride as _,
            src_width as _,
            src_height as _,
            scale_data.as_mut_ptr(),
            dst_stride as _,
            dst_fmt.w as _,
            dst_fmt.h as _,
            FilterMode::kFilterBox,
        ));
        Ok(())
    };

    let scaled_pixfmt = match src_pixfmt {
        Pixfmt::BGRA | Pixfmt::RGBA => {
            let input_stride = *src_stride
                .first()
                .ok_or_else(|| hbb_common::anyhow::anyhow!("missing source stride"))?;
            scale(src, input_stride)?;
            src_pixfmt
        }
        Pixfmt::RGB565LE => {
            let input_stride = *src_stride
                .first()
                .ok_or_else(|| hbb_common::anyhow::anyhow!("missing source stride"))?;
            let argb_stride = src_width
                .checked_mul(4)
                .ok_or_else(|| hbb_common::anyhow::anyhow!("ARGB frame stride overflow"))?;
            let argb_len = argb_stride
                .checked_mul(src_height)
                .ok_or_else(|| hbb_common::anyhow::anyhow!("ARGB frame buffer overflow"))?;
            mid_data.resize(argb_len, 0);
            call_yuv!(RGB565ToARGB(
                src.as_ptr(),
                input_stride as _,
                mid_data.as_mut_ptr(),
                argb_stride as _,
                src_width as _,
                src_height as _,
            ));
            scale(mid_data, argb_stride)?;
            Pixfmt::BGRA
        }
        _ => {
            bail!("unsupported scaled source pixel format: {src_pixfmt:?}",);
        }
    };

    convert_frame_data_to_yuv(
        FrameData {
            data: scale_data,
            stride: &[dst_stride],
            pixfmt: scaled_pixfmt,
            width: dst_fmt.w,
            height: dst_fmt.h,
        },
        &dst_fmt,
        dst,
        mid_data,
    )
}

fn validate_rgb_input(
    src: &[u8],
    src_stride: &[usize],
    src_pixfmt: Pixfmt,
    src_width: usize,
    src_height: usize,
) -> ResultType<()> {
    if !matches!(src_pixfmt, Pixfmt::BGRA | Pixfmt::RGBA | Pixfmt::RGB565LE) {
        return Ok(());
    }
    let stride = *src_stride
        .first()
        .ok_or_else(|| hbb_common::anyhow::anyhow!("missing source stride"))?;
    let min_stride = src_width
        .checked_mul(src_pixfmt.bytes_per_pixel())
        .ok_or_else(|| hbb_common::anyhow::anyhow!("source stride overflow"))?;
    if stride < min_stride {
        bail!("src_stride too small: {stride} < {min_stride}");
    }
    let min_len = stride
        .checked_mul(src_height)
        .ok_or_else(|| hbb_common::anyhow::anyhow!("source buffer size overflow"))?;
    if src.len() < min_len {
        bail!("wrong src len, {} < {stride} * {src_height}", src.len());
    }
    Ok(())
}

fn convert_frame_data_to_yuv(
    source: FrameData,
    dst_fmt: &EncodeYuvFormat,
    dst: &mut Vec<u8>,
    mid_data: &mut Vec<u8>,
) -> ResultType<()> {
    let src = source.data;
    let src_stride = source.stride;
    let src_pixfmt = source.pixfmt;
    let src_width = source.width;
    let src_height = source.height;
    if src_width > dst_fmt.w || src_height > dst_fmt.h {
        bail!(
            "src rect > dst rect: ({src_width}, {src_height}) > ({},{})",
            dst_fmt.w,
            dst_fmt.h
        );
    }
    validate_rgb_input(src, src_stride, src_pixfmt, src_width, src_height)?;
    let align = |x: usize| (x + 63) / 64 * 64;
    let unsupported = format!(
        "unsupported pixfmt conversion: {src_pixfmt:?} -> {:?}",
        dst_fmt.pixfmt
    );

    match (src_pixfmt, dst_fmt.pixfmt) {
        (Pixfmt::BGRA, Pixfmt::I420)
        | (Pixfmt::RGBA, Pixfmt::I420)
        | (Pixfmt::RGB565LE, Pixfmt::I420) => {
            let dst_stride_y = dst_fmt.stride[0];
            let dst_stride_uv = dst_fmt.stride[1];
            dst.resize(dst_fmt.h * dst_stride_y * 2, 0); // waste some memory to ensure memory safety
            let dst_y = dst.as_mut_ptr();
            let dst_u = dst[dst_fmt.u..].as_mut_ptr();
            let dst_v = dst[dst_fmt.v..].as_mut_ptr();
            let f = match src_pixfmt {
                Pixfmt::BGRA => ARGBToI420,
                Pixfmt::RGBA => ABGRToI420,
                Pixfmt::RGB565LE => RGB565ToI420,
                _ => bail!(unsupported),
            };
            call_yuv!(f(
                src.as_ptr(),
                src_stride[0] as _,
                dst_y,
                dst_stride_y as _,
                dst_u,
                dst_stride_uv as _,
                dst_v,
                dst_stride_uv as _,
                src_width as _,
                src_height as _,
            ));
        }
        (Pixfmt::BGRA, Pixfmt::NV12)
        | (Pixfmt::RGBA, Pixfmt::NV12)
        | (Pixfmt::RGB565LE, Pixfmt::NV12) => {
            let dst_stride_y = dst_fmt.stride[0];
            let dst_stride_uv = dst_fmt.stride[1];
            dst.resize(
                align(dst_fmt.h) * (align(dst_stride_y) + align(dst_stride_uv / 2)),
                0,
            );
            let dst_y = dst.as_mut_ptr();
            let dst_uv = dst[dst_fmt.u..].as_mut_ptr();
            let (input, input_stride) = match src_pixfmt {
                Pixfmt::BGRA => (src.as_ptr(), src_stride[0]),
                Pixfmt::RGBA => (src.as_ptr(), src_stride[0]),
                Pixfmt::RGB565LE => {
                    let mid_stride = src_width * 4;
                    mid_data.resize(mid_stride * src_height, 0);
                    call_yuv!(RGB565ToARGB(
                        src.as_ptr(),
                        src_stride[0] as _,
                        mid_data.as_mut_ptr(),
                        mid_stride as _,
                        src_width as _,
                        src_height as _,
                    ));
                    (mid_data.as_ptr(), mid_stride)
                }
                _ => bail!(unsupported),
            };
            let f = match src_pixfmt {
                Pixfmt::BGRA => ARGBToNV12,
                Pixfmt::RGBA => ABGRToNV12,
                Pixfmt::RGB565LE => ARGBToNV12,
                _ => bail!(unsupported),
            };
            call_yuv!(f(
                input,
                input_stride as _,
                dst_y,
                dst_stride_y as _,
                dst_uv,
                dst_stride_uv as _,
                src_width as _,
                src_height as _,
            ));
        }
        (Pixfmt::BGRA, Pixfmt::I444)
        | (Pixfmt::RGBA, Pixfmt::I444)
        | (Pixfmt::RGB565LE, Pixfmt::I444) => {
            let dst_stride_y = dst_fmt.stride[0];
            let dst_stride_u = dst_fmt.stride[1];
            let dst_stride_v = dst_fmt.stride[2];
            dst.resize(
                align(dst_fmt.h)
                    * (align(dst_stride_y) + align(dst_stride_u) + align(dst_stride_v)),
                0,
            );
            let dst_y = dst.as_mut_ptr();
            let dst_u = dst[dst_fmt.u..].as_mut_ptr();
            let dst_v = dst[dst_fmt.v..].as_mut_ptr();
            let (input, input_stride) = match src_pixfmt {
                Pixfmt::BGRA => (src.as_ptr(), src_stride[0]),
                Pixfmt::RGBA => {
                    mid_data.resize(src.len(), 0);
                    call_yuv!(ABGRToARGB(
                        src.as_ptr(),
                        src_stride[0] as _,
                        mid_data.as_mut_ptr(),
                        src_stride[0] as _,
                        src_width as _,
                        src_height as _,
                    ));
                    (mid_data.as_ptr(), src_stride[0])
                }
                Pixfmt::RGB565LE => {
                    let mid_stride = src_width * 4;
                    mid_data.resize(mid_stride * src_height, 0);
                    call_yuv!(RGB565ToARGB(
                        src.as_ptr(),
                        src_stride[0] as _,
                        mid_data.as_mut_ptr(),
                        mid_stride as _,
                        src_width as _,
                        src_height as _,
                    ));
                    (mid_data.as_ptr(), mid_stride)
                }
                _ => bail!(unsupported),
            };

            call_yuv!(ARGBToI444(
                input,
                input_stride as _,
                dst_y,
                dst_stride_y as _,
                dst_u,
                dst_stride_u as _,
                dst_v,
                dst_stride_v as _,
                src_width as _,
                src_height as _,
            ));
        }
        _ => {
            bail!(unsupported);
        }
    }
    Ok(())
}

pub fn convert(captured: &PixelBuffer, pixfmt: crate::Pixfmt, dst: &mut Vec<u8>) -> ResultType<()> {
    if captured.pixfmt() == pixfmt {
        dst.extend_from_slice(captured.data());
        return Ok(());
    }

    let src = captured.data();
    let src_stride = captured.stride();
    let src_pixfmt = captured.pixfmt();
    let src_width = captured.width();
    let src_height = captured.height();

    let unsupported = format!(
        "unsupported pixfmt conversion: {src_pixfmt:?} -> {:?}",
        pixfmt
    );

    match (src_pixfmt, pixfmt) {
        (crate::Pixfmt::BGRA, crate::Pixfmt::RGBA) | (crate::Pixfmt::RGBA, crate::Pixfmt::BGRA) => {
            dst.resize(src.len(), 0);
            call_yuv!(ABGRToARGB(
                src.as_ptr(),
                src_stride[0] as _,
                dst.as_mut_ptr(),
                src_stride[0] as _,
                src_width as _,
                src_height as _,
            ));
        }
        _ => {
            bail!(unsupported);
        }
    }
    Ok(())
}
