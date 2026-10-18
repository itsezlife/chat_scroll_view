import 'package:flutter/foundation.dart';

/// Which edge of a secondary click opens the pointer menu.
enum ComposerMenuOpensOn {
  /// The moment the button goes down.
  press,

  /// The moment it comes up.
  release,
}

/// How the composer's field presents its menu, chosen like the selection
/// policies: one pure-Dart strategy per input family.
///
/// - [ComposerMenuPolicy$Mobile]: the floating toolbar over the selection
///   (`ComposerSelectionMenu`) for every gesture.
/// - [ComposerMenuPolicy$Desktop]: a secondary click opens the **pointer
///   menu**, the reference desktop client's context menu of its message field,
///   at the pointer; the toolbar stays for a touch long-press on a touch
///   screen.
sealed class ComposerMenuPolicy {
  const ComposerMenuPolicy();

  /// The floating toolbar everywhere.
  const factory ComposerMenuPolicy.mobile() = ComposerMenuPolicy$Mobile;

  /// The pointer menu for a secondary click, with the hints and the click edge
  /// of [platform].
  const factory ComposerMenuPolicy.desktop({TargetPlatform platform}) =
      ComposerMenuPolicy$Desktop;

  /// The policy for [platform]; the web counts as desktop.
  factory ComposerMenuPolicy.forPlatform(
    TargetPlatform platform, {
    bool isWeb = false,
  }) {
    if (isWeb) return ComposerMenuPolicy.desktop(platform: platform);
    return switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => const ComposerMenuPolicy.mobile(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => ComposerMenuPolicy.desktop(platform: platform),
    };
  }

  /// Whether a secondary click opens the pointer menu.
  bool get usesPointerMenu;
}

/// Touch-first: no pointer menu; see [ComposerMenuPolicy.mobile].
final class ComposerMenuPolicy$Mobile extends ComposerMenuPolicy {
  /// Creates the policy.
  const ComposerMenuPolicy$Mobile();

  @override
  bool get usesPointerMenu => false;
}

/// Pointer-first: see [ComposerMenuPolicy.desktop].
@immutable
final class ComposerMenuPolicy$Desktop extends ComposerMenuPolicy {
  /// Creates the policy for [platform].
  const ComposerMenuPolicy$Desktop({this.platform = TargetPlatform.windows});

  /// The platforms whose toolkit opens a context menu on the press of the
  /// secondary button (the others open it on the release).
  ///
  /// **UNVERIFIED.** The reference client's toolkit decides this per operating
  /// system, inside its platform layer, which no source available to the port
  /// shows; the table is what that layer is known to do (a press on macOS and
  /// Linux, a release on Windows). This one set is the only place the guess is
  /// written, so a device check changes one line.
  static const Set<TargetPlatform> platformsOpeningOnPress = {
    TargetPlatform.macOS,
    TargetPlatform.linux,
  };

  /// The platform whose click timing and key hints the menu follows.
  final TargetPlatform platform;

  /// The edge of the secondary click that opens the menu on [platform].
  ComposerMenuOpensOn get opensOn => platformsOpeningOnPress.contains(platform)
      ? ComposerMenuOpensOn.press
      : ComposerMenuOpensOn.release;

  @override
  bool get usesPointerMenu => true;

  @override
  bool operator ==(Object other) =>
      other is ComposerMenuPolicy$Desktop && other.platform == platform;

  @override
  int get hashCode => platform.hashCode;
}
