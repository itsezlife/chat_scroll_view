import 'dart:async';

import 'package:meta/meta.dart';

/// Chat scroll diagnostics categories, each behind its own switch.
///
/// Enable one category with `--dart-define=chat_scroll_view.debug.<name>=true`
/// or `zoneValues: {#chat_scroll_view.debug.<name>: true}`; enable all with
/// `chat_scroll_view.debug` / `#chat_scroll_view.debug`.
@internal
enum LogCategory {
  /// `animateTo`, stitch and close-path travel.
  animate(
    define: bool.fromEnvironment('chat_scroll_view.debug.animate'),
    zoneKey: #chat_scroll_view.debug.animate,
  ),

  /// Chunk loads and anchor persistence across layout.
  anchor(
    define: bool.fromEnvironment('chat_scroll_view.debug.anchor'),
    zoneKey: #chat_scroll_view.debug.anchor,
  ),

  /// Chunk fetch scheduling (poll, jump fetch, eviction).
  fetch(
    define: bool.fromEnvironment('chat_scroll_view.debug.fetch'),
    zoneKey: #chat_scroll_view.debug.fetch,
  ),

  /// Paint-time edge stretch.
  overscroll(
    define: bool.fromEnvironment('chat_scroll_view.debug.overscroll'),
    zoneKey: #chat_scroll_view.debug.overscroll,
  ),

  /// Scrollbar thumb and id-linear progress.
  scrollbar(
    define: bool.fromEnvironment('chat_scroll_view.debug.scrollbar'),
    zoneKey: #chat_scroll_view.debug.scrollbar,
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
      Zone.current[#chat_scroll_view.debug] == true;
}

const bool _$kDebugAll = bool.fromEnvironment('chat_scroll_view.debug');
