import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class KqIOSDiagnostics {
  static const _channel = MethodChannel('mChannel');
  static final _pending = <Map<String, String>>[];
  static DebugPrintCallback? _originalDebugPrint;
  static Timer? _flushTimer;
  static var _installed = false;
  static var _flushing = false;

  static void install() {
    if (!Platform.isIOS || _installed) return;
    _installed = true;
    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
      record(message ?? '', category: 'debug-print');
    };
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      record(
        '${details.exceptionAsString()}\n${details.stack}',
        level: 'error',
        category: 'flutter-error',
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(
        '$error\n$stack',
        level: 'error',
        category: 'uncaught-async-error',
      );
      return true;
    };
    record('Flutter diagnostics installed', category: 'lifecycle');
  }

  static void record(
    String message, {
    String level = 'debug',
    String category = 'flutter',
  }) {
    if (!Platform.isIOS || message.isEmpty) return;
    _pending.add({
      'level': level,
      'category': category,
      'message': message.length > 8000 ? message.substring(0, 8000) : message,
    });
    if (level == 'error' || _pending.length >= 20) {
      unawaited(flush());
    } else {
      _flushTimer ??= Timer(const Duration(milliseconds: 600), () {
        _flushTimer = null;
        unawaited(flush());
      });
    }
  }

  static Future<void> flush() async {
    if (!Platform.isIOS || _flushing || _pending.isEmpty) return;
    _flushing = true;
    final entries = List<Map<String, String>>.from(_pending);
    _pending.clear();
    try {
      await _channel.invokeMethod<bool>('append_ios_diagnostic_logs', entries);
    } catch (_) {
      _pending.insertAll(0, entries.take(20));
    } finally {
      _flushing = false;
    }
  }
}
