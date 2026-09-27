import 'dart:developer' as developer;

import 'package:chat_scroll_view/src/util/constants.dart';
import 'package:meta/meta.dart';

/// Signature of [fine], [config] and [info].
@internal
typedef FieldsLogger =
    void Function(
      LogCategory category,
      Object? message, [
      Map<String, Object?> fields,
    ]);

/// Tracing information. [fields] with `null` values are dropped.
@internal
final FieldsLogger fine = _logFields(500);

/// Static configuration messages
@internal
final FieldsLogger config = _logFields(700);

/// Informational messages
@internal
final FieldsLogger info = _logFields(800);

/// Potential problems
@internal
final void Function(
  LogCategory category,
  Object exception, [
  StackTrace? stackTrace,
  String? reason,
])
warning = _logAll(900);

/// Serious failures
@internal
final void Function(
  LogCategory category,
  Object error, [
  StackTrace stackTrace,
  String? reason,
])
severe = _logAll(1000);

FieldsLogger _logFields(int level) => (category, message, [fields = const {}]) {
  // coverage:ignore-start
  if (!category.enabled) return;
  final body = fields.entries
      .where((e) => e.value != null)
      .map((e) => '${e.key}=${e.value}')
      .join(' ');
  developer.log(
    body.isEmpty ? '$message' : '$message | $body',
    level: level,
    name: 'chat_scroll_view.${category.name}',
  );
  // coverage:ignore-end
};

void Function(
  LogCategory category,
  Object? message, [
  StackTrace? stackTrace,
  String? reason,
])
_logAll(int level) => (category, message, [stackTrace, reason]) {
  // coverage:ignore-start
  if (!category.enabled) return;
  developer.log(
    '${reason ?? message}',
    level: level,
    name: 'chat_scroll_view.${category.name}',
    error: message is Exception || message is Error ? message : null,
    stackTrace: stackTrace,
  );
  // coverage:ignore-end
};

/// Shared format helpers for logger field values.
@internal
abstract final class LogFormat {
  /// Fixed-one-decimal string for pixel offsets and sizes.
  static String f(double v) => v.toStringAsFixed(1);

  /// Higher-precision string for 0..1 ratios and fractional ids in scrollbar
  /// diagnostics where one-decimal rounding hides frame-by-frame drift.
  static String ratio(double v, {int decimals = 3}) =>
      v.toStringAsFixed(decimals);

  /// Comma-separated id list, truncated with a count when [max] is exceeded.
  static String ids(Iterable<int> ids, {int max = 12}) {
    final list = ids.toList()..sort();
    if (list.length <= max) return list.join(',');
    final head = list.take(max ~/ 2).join(',');
    final tail = list.skip(list.length - max ~/ 2).join(',');
    return '$head,…(${list.length}),…$tail';
  }
}
