use std::{
    env, fs,
    path::{Path, PathBuf},
    println,
};

#[cfg(all(target_os = "linux", feature = "linux-pkg-config"))]
fn link_pkg_config(name: &str) -> Vec<PathBuf> {
    // sometimes an override is needed
    let pc_name = match name {
        "libvpx" => "vpx",
        _ => name,
    };
    let lib = pkg_config::probe_library(pc_name)
        .expect(format!(
            "unable to find '{pc_name}' development headers with pkg-config (feature linux-pkg-config is enabled).
            try installing '{pc_name}-dev' from your system package manager.").as_str());

    lib.include_paths
}
#[cfg(not(all(target_os = "linux", feature = "linux-pkg-config")))]
fn link_pkg_config(_name: &str) -> Vec<PathBuf> {
    unimplemented!()
}

/// Link vcpkg package.
fn link_vcpkg(mut path: PathBuf, name: &str) -> PathBuf {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let mut target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    if target_arch == "x86_64" {
        target_arch = "x64".to_owned();
    } else if target_arch == "x86" {
        target_arch = "x86".to_owned();
    } else if target_arch == "loongarch64" {
        target_arch = "loongarch64".to_owned();
    } else if target_arch == "aarch64" {
        target_arch = "arm64".to_owned();
    } else {
        target_arch = "arm".to_owned();
    }
    let mut target = if target_os == "macos" {
        if target_arch == "x64" {
            "x64-osx".to_owned()
        } else if target_arch == "arm64" {
            "arm64-osx".to_owned()
        } else {
            format!("{}-{}", target_arch, target_os)
        }
    } else if target_os == "windows" {
        "x64-windows-static".to_owned()
    } else {
        format!("{}-{}", target_arch, target_os)
    };
    if target_arch == "x86" {
        target = target.replace("x64", "x86");
    }
    println!("cargo:info={}", target);
    if let Ok(vcpkg_root) = std::env::var("VCPKG_INSTALLED_ROOT") {
        path = vcpkg_root.into();
    } else {
        path.push("installed");
    }
    path.push(target);
    println!(
        "cargo:rustc-link-lib=static={}",
        name.trim_start_matches("lib")
    );
    println!(
        "cargo:rustc-link-search={}",
        path.join("lib").to_str().unwrap()
    );
    let include = path.join("include");
    println!("cargo:include={}", include.to_str().unwrap());
    include
}

/// Link homebrew package(for Mac M1).
fn link_homebrew_m1(name: &str) -> PathBuf {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    if target_os != "macos" || target_arch != "aarch64" {
        panic!("Couldn't find VCPKG_ROOT, also can't fallback to homebrew because it's only for macos aarch64.");
    }
    let mut path = PathBuf::from("/opt/homebrew/Cellar");
    path.push(name);
    let entries = if let Ok(dir) = std::fs::read_dir(&path) {
        dir
    } else {
        panic!("Could not find package in {}. Make sure your homebrew and package {} are all installed.", path.to_str().unwrap(),&name);
    };
    let mut directories = entries
        .into_iter()
        .filter(|x| x.is_ok())
        .map(|x| x.unwrap().path())
        .filter(|x| x.is_dir())
        .collect::<Vec<_>>();
    // Find the newest version.
    directories.sort_unstable();
    if directories.is_empty() {
        panic!(
            "There's no installed version of {} in /opt/homebrew/Cellar",
            name
        );
    }
    path.push(directories.pop().unwrap());
    // Link the library.
    println!(
        "cargo:rustc-link-lib=static={}",
        name.trim_start_matches("lib")
    );
    // Add the library path.
    println!(
        "cargo:rustc-link-search={}",
        path.join("lib").to_str().unwrap()
    );
    // Add the include path.
    let include = path.join("include");
    println!("cargo:include={}", include.to_str().unwrap());
    include
}

/// Find package. By default, it will try to find vcpkg first, then homebrew(currently only for Mac M1).
/// If building for linux and feature "linux-pkg-config" is enabled, will try to use pkg-config
/// unless check fails (e.g. NO_PKG_CONFIG_libyuv=1)
fn find_package(name: &str) -> Vec<PathBuf> {
    let no_pkg_config_var_name = format!("NO_PKG_CONFIG_{name}");
    println!("cargo:rerun-if-env-changed={no_pkg_config_var_name}");
    if cfg!(all(target_os = "linux", feature = "linux-pkg-config"))
        && std::env::var(no_pkg_config_var_name).as_deref() != Ok("1")
    {
        link_pkg_config(name)
    } else if let Ok(vcpkg_root) = std::env::var("VCPKG_ROOT") {
        vec![link_vcpkg(vcpkg_root.into(), name)]
    } else {
        // Try using homebrew
        vec![link_homebrew_m1(name)]
    }
}

fn generate_bindings(
    ffi_header: &Path,
    include_paths: &[PathBuf],
    ffi_rs: &Path,
    exact_file: &Path,
    regex: &str,
) {
    let mut b = bindgen::builder()
        .header(ffi_header.to_str().unwrap())
        .allowlist_type(regex)
        .allowlist_var(regex)
        .allowlist_function(regex)
        .rustified_enum(regex)
        .trust_clang_mangling(false)
        .layout_tests(false) // breaks 32/64-bit compat
        .generate_comments(false); // comments have prefix /*!\

    for dir in include_paths {
        b = b.clang_arg(format!("-I{}", dir.display()));
    }

    let mut generated = b.generate().unwrap().to_string();
    patch_opaque_codec_cfgs(ffi_rs, &mut generated);
    fs::write(ffi_rs, generated).unwrap();
    fs::copy(ffi_rs, exact_file).ok(); // ignore failure
}

fn replace_generated_struct(
    bindings: &mut String,
    struct_name: &str,
    alias_name: &str,
    replacement: &str,
) {
    let struct_marker = format!("pub struct {struct_name} {{");
    let Some(struct_pos) = bindings.find(&struct_marker) else {
        return;
    };
    let Some(start) = bindings[..struct_pos].rfind("#[repr(C)]") else {
        return;
    };
    let end_marker = format!("pub type {alias_name} = {struct_name};");
    let Some(end_rel) = bindings[struct_pos..].find(&end_marker) else {
        return;
    };
    let end = struct_pos + end_rel + end_marker.len();
    bindings.replace_range(start..end, replacement);
}

// bindgen 0.65 can keep libvpx/libaom encoder/decoder config structs opaque on
// Android because vpx_codec.h/aom_codec.h forward-declare those structs before
// vpx_encoder.h/aom_encoder.h provide the real definitions. The Rust encoders
// set public config fields directly, so patch only these four generated structs
// back to the ABI layout from the installed headers.
fn patch_opaque_codec_cfgs(ffi_rs: &Path, bindings: &mut String) {
    match ffi_rs.file_name().and_then(|s| s.to_str()) {
        Some("vpx_ffi.rs") => {
            replace_generated_struct(
                bindings,
                "vpx_codec_enc_cfg",
                "vpx_codec_enc_cfg_t",
                r#"#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct vpx_codec_enc_cfg {
    pub g_usage: ::std::os::raw::c_uint,
    pub g_threads: ::std::os::raw::c_uint,
    pub g_profile: ::std::os::raw::c_uint,
    pub g_w: ::std::os::raw::c_uint,
    pub g_h: ::std::os::raw::c_uint,
    pub g_bit_depth: vpx_bit_depth_t,
    pub g_input_bit_depth: ::std::os::raw::c_uint,
    pub g_timebase: vpx_rational,
    pub g_error_resilient: vpx_codec_er_flags_t,
    pub g_pass: vpx_enc_pass,
    pub g_lag_in_frames: ::std::os::raw::c_uint,
    pub rc_dropframe_thresh: ::std::os::raw::c_uint,
    pub rc_resize_allowed: ::std::os::raw::c_uint,
    pub rc_scaled_width: ::std::os::raw::c_uint,
    pub rc_scaled_height: ::std::os::raw::c_uint,
    pub rc_resize_up_thresh: ::std::os::raw::c_uint,
    pub rc_resize_down_thresh: ::std::os::raw::c_uint,
    pub rc_end_usage: vpx_rc_mode,
    pub rc_twopass_stats_in: vpx_fixed_buf_t,
    pub rc_firstpass_mb_stats_in: vpx_fixed_buf_t,
    pub rc_target_bitrate: ::std::os::raw::c_uint,
    pub rc_min_quantizer: ::std::os::raw::c_uint,
    pub rc_max_quantizer: ::std::os::raw::c_uint,
    pub rc_undershoot_pct: ::std::os::raw::c_uint,
    pub rc_overshoot_pct: ::std::os::raw::c_uint,
    pub rc_buf_sz: ::std::os::raw::c_uint,
    pub rc_buf_initial_sz: ::std::os::raw::c_uint,
    pub rc_buf_optimal_sz: ::std::os::raw::c_uint,
    pub rc_2pass_vbr_bias_pct: ::std::os::raw::c_uint,
    pub rc_2pass_vbr_minsection_pct: ::std::os::raw::c_uint,
    pub rc_2pass_vbr_maxsection_pct: ::std::os::raw::c_uint,
    pub rc_2pass_vbr_corpus_complexity: ::std::os::raw::c_uint,
    pub kf_mode: vpx_kf_mode,
    pub kf_min_dist: ::std::os::raw::c_uint,
    pub kf_max_dist: ::std::os::raw::c_uint,
    pub ss_number_layers: ::std::os::raw::c_uint,
    pub ss_enable_auto_alt_ref: [::std::os::raw::c_int; 5usize],
    pub ss_target_bitrate: [::std::os::raw::c_uint; 5usize],
    pub ts_number_layers: ::std::os::raw::c_uint,
    pub ts_target_bitrate: [::std::os::raw::c_uint; 5usize],
    pub ts_rate_decimator: [::std::os::raw::c_uint; 5usize],
    pub ts_periodicity: ::std::os::raw::c_uint,
    pub ts_layer_id: [::std::os::raw::c_uint; 16usize],
    pub layer_target_bitrate: [::std::os::raw::c_uint; 12usize],
    pub temporal_layering_mode: ::std::os::raw::c_int,
    pub use_vizier_rc_params: ::std::os::raw::c_int,
    pub active_wq_factor: vpx_rational_t,
    pub err_per_mb_factor: vpx_rational_t,
    pub sr_default_decay_limit: vpx_rational_t,
    pub sr_diff_factor: vpx_rational_t,
    pub kf_err_per_mb_factor: vpx_rational_t,
    pub kf_frame_min_boost_factor: vpx_rational_t,
    pub kf_frame_max_boost_first_factor: vpx_rational_t,
    pub kf_frame_max_boost_subs_factor: vpx_rational_t,
    pub kf_max_total_boost_factor: vpx_rational_t,
    pub gf_max_total_boost_factor: vpx_rational_t,
    pub gf_frame_max_boost_factor: vpx_rational_t,
    pub zm_factor: vpx_rational_t,
    pub rd_mult_inter_qp_fac: vpx_rational_t,
    pub rd_mult_arf_qp_fac: vpx_rational_t,
    pub rd_mult_key_qp_fac: vpx_rational_t,
}
pub type vpx_codec_enc_cfg_t = vpx_codec_enc_cfg;"#,
            );
            replace_generated_struct(
                bindings,
                "vpx_codec_dec_cfg",
                "vpx_codec_dec_cfg_t",
                r#"#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct vpx_codec_dec_cfg {
    pub threads: ::std::os::raw::c_uint,
    pub w: ::std::os::raw::c_uint,
    pub h: ::std::os::raw::c_uint,
}
pub type vpx_codec_dec_cfg_t = vpx_codec_dec_cfg;"#,
            );
        }
        Some("aom_ffi.rs") => {
            replace_generated_struct(
                bindings,
                "aom_codec_enc_cfg",
                "aom_codec_enc_cfg_t",
                r#"#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct aom_codec_enc_cfg {
    pub g_usage: ::std::os::raw::c_uint,
    pub g_threads: ::std::os::raw::c_uint,
    pub g_profile: ::std::os::raw::c_uint,
    pub g_w: ::std::os::raw::c_uint,
    pub g_h: ::std::os::raw::c_uint,
    pub g_limit: ::std::os::raw::c_uint,
    pub g_forced_max_frame_width: ::std::os::raw::c_uint,
    pub g_forced_max_frame_height: ::std::os::raw::c_uint,
    pub g_bit_depth: aom_bit_depth_t,
    pub g_input_bit_depth: ::std::os::raw::c_uint,
    pub g_timebase: aom_rational,
    pub g_error_resilient: aom_codec_er_flags_t,
    pub g_pass: aom_enc_pass,
    pub g_lag_in_frames: ::std::os::raw::c_uint,
    pub rc_dropframe_thresh: ::std::os::raw::c_uint,
    pub rc_resize_mode: ::std::os::raw::c_uint,
    pub rc_resize_denominator: ::std::os::raw::c_uint,
    pub rc_resize_kf_denominator: ::std::os::raw::c_uint,
    pub rc_superres_mode: aom_superres_mode,
    pub rc_superres_denominator: ::std::os::raw::c_uint,
    pub rc_superres_kf_denominator: ::std::os::raw::c_uint,
    pub rc_superres_qthresh: ::std::os::raw::c_uint,
    pub rc_superres_kf_qthresh: ::std::os::raw::c_uint,
    pub rc_end_usage: aom_rc_mode,
    pub rc_twopass_stats_in: aom_fixed_buf_t,
    pub rc_firstpass_mb_stats_in: aom_fixed_buf_t,
    pub rc_target_bitrate: ::std::os::raw::c_uint,
    pub rc_min_quantizer: ::std::os::raw::c_uint,
    pub rc_max_quantizer: ::std::os::raw::c_uint,
    pub rc_undershoot_pct: ::std::os::raw::c_uint,
    pub rc_overshoot_pct: ::std::os::raw::c_uint,
    pub rc_buf_sz: ::std::os::raw::c_uint,
    pub rc_buf_initial_sz: ::std::os::raw::c_uint,
    pub rc_buf_optimal_sz: ::std::os::raw::c_uint,
    pub rc_2pass_vbr_bias_pct: ::std::os::raw::c_uint,
    pub rc_2pass_vbr_minsection_pct: ::std::os::raw::c_uint,
    pub rc_2pass_vbr_maxsection_pct: ::std::os::raw::c_uint,
    pub fwd_kf_enabled: ::std::os::raw::c_int,
    pub kf_mode: aom_kf_mode,
    pub kf_min_dist: ::std::os::raw::c_uint,
    pub kf_max_dist: ::std::os::raw::c_uint,
    pub sframe_dist: ::std::os::raw::c_uint,
    pub sframe_mode: ::std::os::raw::c_uint,
    pub large_scale_tile: ::std::os::raw::c_uint,
    pub monochrome: ::std::os::raw::c_uint,
    pub full_still_picture_hdr: ::std::os::raw::c_uint,
    pub save_as_annexb: ::std::os::raw::c_uint,
    pub tile_width_count: ::std::os::raw::c_int,
    pub tile_height_count: ::std::os::raw::c_int,
    pub tile_widths: [::std::os::raw::c_int; 64usize],
    pub tile_heights: [::std::os::raw::c_int; 64usize],
    pub use_fixed_qp_offsets: ::std::os::raw::c_uint,
    pub fixed_qp_offsets: [::std::os::raw::c_int; 5usize],
    pub encoder_cfg: cfg_options_t,
}
pub type aom_codec_enc_cfg_t = aom_codec_enc_cfg;"#,
            );
            replace_generated_struct(
                bindings,
                "aom_codec_dec_cfg",
                "aom_codec_dec_cfg_t",
                r#"#[repr(C)]
#[derive(Debug, Copy, Clone)]
pub struct aom_codec_dec_cfg {
    pub threads: ::std::os::raw::c_uint,
    pub w: ::std::os::raw::c_uint,
    pub h: ::std::os::raw::c_uint,
    pub allow_lowbitdepth: ::std::os::raw::c_uint,
}
pub type aom_codec_dec_cfg_t = aom_codec_dec_cfg;"#,
            );
        }
        _ => {}
    }
}

