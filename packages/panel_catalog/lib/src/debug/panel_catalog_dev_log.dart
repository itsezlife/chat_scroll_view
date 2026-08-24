// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// Whether panel-catalog diagnostics are emitted ([PanelCatalogDevLog.event]).
///
/// Override at compile time with `--dart-define=PANEL_CATALOG_DEV_LOG=false`
/// to silence during a debug run. Defaults to [kDebugMode].
const bool kPanelCatalogDevLog =
    bool.fromEnvironment('PANEL_CATALOG_DEV_LOG', defaultValue: kDebugMode);

/// Scoped `dart:developer` logger for panel catalog viewport diagnostics.
///
/// Filter console / DevTools by [name], e.g. `PanelCatalogLayout`,
/// `PanelCatalogBinding`, `PanelCatalogScroll`, `PanelCatalogShell`.
///
/// ```dart
/// final layoutLog = PanelCatalogDevLog('PanelCatalogLayout');
/// layoutLog.event('layout.end', {'extent': DevLogFormat.f(extent)});
/// ```
class PanelCatalogDevLog {
  /// Creates a logger visible under [name] when [kPanelCatalogDevLog] is true.
  PanelCatalogDevLog(this.name, {bool? enabled})
    : enabled = enabled ?? kPanelCatalogDevLog;

  /// Console filter name passed to [dev.log].
  final String name;

  /// When `false`, [event] is a no-op (call sites may stay in place).
  bool enabled;

  /// Monotonic layout-pass counter for this logger instance.
  int layoutFrame = 0;

  /// Monotonic paint-pass counter for this logger instance.
  int paintFrame = 0;

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

  /// Increments and returns [paintFrame].
  int bumpPaintFrame() => ++paintFrame;
}

/// Shared format helpers for [PanelCatalogDevLog] field values.
abstract final class DevLogFormat {
  /// Fixed-one-decimal string for pixel offsets and sizes.
  static String f(double v) => v.toStringAsFixed(1);

  /// Higher-precision string for ratios and progress factors.
  static String ratio(double v, {int decimals = 3}) =>
      v.toStringAsFixed(decimals);

  /// Truncates long glyph strings for logs (avoids multi-codepoint noise).
  static String glyph(String g, {int maxRunes = 4}) {
    final runes = g.runes.take(maxRunes).toList();
    final suffix = g.runes.length > maxRunes ? '…' : '';
    return '${String.fromCharCodes(runes)}$suffix';
  }

  /// Comma-separated asset keys, truncated when [max] exceeded.
  static String assetKeys(Iterable<Object> keys, {int max = 8}) {
    final list = keys.map((k) => k.toString()).toList();
    if (list.length <= max) return list.join(',');
    final head = list.take(max ~/ 2).join(',');
    final tail = list.skip(list.length - max ~/ 2).join(',');
    return '$head,…(${list.length}),…$tail';
  }
}
