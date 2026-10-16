import 'dart:ui' show Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colours of tappable action chrome: composer action icons, the send
/// button and the floating type pill.
///
/// Derived from a [ChromePalette] by [ActionTokens.fromPalette]; a host
/// overrides single fields with [copyWith] or supplies the whole group to a
/// `ChromeThemeScope`.
@immutable
final class ActionTokens {
  /// An action token group with every colour given.
  const ActionTokens({
    required this.icon,
    required this.iconHover,
    required this.send,
    required this.onSend,
    required this.backspace,
    required this.floatingFill,
    required this.floatingSelectedFill,
    required this.floatingLabel,
    required this.floatingLabelMuted,
  });

  /// The default mapping of [palette] roles onto action fields.
  factory ActionTokens.fromPalette(ChromePalette palette) => ActionTokens(
    icon: palette.iconIdle,
    iconHover: palette.iconActive,
    send: palette.accent,
    onSend: palette.onAccent,
    backspace: palette.iconIdle,
    floatingFill: palette.surfaceRaised,
    floatingSelectedFill: palette.surfaceSelected,
    floatingLabel: palette.onSurface,
    floatingLabelMuted: palette.onSurfaceMuted,
  );

  /// Composer action icons.
  final Color icon;

  /// A composer action icon while a mouse is over its button: the reference
  /// client swaps the icon's colour and draws nothing else.
  final Color iconHover;

  /// Send button fill.
  final Color send;

  /// Glyph drawn on [send].
  final Color onSend;

  /// Backspace icon.
  final Color backspace;

  /// Floating pill and button fill (solid, opaque).
  final Color floatingFill;

  /// Selected segment capsule inside the floating pill (solid).
  final Color floatingSelectedFill;

  /// Active label or icon on floating chrome.
  final Color floatingLabel;

  /// Idle label on floating chrome.
  final Color floatingLabelMuted;

  /// A copy with the named fields replaced.
  ActionTokens copyWith({
    Color? icon,
    Color? iconHover,
    Color? send,
    Color? onSend,
    Color? backspace,
    Color? floatingFill,
    Color? floatingSelectedFill,
    Color? floatingLabel,
    Color? floatingLabelMuted,
  }) => ActionTokens(
    icon: icon ?? this.icon,
    iconHover: iconHover ?? this.iconHover,
    send: send ?? this.send,
    onSend: onSend ?? this.onSend,
    backspace: backspace ?? this.backspace,
    floatingFill: floatingFill ?? this.floatingFill,
    floatingSelectedFill: floatingSelectedFill ?? this.floatingSelectedFill,
    floatingLabel: floatingLabel ?? this.floatingLabel,
    floatingLabelMuted: floatingLabelMuted ?? this.floatingLabelMuted,
  );

  /// Interpolates every field between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static ActionTokens lerp(ActionTokens a, ActionTokens b, double t) =>
      ActionTokens(
        icon: Color.lerp(a.icon, b.icon, t)!,
        iconHover: Color.lerp(a.iconHover, b.iconHover, t)!,
        send: Color.lerp(a.send, b.send, t)!,
        onSend: Color.lerp(a.onSend, b.onSend, t)!,
        backspace: Color.lerp(a.backspace, b.backspace, t)!,
        floatingFill: Color.lerp(a.floatingFill, b.floatingFill, t)!,
        floatingSelectedFill: Color.lerp(
          a.floatingSelectedFill,
          b.floatingSelectedFill,
          t,
        )!,
        floatingLabel: Color.lerp(a.floatingLabel, b.floatingLabel, t)!,
        floatingLabelMuted: Color.lerp(
          a.floatingLabelMuted,
          b.floatingLabelMuted,
          t,
        )!,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ActionTokens &&
          icon == other.icon &&
          iconHover == other.iconHover &&
          send == other.send &&
          onSend == other.onSend &&
          backspace == other.backspace &&
          floatingFill == other.floatingFill &&
          floatingSelectedFill == other.floatingSelectedFill &&
          floatingLabel == other.floatingLabel &&
          floatingLabelMuted == other.floatingLabelMuted;

  @override
  int get hashCode => Object.hash(
    icon,
    iconHover,
    send,
    onSend,
    backspace,
    floatingFill,
    floatingSelectedFill,
    floatingLabel,
    floatingLabelMuted,
  );

  @override
  String toString() => 'ActionTokens(send: $send)';
}