fn gen_vcpkg_package(package: &str, ffi_header: &str, generated: &str, regex: &str) {
    let includes = find_package(package);
    let src_dir = env::var_os("CARGO_MANIFEST_DIR").unwrap();
    let src_dir = Path::new(&src_dir);
    let out_dir = env::var_os("OUT_DIR").unwrap();
    let out_dir = Path::new(&out_dir);

    let ffi_header = src_dir.join("src").join("bindings").join(ffi_header);
    println!("cargo:rerun-if-changed={}", ffi_header.display());
    for dir in &includes {
        println!("cargo:rerun-if-changed={}", dir.display());
    }

    let ffi_rs = out_dir.join(generated);
    let exact_file = src_dir.join("generated").join(generated);
    generate_bindings(&ffi_header, &includes, &ffi_rs, &exact_file, regex);
}

// If you have problems installing ffmpeg, you can download $VCPKG_ROOT/installed from ci
// Linux require link in hwcodec
/*
fn ffmpeg() {
    // ffmpeg
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let static_libs = vec!["avcodec", "avutil", "avformat"];
    static_libs.iter().for_each(|lib| {
        find_package(lib);
    });
    if target_os == "windows" {
        println!("cargo:rustc-link-lib=static=libmfx");
    }

    // os
    let dyn_libs: Vec<&str> = if target_os == "windows" {
        ["User32", "bcrypt", "ole32", "advapi32"].to_vec()
    } else if target_os == "linux" {
        let mut v = ["va", "va-drm", "va-x11", "vdpau", "X11", "stdc++"].to_vec();
        if target_arch == "x86_64" {
            v.push("z");
        }
        v
    } else if target_os == "macos" || target_os == "ios" {
        ["c++", "m"].to_vec()
    } else if target_os == "android" {
        ["z", "m", "android", "atomic"].to_vec()
    } else {
        panic!("unsupported os");
    };
    dyn_libs
        .iter()
        .map(|lib| println!("cargo:rustc-link-lib={}", lib))
        .count();

    if target_os == "macos" || target_os == "ios" {
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
        println!("cargo:rustc-link-lib=framework=CoreVideo");
        println!("cargo:rustc-link-lib=framework=CoreMedia");
        println!("cargo:rustc-link-lib=framework=VideoToolbox");
        println!("cargo:rustc-link-lib=framework=AVFoundation");
    }
}
*/

