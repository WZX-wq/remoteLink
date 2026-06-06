import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ListSearchActionListener extends StatelessWidget {
  final FocusNode node;
  final TimeoutStringBuffer buffer;
  final Widget child;
  final Function(String) onNext;
  final Function(String) onSearch;
  final bool Function()? shouldHandleKeyEvent;

  const ListSearchActionListener(
      {super.key,
      required this.node,
      required this.buffer,
      required this.child,
      required this.onNext,
      required this.onSearch,
      this.shouldHandleKeyEvent});

  @mustCallSuper
  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
        autofocus: true,
        onKeyEvent: (kv) {
          if (shouldHandleKeyEvent != null && !shouldHandleKeyEvent!()) {
            return;
          }
          if (kv is! KeyDownEvent) {
            return;
          }
          final ch = kv.character;
          if (ch == null ||
              ch.isEmpty ||
              ch.runes.any((rune) => rune < 0x20 || rune == 0x7F)) {
            return;
          }
          final action = buffer.input(ch);
          switch (action) {
            case ListSearchAction.search:
              onSearch(buffer.buffer);
              break;
            case ListSearchAction.next:
              onNext(buffer.buffer);
              break;
          }
        },
        focusNode: node,
        child: child);
  }
}

enum ListSearchAction { search, next }

class TimeoutStringBuffer {
  var _buffer = "";
  late DateTime _duration;

  static int timeoutMilliSec = 1500;

  String get buffer => _buffer;

  void clear() {
    _buffer = "";
    _duration = DateTime.now();
  }

  TimeoutStringBuffer() {
    _duration = DateTime.now();
  }

  ListSearchAction input(String ch) {
    ch = ch.toLowerCase();
    final curr = DateTime.now();
    try {
      if (curr.difference(_duration).inMilliseconds > timeoutMilliSec) {
        _buffer = ch;
        return ListSearchAction.search;
      } else {
        if (ch == _buffer) {
          return ListSearchAction.next;
        } else {
          _buffer += ch;
          return ListSearchAction.search;
        }
      }
    } finally {
      _duration = curr;
    }
  }
}
