import 'package:chat_composer/src/capabilities/composer_slow_mode_forms.dart';
import 'package:flutter/foundation.dart';

/// How the composer draws what the chat's capabilities deny: a dimmed
/// action, a locked text field and slow mode ([slowMode]). The per-platform defaults are
/// [ComposerDeniedForms.forPlatform]; a host passes its own to
/// `ComposerView.deniedForms`.
///
/// The forms only draw. Which actions are denied, the texts and the report
/// of a tap are the controller's (`ComposerController.reportDenied`), and
/// so are slow mode's countdown and refusal.
@immutable
final class ComposerDeniedForms {
  /// Denied forms with the given chrome.
  const ComposerDeniedForms({
    required this.lockedFieldGlyph,
    required this.slowMode,
    this.textDeniedDimsEmoji = false,
    this.dimmedOpacity = defaultDimmedOpacity,
  }) : assert(
         dimmedOpacity >= 0 && dimmedOpacity <= 1,
         'an opacity is between 0 and 1',
       );

  /// The opacity of a denied action on every platform: half. One value, as
  /// no platform draws it otherwise; a host passes its own to a form.
  static const double defaultDimmedOpacity = 0.5;

  /// Android: the locked field's placeholder starts with a lock, and plain
  /// text denied dims the emoji panel's toggle too.
  static const android = ComposerDeniedForms(
    lockedFieldGlyph: true,
    textDeniedDimsEmoji: true,
    slowMode: ComposerSlowModeForms.android,
  );

  /// iOS: the locked field shows the placeholder alone.
  static const ios = ComposerDeniedForms(
    lockedFieldGlyph: false,
    slowMode: ComposerSlowModeForms.ios,
  );

  /// Desktop: the locked field is a disabled field showing the text.
  static const desktop = ComposerDeniedForms(
    lockedFieldGlyph: false,
    slowMode: ComposerSlowModeForms.desktop,
  );

  /// The defaults of [platform].
  ///
  /// The web is not desktop: until the chrome reads the window's width
  /// class and input class, a web composer takes the mobile form of the
  /// browser's family, [ios] for an iOS browser and [android] for any
  /// other. A host that knows its width and input passes its own forms.
  static ComposerDeniedForms forPlatform(
    TargetPlatform platform, {
    bool isWeb = false,
  }) {
    if (isWeb) return platform == TargetPlatform.iOS ? ios : android;
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

  /// Whether plain text denied dims the host's emoji panel toggle too.
  ///
  /// The composer knows no emoji toggle: a host reads this when it builds
  /// its toggle's descriptor and, when true, gives it
  /// `capability: CapabilityAction.sendText`, so the toggle takes the
  /// dimmed form with the field.
  final bool textDeniedDimsEmoji;

  /// How slow mode is drawn: the countdown, the held send, the held
  /// actions. Its [ComposerSlowModeForms.refresh] is the period the
  /// controller redraws the countdown at.
  final ComposerSlowModeForms slowMode;

  @override
  bool operator ==(Object other) =>
      other is ComposerDeniedForms &&
      other.dimmedOpacity == dimmedOpacity &&
      other.lockedFieldGlyph == lockedFieldGlyph &&
      other.textDeniedDimsEmoji == textDeniedDimsEmoji &&
      other.slowMode == slowMode;

  @override
  int get hashCode => Object.hash(
    dimmedOpacity,
    lockedFieldGlyph,
    textDeniedDimsEmoji,
    slowMode,
  );
}