fn main() {
    // in this crate, these are also valid configurations
    println!("cargo:rustc-check-cfg=cfg(dxgi,quartz,x11)");

    // there is problem with cfg(target_os) in build.rs, so use our workaround
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();

    // note: all link symbol names in x86 (32-bit) are prefixed wth "_".
    // run "rustup show" to show current default toolchain, if it is stable-x86-pc-windows-msvc,
    // please install x64 toolchain by "rustup toolchain install stable-x86_64-pc-windows-msvc",
    // then set x64 to default by "rustup default stable-x86_64-pc-windows-msvc"
    let target = target_build_utils::TargetInfo::new();
    if target.unwrap().target_pointer_width() != "64" {
        // panic!("Only support 64bit system");
    }
    env::remove_var("CARGO_CFG_TARGET_FEATURE");
    env::set_var("CARGO_CFG_TARGET_FEATURE", "crt-static");

    find_package("libyuv");
    gen_vcpkg_package("libvpx", "vpx_ffi.h", "vpx_ffi.rs", "^[vV].*");
    // kq-ios-no-aom-linkage: Codemagic linked a host-built aom_codec.c.o into iOS.
    if target_os != "ios" {
        // aom 3.x exposes cfg_options_t inside aom_codec_enc_cfg; include it
        // without broadening the allowlist enough to trip forward declarations.
        gen_vcpkg_package(
            "aom",
            "aom_ffi.h",
            "aom_ffi.rs",
            "^(aom|AOM|OBU|AV1|cfg_options).*",
        );
    }
    gen_vcpkg_package("libyuv", "yuv_ffi.h", "yuv_ffi.rs", ".*");
    // ffmpeg();

    if target_os == "ios" {
        // nothing
    } else if target_os == "android" {
        println!("cargo:rustc-cfg=android");
    } else if cfg!(windows) {
        // The first choice is Windows because DXGI is amazing.
        println!("cargo:rustc-cfg=dxgi");
    } else if cfg!(target_os = "macos") {
        // Quartz is second because macOS is the (annoying) exception.
        println!("cargo:rustc-cfg=quartz");
    } else if cfg!(unix) {
        // On UNIX we pray that X11 (with XCB) is available.
        println!("cargo:rustc-cfg=x11");
    }
}
