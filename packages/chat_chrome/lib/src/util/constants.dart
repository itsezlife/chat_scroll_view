import 'dart:async';

import 'package:meta/meta.dart';

/// Chat chrome diagnostics categories, each behind its own switch.
///
/// Enable one category with `--dart-define=chat_chrome.debug.<name>=true`
/// or `zoneValues: {#chat_chrome.debug.<name>: true}`; enable all with
/// `chat_chrome.debug` / `#chat_chrome.debug`.
@internal
enum LogCategory {
  /// IME ↔ keyboard panel arbitration of the bottom inset.
  inset(
    define: bool.fromEnvironment('chat_chrome.debug.inset'),
    zoneKey: #chat_chrome.debug.inset,
  ),

  /// Keyboard panel open / close / handoff animation.
  panel(
    define: bool.fromEnvironment('chat_chrome.debug.panel'),
    zoneKey: #chat_chrome.debug.panel,
  ),

  /// Emoji page shell geometry, leaf taps and catalog rebuilds.
  emoji(
    define: bool.fromEnvironment('chat_chrome.debug.emoji'),
    zoneKey: #chat_chrome.debug.emoji,
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
      Zone.current[#chat_chrome.debug] == true;
}

const bool _$kDebugAll = bool.fromEnvironment('chat_chrome.debug');
