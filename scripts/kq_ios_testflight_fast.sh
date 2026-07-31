#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/kq_ios_testflight_fast.sh --mode rust [--build-number N] [--no-upload]
  scripts/kq_ios_testflight_fast.sh --mode dart [--build-number N] [--no-upload]
  scripts/kq_ios_testflight_fast.sh --mode archive-only [--build-number N] [--no-upload]
  scripts/kq_ios_testflight_fast.sh --mode upload-existing --ipa /path/to/app.ipa

Modes:
  rust             Rebuild the iOS Rust static library, archive, export, upload.
  dart             Archive, export, upload without rebuilding Rust.
  archive-only     Reuse existing build intermediates, archive, export, upload.
  upload-existing  Reuse an existing IPA and upload only.

Defaults are intentionally incremental. This script does not run flutter clean,
does not reinstall pods unless Pods is missing, and uses low build concurrency.
EOF
}

log() {
  printf '[kq-ios] %s\n' "$*"
}

fail() {
  printf '[kq-ios] ERROR: %s\n' "$*" >&2
  exit 1
}

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_dir="$repo_dir/flutter"
ios_dir="$flutter_dir/ios"
release_config_validator="$repo_dir/scripts/prepare_ios_release_config.py"

mode="rust"
build_name="${FLUTTER_BUILD_NAME:-1.4.6}"
build_number="${FLUTTER_BUILD_NUMBER:-}"
ipa_path=""
upload=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --build-name)
      build_name="${2:-}"
      shift 2
      ;;
    --build-number)
      build_number="${2:-}"
      shift 2
      ;;
    --ipa)
      ipa_path="${2:-}"
      shift 2
      ;;
    --no-upload)
      upload=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

case "$mode" in
  rust|dart|archive-only|upload-existing) ;;
  *) fail "Unsupported --mode $mode" ;;
esac

flutter_bin="${FLUTTER_BIN:-/Users/m4_txx/.local/flutter/3.44.5/bin/flutter}"
vcpkg_root="${KQ_IOS_VCPKG_ROOT:-$repo_dir/build/vcpkg-ios-device-root}"
signing_dir="${KQ_IOS_SIGNING_DIR:-/Users/m4_txx/Downloads/RemoteLink_Distribution_Signing_Verified_20260725-140641}"
export_options="${KQ_IOS_EXPORT_OPTIONS:-$ios_dir/ExportOptions-AppStore.plist}"
api_key_id="${APP_STORE_CONNECT_API_KEY_ID:-HDR5LN3828}"
api_issuer_id="${APP_STORE_CONNECT_ISSUER_ID:-7f07ef9b-b160-4e26-b7d6-ecc74ab4a5b5}"
user_home="${KQ_USER_HOME:-/Users/m4_txx}"
team_id="${KQ_IOS_TEAM_ID:-G4C3ADW2F4}"
xcode_jobs="${XCODE_JOBS:-2}"
cargo_jobs="${CARGO_BUILD_JOBS:-2}"
target="aarch64-apple-ios"
rust_features="${KQ_IOS_CARGO_FEATURES:-flutter}"
ios_deployment_target="${KQ_IOS_DEPLOYMENT_TARGET:-13.0}"
ios_rust_context_file="$repo_dir/target/.kq-ios-rust-context-$target"

export PATH="$(dirname "$flutter_bin"):$PATH"
export VCPKG_ROOT="$vcpkg_root"
export CARGO_BUILD_JOBS="$cargo_jobs"
export VCPKG_TRIPLET="${VCPKG_TRIPLET:-arm64-ios}"
default_iap_products='{"1":"com.kunqiong.remotelink.member.monthly","2":"com.kunqiong.remotelink.member.quarterly","3":"com.kunqiong.remotelink.member.halfyear","4":"com.kunqiong.remotelink.member.yearly","5":"com.kunqiong.remotelink.member.lifetime"}'
export KQ_IOS_IAP_PRODUCTS="${KQ_IOS_IAP_PRODUCTS:-$default_iap_products}"

