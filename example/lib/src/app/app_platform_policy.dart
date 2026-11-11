import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:panel_shell/panel_shell.dart';

/// The platform family the demo host arranges its own chrome for: a phone's
/// ([AppPlatformPolicy$Mobile]) or a desktop's, the web included
/// ([AppPlatformPolicy$Desktop]).
///
/// The one place the host reads the platform for its chrome choices: the
/// bulletin colours, the pack sheet's arrangement and its questions, which
/// library edits a bulletin says, and the message menu's chrome. The
/// packages' own policies (bulletins, panel presentation, appear motion) pick
/// their families themselves; this one agrees with them: Android and iOS are
/// mobile, every other operating system and the web is a desktop.
@immutable
sealed class AppPlatformPolicy {
  const AppPlatformPolicy._();

  /// An Android phone.
  const factory AppPlatformPolicy.android() = AppPlatformPolicy$Mobile.android;

  /// An iPhone.
  const factory AppPlatformPolicy.iOS() = AppPlatformPolicy$Mobile.iOS;

  /// A desktop app.
  const factory AppPlatformPolicy.desktop() = AppPlatformPolicy$Desktop.app;

  /// A browser, on any operating system.
  const factory AppPlatformPolicy.web() = AppPlatformPolicy$Desktop.web;

  /// The family of [platform]; [isWeb] wins over it.
  factory AppPlatformPolicy.forPlatform(
    TargetPlatform platform, {
    required bool isWeb,
  }) {
    if (isWeb) return const AppPlatformPolicy.web();
    return switch (platform) {
      TargetPlatform.android => const AppPlatformPolicy.android(),
      TargetPlatform.iOS => const AppPlatformPolicy.iOS(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => const AppPlatformPolicy.desktop(),
    };
  }

  /// The family of the running app (read on each call, so a test's platform
  /// override reaches it).
  factory AppPlatformPolicy.current() =>
      AppPlatformPolicy.forPlatform(defaultTargetPlatform, isWeb: kIsWeb);

  /// The bulletin colours the app's theme scope supplies, or null for the
  /// group's default (the dark card).
  BulletinTokens? get bulletinTokens;

  /// How a pack sheet is arranged: a bottom sheet to touch or a centred box
  /// to point at.
  PanelArrangement get packSheetArrangement;

  /// Whether the app asks its questions (a pack's removal) in boxes on a box
  /// layer rather than in the platform's dialog.
  bool get asksInBoxes;

  /// Whether a pack's removal from a pack sheet asks first.
  bool get confirmsPackRemovals;

  /// Whether a library edit (a favourite, a recent, a saved GIF, a pack added
  /// or removed) is said in a bulletin, with Undo for a removal. Where it is
  /// not, the edit shows only in the lists and a removal is done at once.
  bool get saysLibraryEdits;

  /// Whether a full list replacing its oldest entry is said in a bulletin,
  /// even where [saysLibraryEdits] is false.
  bool get saysListReplacements;

  /// The press feedback of the platform, which also picks the message menu's
  /// chrome: the Android rows and glass for [ChromeInkKind.ripple], the
  /// pointer menu's rows and card for [ChromeInkKind.pointer].
  ChromeInkKind get inkKind;
}

/// A phone: a pack sheet is a bottom sheet, removals are done behind Undo
/// and every library edit is said in a bulletin.
final class AppPlatformPolicy$Mobile extends AppPlatformPolicy {
  /// An Android phone.
  const AppPlatformPolicy$Mobile.android() : android = true, super._();

  /// An iPhone.
  const AppPlatformPolicy$Mobile.iOS() : android = false, super._();

  /// Whether this is Android (iOS otherwise).
  final bool android;

  @override
  BulletinTokens? get bulletinTokens => null;

  @override
  PanelArrangement get packSheetArrangement => PanelArrangement.touch;

  @override
  bool get asksInBoxes => false;

  @override
  bool get confirmsPackRemovals => false;

  @override
  bool get saysLibraryEdits => true;

  @override
  bool get saysListReplacements => true;

  @override
  ChromeInkKind get inkKind =>
      android ? ChromeInkKind.ripple : ChromeInkKind.highlight;

  @override
  bool operator ==(Object other) =>
      other is AppPlatformPolicy$Mobile && other.android == android;

  @override
  int get hashCode => Object.hash(AppPlatformPolicy$Mobile, android);
}

/// A desktop app or a browser: a pack sheet is a box on a box layer, the
/// bulletin is the desktop toast in its own colours, and library edits show
/// only in the lists. An app asks before it removes a pack; a browser
/// removes it at once and still says a full list's replacement.
final class AppPlatformPolicy$Desktop extends AppPlatformPolicy {
  /// A desktop app.
  const AppPlatformPolicy$Desktop.app() : web = false, super._();

  /// A browser.
  const AppPlatformPolicy$Desktop.web() : web = true, super._();

  /// Whether this is a browser.
  final bool web;

  @override
  BulletinTokens? get bulletinTokens => BulletinTokens.desktop;

  @override
  PanelArrangement get packSheetArrangement => PanelArrangement.pointer;

  @override
  bool get asksInBoxes => true;

  @override
  bool get confirmsPackRemovals => !web;

  @override
  bool get saysLibraryEdits => false;

  @override
  bool get saysListReplacements => web;

  @override
  ChromeInkKind get inkKind => ChromeInkKind.pointer;

  @override
  bool operator ==(Object other) =>
      other is AppPlatformPolicy$Desktop && other.web == web;

  @override
  int get hashCode => Object.hash(AppPlatformPolicy$Desktop, web);
}
