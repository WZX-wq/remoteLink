import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('Android native startup initializes NDK context from application context',
      () {
    final native =
        File('../libs/scrap/src/android/ffi.rs').readAsStringSync();
    final application = File(
            'android/app/src/main/kotlin/com/carriez/flutter_hbb/MainApplication.kt')
        .readAsStringSync();
    final onLoad = _section(
      native,
      'pub extern "C" fn JNI_OnLoad',
      '#[no_mangle]\npub extern "system" fn Java_ffi_FFI_onAppStart',
    );
    final onAppStart = _section(
      native,
      'pub extern "system" fn Java_ffi_FFI_onAppStart',
      '\n}',
    );

    expect(onLoad, isNot(contains('init_ndk_context(')));
    expect(onAppStart, contains('init_ndk_context(java_vm, context_jobject);'));
    expect(
      onAppStart.indexOf('init_ndk_context(java_vm, context_jobject);'),
      lessThan(onAppStart.indexOf('try_init_rustls_platform_verifier')),
    );
    expect(application, contains('FFI.onAppStart(applicationContext)'));
  });

  test('Android package exposes only the ABI supported by librustdesk', () {
    final buildGradle = File('android/app/build.gradle').readAsStringSync();
    final defaultConfig = _section(
      buildGradle,
      '    defaultConfig {',
      '    signingConfigs {',
    );

    expect(defaultConfig, contains('abiFilters "arm64-v8a"'));
    expect(buildGradle, contains('"lib/armeabi-v7a/**"'));
    expect(buildGradle, contains('"lib/x86/**"'));
    expect(buildGradle, contains('"lib/x86_64/**"'));
  });

  test('Android startup avoids the path provider JNI bootstrap', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lock = File('pubspec.lock').readAsStringSync();

    expect(pubspec, contains('path_provider_android: 2.2.23'));
    expect(lock, contains('  path_provider_android:'));
    expect(lock, contains('    version: "2.2.23"'));
    expect(lock, isNot(contains('\n  jni:\n')));
    expect(lock, isNot(contains('\n  jni_flutter:\n')));
  });
}