p12_file="$signing_dir/RemoteLink-Apple-Distribution.p12"
p12_password_file="$signing_dir/CERTIFICATE_PASSWORD.txt"
main_profile="$signing_dir/RemoteLink-Main-AppStore.mobileprovision"
broadcast_profile="$signing_dir/RemoteLink-Broadcast-AppStore.mobileprovision"
api_key_file="$user_home/.appstoreconnect/private_keys/AuthKey_${api_key_id}.p8"

require_file() {
  [[ -f "$1" ]] || fail "Missing required file: $1"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required tool: $1"
}

guard_existing_heavy_processes() {
  if [[ "${KQ_ALLOW_EXISTING_PROCESSES:-0}" == "1" ]]; then
    return
  fi
  local matches
  matches="$(ps -axo pid,pcpu,pmem,comm,args \
    | grep -E '(flutter|dart|xcodebuild|cargo|rustc|altool|Transporter|log stream)' \
    | grep -v grep \
    | grep -v 'kq_ios_testflight_fast.sh' || true)"
  if [[ -n "$matches" ]]; then
    printf '%s\n' "$matches" >&2
    fail "Build/upload process already running. Stop it first or set KQ_ALLOW_EXISTING_PROCESSES=1."
  fi
}

latest_local_build_number() {
  local latest
  latest="$(find "$ios_dir/build/ios" -maxdepth 1 -type d -name 'ipa-[0-9]*-*' 2>/dev/null \
    | sed -E 's/^.*ipa-([0-9]+)-.*$/\1/' \
    | sort -n \
    | tail -n 1)"
  if [[ -n "$latest" ]]; then
    printf '%s\n' "$((latest + 1))"
  else
    printf '%s\n' "3008970547811"
  fi
}

latest_local_ipa() {
  find "$ios_dir/build/ios" -maxdepth 2 -type f -name '*.ipa' 2>/dev/null \
    | sort \
    | tail -n 1
}

ensure_build_number() {
  if [[ -z "$build_number" ]]; then
    build_number="$(latest_local_build_number)"
  fi
}

ensure_flutter_pub_get() {
  if [[ ! -f "$flutter_dir/.dart_tool/package_config.json" ]]; then
    log "Running flutter pub get because package_config.json is missing."
    (cd "$flutter_dir" && "$flutter_bin" pub get)
  else
    log "Reusing Flutter package config."
  fi
}

prepare_flutter_build_config() {
  log "Refreshing Flutter iOS build settings for $build_name ($build_number) without compiling."
  python3 "$release_config_validator"
  (
    cd "$flutter_dir"
    "$flutter_bin" build ios \
      --config-only \
      --release \
      --build-name "$build_name" \
      --build-number "$build_number" \
      --dart-define=KQ_PRIVACY_POLICY_URL="$KQ_PRIVACY_POLICY_URL" \
      --dart-define=KQ_ACCOUNT_DELETE_URL="$KQ_ACCOUNT_DELETE_URL" \
      --dart-define=KQ_IOS_IAP_PRODUCTS="$KQ_IOS_IAP_PRODUCTS" \
      --dart-define=KQ_IOS_IAP_VERIFY_URL="$KQ_IOS_IAP_VERIFY_URL" \
      --dart-define=KQ_IOS_INTERNAL_DIRECT_PAYMENT=false \
      --no-codesign \
      --no-pub
  )
  grep -Fx "FLUTTER_BUILD_NAME=$build_name" "$ios_dir/Flutter/Generated.xcconfig" >/dev/null \
    || fail "Flutter build name was not written to Generated.xcconfig"
  grep -Fx "FLUTTER_BUILD_NUMBER=$build_number" "$ios_dir/Flutter/Generated.xcconfig" >/dev/null \
    || fail "Flutter build number was not written to Generated.xcconfig"
}

ensure_pods() {
  if [[ ! -d "$ios_dir/Pods" ]]; then
    log "Running pod install because Pods is missing."
    (cd "$ios_dir" && pod install)
  else
    log "Reusing existing CocoaPods install."
  fi
}

