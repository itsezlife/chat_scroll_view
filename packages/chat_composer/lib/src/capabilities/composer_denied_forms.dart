import 'package:flutter/foundation.dart';

/// How the composer draws what the chat's capabilities deny: a dimmed
/// action and a locked text field. The per-platform defaults are
/// [ComposerDeniedForms.forPlatform]; a host passes its own to
/// `ComposerView.deniedForms`.
///
/// The forms only draw. Which actions are denied, the texts and the report
/// of a tap are the controller's (`ComposerController.reportDenied`).
@immutable
final class ComposerDeniedForms {
  /// Denied forms with the given chrome.
  const ComposerDeniedForms({
    required this.dimmedOpacity,
    required this.lockedFieldGlyph,
  }) : assert(
         dimmedOpacity >= 0 && dimmedOpacity <= 1,
         'an opacity is between 0 and 1',
       );

  /// Android: a denied action at half opacity; the locked field's
  /// placeholder starts with a lock.
  static const android = ComposerDeniedForms(
    dimmedOpacity: 0.5,
    lockedFieldGlyph: true,
  );

  /// iOS: a denied action faded to half; the locked field shows the
  /// placeholder alone.
  static const ios = ComposerDeniedForms(
    dimmedOpacity: 0.5,
    lockedFieldGlyph: false,
  );

  /// Desktop and the web: the locked field is a disabled field showing the
  /// text. No button form is traced there, so a denied action takes the
  /// mobile half opacity.
  static const desktop = ComposerDeniedForms(
    dimmedOpacity: 0.5,
    lockedFieldGlyph: false,
  );

  /// The defaults of [platform]; the web takes [desktop].
  static ComposerDeniedForms forPlatform(
    TargetPlatform platform, {
    bool isWeb = false,
  }) {
    if (isWeb) return desktop;
    return switch (platform) {
      TargetPlatform.android || TargetPlatform.fuchsia => android,
      TargetPlatform.iOS => ios,
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => desktop,
    };
  }

  /// Opacity of a denied action's button.
  final double dimmedOpacity;

  /// Whether the locked field's placeholder starts with a lock glyph.
  final bool lockedFieldGlyph;

  @override
  bool operator ==(Object other) =>
      other is ComposerDeniedForms &&
      other.dimmedOpacity == dimmedOpacity &&
      other.lockedFieldGlyph == lockedFieldGlyph;

  @override
  int get hashCode => Object.hash(dimmedOpacity, lockedFieldGlyph);
}
