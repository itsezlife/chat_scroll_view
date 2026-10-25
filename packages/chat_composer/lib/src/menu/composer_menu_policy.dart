import 'package:flutter/foundation.dart';

/// Which edge of a secondary click opens the pointer menu.
enum ComposerMenuOpensOn {
  /// The moment the button goes down.
  press,

  /// The moment it comes up.
  release,
}

/// What the selection menu does with an action that cannot apply to the
/// selection (Bold inside code, Clear formatting over plain text).
enum ComposerUnavailableActions {
  /// Leave it out, so the menu holds only what can be chosen. The reference
  /// touch client builds its formatting menu this way.
  hide,

  /// Keep it in its place, greyed and without a tap, so the menu keeps its
  /// shape from one selection to the next, as a desktop menu does.
  disable,
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
///
/// Each also says what the selection menu does with the actions that cannot
/// apply ([unavailableActions]): the mobile policy leaves them out, the
/// desktop one greys them. A host passes the other value to either. The
/// pointer menu follows the reference desktop client and always greys them.
sealed class ComposerMenuPolicy {
  const ComposerMenuPolicy({required this.unavailableActions});

  /// The floating toolbar everywhere; unavailable actions left out unless
  /// [unavailableActions] says otherwise.
  const factory ComposerMenuPolicy.mobile({
    ComposerUnavailableActions unavailableActions,
  }) = ComposerMenuPolicy$Mobile;

  /// The pointer menu for a secondary click, with the hints and the click edge
  /// of [platform]; unavailable actions of the selection menu greyed unless
  /// [unavailableActions] says otherwise.
  const factory ComposerMenuPolicy.desktop({
    TargetPlatform platform,
    ComposerUnavailableActions unavailableActions,
  }) = ComposerMenuPolicy$Desktop;

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

  /// What the selection menu does with an action that cannot apply.
  final ComposerUnavailableActions unavailableActions;
}

/// Touch-first: no pointer menu; see [ComposerMenuPolicy.mobile].
@immutable
final class ComposerMenuPolicy$Mobile extends ComposerMenuPolicy {
  /// Creates the policy.
  const ComposerMenuPolicy$Mobile({
    super.unavailableActions = ComposerUnavailableActions.hide,
  });

  @override
  bool get usesPointerMenu => false;

  @override
  bool operator ==(Object other) =>
      other is ComposerMenuPolicy$Mobile &&
      other.unavailableActions == unavailableActions;

  @override
  int get hashCode => unavailableActions.hashCode;
}

/// Pointer-first: see [ComposerMenuPolicy.desktop].
@immutable
final class ComposerMenuPolicy$Desktop extends ComposerMenuPolicy {
  /// Creates the policy for [platform].
  const ComposerMenuPolicy$Desktop({
    this.platform = TargetPlatform.windows,
    super.unavailableActions = ComposerUnavailableActions.disable,
  });

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
      other is ComposerMenuPolicy$Desktop &&
      other.platform == platform &&
      other.unavailableActions == unavailableActions;

  @override
  int get hashCode => Object.hash(platform, unavailableActions);
}