verify_archive_build_number() {
  local archive_path="$1"
  local app_info="$archive_path/Products/Applications/Runner.app/Info.plist"
  local extension_info="$archive_path/Products/Applications/Runner.app/PlugIns/KQScreenBroadcast.appex/Info.plist"
  local app_build extension_build
  app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_info")"
  extension_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$extension_info")"
  [[ "$app_build" == "$build_number" && "$extension_build" == "$build_number" ]] \
    || fail "Archive build numbers are inconsistent: app=$app_build extension=$extension_build expected=$build_number"
}

ios_rust_context() {
  printf 'target=%s\n' "$target"
  printf 'features=%s\n' "$rust_features"
  printf 'deployment_target=%s\n' "$ios_deployment_target"
  printf 'iphoneos_sdk=%s\n' "$(xcrun --sdk iphoneos --show-sdk-version)"
  printf 'vcpkg_root=%s\n' "$vcpkg_root"
  printf 'rustc=%s\n' "$(rustc -Vv | tr '\n' ' ')"
}

prepare_ios_rust_cache() {
  local expected_context actual_context=""
  expected_context="$(ios_rust_context)"
  if [[ -f "$ios_rust_context_file" ]]; then
    actual_context="$(<"$ios_rust_context_file")"
  fi

  if [[ "$actual_context" != "$expected_context" ]]; then
    log "Refreshing only the iOS Rust target cache because its toolchain context changed."
    (
      cd "$repo_dir"
      cargo clean --target "$target"
    )
  fi
}

record_ios_rust_context() {
  mkdir -p "$(dirname "$ios_rust_context_file")"
  ios_rust_context > "$ios_rust_context_file"
}

verify_ios_vcpkg_libraries() {
  log "Verifying that vcpkg libraries are built for iOS devices."
  VCPKG_ROOT="$vcpkg_root" \
    VCPKG_TRIPLET="$VCPKG_TRIPLET" \
    bash "$repo_dir/scripts/ci/verify-ios-vcpkg-libraries.sh"
}

build_rust_ios() {
  log "Building Rust iOS static library with features $rust_features and -j $cargo_jobs."
  (
    cd "$repo_dir"
    export IPHONEOS_DEPLOYMENT_TARGET="$ios_deployment_target"
    export CMAKE_OSX_DEPLOYMENT_TARGET="$ios_deployment_target"
    export CFLAGS_aarch64_apple_ios="${CFLAGS_aarch64_apple_ios:+$CFLAGS_aarch64_apple_ios }-miphoneos-version-min=$ios_deployment_target"
    export CXXFLAGS_aarch64_apple_ios="${CXXFLAGS_aarch64_apple_ios:+$CXXFLAGS_aarch64_apple_ios }-miphoneos-version-min=$ios_deployment_target"
    verify_ios_vcpkg_libraries
    prepare_ios_rust_cache
    cargo build --features "$rust_features" --release --target "$target" --lib -j "$cargo_jobs"
    bash "$repo_dir/scripts/ci/prepare-ios-rust-static-libs.sh" "target/$target/release"
    record_ios_rust_context
  )
}

install_profile() {
  local profile="$1"
  local tmp_plist="$work_dir/profile.plist"
  local uuid
  security cms -D -i "$profile" > "$tmp_plist"
  uuid="$(/usr/libexec/PlistBuddy -c 'Print UUID' "$tmp_plist")"
  mkdir -p "$user_home/Library/MobileDevice/Provisioning Profiles"
  cp "$profile" "$user_home/Library/MobileDevice/Provisioning Profiles/$uuid.mobileprovision"
  log "Installed provisioning profile $uuid."
}

read_p12_password() {
  perl -0pe 's/\r?\n\z//' "$p12_password_file"
}

setup_signing_keychain() {
  keychain="$work_dir/kq-ios-signing.keychain-db"
  keychain_password="$(uuidgen)-$(uuidgen)"
  original_keychains="$(security list-keychains -d user | sed 's/[[:space:]\"]//g')"

  security create-keychain -p "$keychain_password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"

  local p12_password
  p12_password="$(read_p12_password)"
  security import "$p12_file" \
    -k "$keychain" \
    -P "$p12_password" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$keychain_password" \
    "$keychain" >/dev/null

  # Put the temporary keychain first so framework signing does not hit
  # errSecInternalComponent.
  # shellcheck disable=SC2086
  security list-keychains -d user -s "$keychain" $original_keychains
  log "Temporary signing keychain ready."
}

