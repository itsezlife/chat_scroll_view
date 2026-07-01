// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// Scoped `dart:developer` logger for chat scroll diagnostics.
///
/// Create one instance per concern (`ChatScrollFetchAnchor`, …) and filter
/// console output by [name].
///
/// ```dart
/// final fetchLog = ChatScrollDevLog('ChatScrollFetchAnchor', enabled: true);
/// fetchLog.event('layout.begin', {'anchor': 42});
/// ```
class ChatScrollDevLog {
  /// Creates a logger visible in the console under [name].
  ChatScrollDevLog(this.name, {this.enabled = false});

  /// Console filter name passed to `dart:developer` [dev.log].
  final String name;

  /// When `false`, [event] is a no-op (call sites may stay in place).
  bool enabled;

  /// Monotonic layout-pass counter for this logger instance.
  int layoutFrame = 0;

  /// Monotonic ticker-frame counter for this logger instance.
  int tickFrame = 0;

  /// Emits one line tagged with [tag] and formatted [fields].
  void event(String tag, Map<String, Object?> fields) {
    if (!kDebugMode || !enabled) return;
    final body = fields.entries
        .where((e) => e.value != null)
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    dev.log('$tag | $body', name: name);
  }

  /// Increments and returns [layoutFrame].
  int bumpLayoutFrame() => ++layoutFrame;

  /// Increments and returns [tickFrame].
  int bumpTickFrame() => ++tickFrame;
}

/// Shared format helpers for [ChatScrollDevLog] field values.
abstract final class DevLogFormat {
  /// Fixed-one-decimal string for pixel offsets and sizes.
  static String f(double v) => v.toStringAsFixed(1);

  /// Comma-separated id list, truncated with a count when [max] is exceeded.
  static String ids(Iterable<int> ids, {int max = 12}) {
    final list = ids.toList()..sort();
    if (list.length <= max) return list.join(',');
    final head = list.take(max ~/ 2).join(',');
    final tail = list.skip(list.length - max ~/ 2).join(',');
    return '$head,…(${list.length}),…$tail';
  }
}
