#!/usr/bin/env bash
set -euo pipefail

export KQ_IOS_IAP_PRODUCTS="${KQ_IOS_IAP_PRODUCTS:-{\"1\":\"com.kunqiong.remotelink.member.monthly\",\"2\":\"com.kunqiong.remotelink.member.quarterly\",\"3\":\"com.kunqiong.remotelink.member.halfyear\",\"4\":\"com.kunqiong.remotelink.member.yearly\",\"5\":\"com.kunqiong.remotelink.member.lifetime\"}}"

FLUTTER_ARGS=()
for define_name in \
  KQ_PRIVACY_POLICY_URL \
  KQ_ACCOUNT_DELETE_URL \
  KQ_IOS_IAP_PRODUCTS \
  KQ_IOS_IAP_VERIFY_URL \
  KQ_IOS_IAP_LOCAL_STOREKIT_TEST \
  KQ_IOS_INTERNAL_DIRECT_PAYMENT
do
  if [ -n "${!define_name:-}" ]; then
    FLUTTER_ARGS+=(--dart-define="$define_name=${!define_name}")
  fi
done

cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid
flutter pub get
~/.cargo/bin/flutter_rust_bridge_codegen --rust-input ../src/flutter_ffi.rs --dart-output ./lib/generated_bridge.dart --c-output ./macos/Runner/bridge_generated.h
# call `flutter clean` if cargo build fails
# export LLVM_HOME=/Library/Developer/CommandLineTools/usr/
cargo build --features flutter
flutter run "${FLUTTER_ARGS[@]}" "$@"
