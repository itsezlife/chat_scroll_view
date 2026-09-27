import 'dart:async';

import 'package:meta/meta.dart';

/// Panel catalog diagnostics categories, each behind its own switch.
///
/// Enable one category with `--dart-define=panel_catalog.debug.<name>=true`
/// or `zoneValues: {#panel_catalog.debug.<name>: true}`; enable all with
/// `panel_catalog.debug` / `#panel_catalog.debug`.
@internal
enum LogCategory {
  /// Slot projection, content extent and paint window.
  layout(
    define: bool.fromEnvironment('panel_catalog.debug.layout'),
    zoneKey: #panel_catalog.debug.layout,
  ),

  /// Leaf binding window sync and readiness counts.
  binding(
    define: bool.fromEnvironment('panel_catalog.debug.binding'),
    zoneKey: #panel_catalog.debug.binding,
  ),

  /// Offset changes and section jumps.
  scroll(
    define: bool.fromEnvironment('panel_catalog.debug.scroll'),
    zoneKey: #panel_catalog.debug.scroll,
  ),

  /// Placeholder vs content paint counts.
  paint(
    define: bool.fromEnvironment('panel_catalog.debug.paint'),
    zoneKey: #panel_catalog.debug.paint,
  );

  const LogCategory({required bool define, required Symbol zoneKey})
    : _define = define,
      _zoneKey = zoneKey;

  final bool _define;
  final Symbol _zoneKey;

  /// Whether this category logs in the current [Zone].
  bool get enabled =>
      _define ||
      _$kDebugAll ||
      Zone.current[_zoneKey] == true ||
      Zone.current[#panel_catalog.debug] == true;
}

const bool _$kDebugAll = bool.fromEnvironment('panel_catalog.debug');