restore_keychains() {
  if [[ -n "${original_keychains:-}" ]]; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s $original_keychains >/dev/null 2>&1 || true
  fi
}

cleanup() {
  local status=$?
  restore_keychains
  if [[ -n "${keychain:-}" && -f "$keychain" ]]; then
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
  fi
  if [[ -n "${work_dir:-}" && -d "$work_dir" ]]; then
    rm -rf "$work_dir"
  fi
  return "$status"
}

archive_and_export() {
  require_file "$export_options"
  require_file "$p12_file"
  require_file "$p12_password_file"
  require_file "$main_profile"
  require_file "$broadcast_profile"

  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/kq-ios-testflight.XXXXXX")"
  keychain=""
  original_keychains=""
  trap cleanup EXIT

  install_profile "$main_profile"
  install_profile "$broadcast_profile"
  setup_signing_keychain

  local timestamp archive_path export_path
  timestamp="$(date +%Y%m%d%H%M%S)"
  archive_path="$ios_dir/build/ios/archive/Runner-${build_number}-${timestamp}.xcarchive"
  export_path="$ios_dir/build/ios/ipa-${build_number}-${timestamp}"
  mkdir -p "$(dirname "$archive_path")" "$export_path"

  log "Archiving build $build_name ($build_number)."
  xcodebuild archive \
    -quiet \
    -workspace "$ios_dir/Runner.xcworkspace" \
    -scheme Runner \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_STYLE=Manual \
    MARKETING_VERSION="$build_name" \
    CURRENT_PROJECT_VERSION="$build_number" \
    FLUTTER_BUILD_NAME="$build_name" \
    FLUTTER_BUILD_NUMBER="$build_number" \
    OTHER_CODE_SIGN_FLAGS="--keychain $keychain" \
    -jobs "$xcode_jobs"

  verify_archive_build_number "$archive_path"

  log "Exporting IPA."
  xcodebuild -exportArchive \
    -quiet \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$export_options" \
    OTHER_CODE_SIGN_FLAGS="--keychain $keychain" \
    -jobs "$xcode_jobs"

  ipa_path="$(find "$export_path" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
  [[ -n "$ipa_path" && -f "$ipa_path" ]] || fail "Export succeeded but no IPA was found in $export_path"
  log "IPA: $ipa_path"
}

upload_ipa() {
  require_file "$1"
  require_file "$api_key_file"
  log "Uploading IPA to TestFlight."
  xcrun altool --upload-package "$1" \
    --api-key "$api_key_id" \
    --api-issuer "$api_issuer_id" \
    --output-format json
}

require_tool xcodebuild
require_tool xcrun
require_tool security
require_tool perl
require_tool uuidgen
require_tool cargo
require_tool rustc
require_tool python3
require_file "$flutter_bin"
require_file "$release_config_validator"
guard_existing_heavy_processes

if [[ "$mode" == "upload-existing" ]]; then
  if [[ -z "$ipa_path" ]]; then
    ipa_path="$(latest_local_ipa)"
  fi
  [[ -n "$ipa_path" ]] || fail "No IPA found. Pass --ipa explicitly."
  upload_ipa "$ipa_path"
  log "Done."
  exit 0
fi

ensure_build_number
log "Mode: $mode"
log "Build: $build_name ($build_number)"

case "$mode" in
  rust)
    ensure_flutter_pub_get
    ensure_pods
    build_rust_ios
    prepare_flutter_build_config
    archive_and_export
    ;;
  dart)
    ensure_flutter_pub_get
    ensure_pods
    prepare_flutter_build_config
    archive_and_export
    ;;
  archive-only)
    ensure_flutter_pub_get
    ensure_pods
    prepare_flutter_build_config
    archive_and_export
    ;;
esac

if [[ "$upload" == "1" ]]; then
  upload_ipa "$ipa_path"
else
  log "Skipping upload because --no-upload was set."
fi

log "Done."
