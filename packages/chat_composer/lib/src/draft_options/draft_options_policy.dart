import 'package:chat_composer/src/draft_options/draft_link_page_policy.dart';
import 'package:chat_composer/src/draft_options/draft_options_card.dart';
import 'package:chat_composer/src/draft_options/draft_options_desktop_box.dart';
import 'package:chat_composer/src/draft_options/draft_options_spring_surface.dart';
import 'package:chat_composer/src/draft_options/draft_options_web_menu_policy.dart';
import 'package:chat_composer/src/input/composer_keyboard_intent.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';

/// A part of the draft the draft options overlay has a page for.
///
/// The link page is the only page today; reply and forward are admitted by
/// the shape and come with those features.
enum DraftPart {
  /// The reply the draft answers.
  reply,

  /// The messages the draft forwards.
  forward,

  /// The draft's link preview.
  link,
}

/// When the draft options overlay hands its edits to the host.
enum DraftOptionsApply {
  /// Each edit is reported at once; apply only closes. The mobile default.
  liveApply,

  /// Edits stay in a copy local to the overlay: save reports the copy and
  /// closes, cancel and Escape discard it, Enter saves. The desktop default.
  commitOnSave,
}

/// What heads a page of the draft options overlay.
enum DraftOptionsTitle {
  /// A header bar with the page's title and subtitle.
  titleAndSubtitle,

  /// The page's title, when the overlay has one part (several parts show
  /// tabs instead).
  titleWithOnePart,

  /// No title.
  none,
}

/// Which links of the draft's text a tap in the live preview may choose as
/// the one to preview.
enum DraftOptionsLinkChoice {
  /// Any link, only when the text has more than one: a tap on the single
  /// link of a text is ignored.
  severalLinks,

  /// Any link of the text, a single one too.
  anyLink,
}

/// The overlay's presentation family, as its events name it.
enum DraftOptionsPresentation {
  /// A full-window card over the chat.
  android,

  /// Content springing from the strip.
  ios,

  /// The iOS form in a regular-width window.
  ipad,

  /// A modal box.
  desktop,

  /// No overlay: a menu anchored at the strip.
  web,
}

/// What the draft options overlay asks of the soft keyboard: the [intent]
/// it states on open while the keyboard is up, and when a held keyboard
/// comes back on close.
@immutable
final class DraftOptionsKeyboard {
  /// A keyboard rule; see the fields.
  const DraftOptionsKeyboard({
    required this.intent,
    this.reopenDelay = Duration.zero,
    this.holdReleaseDelay = Duration.zero,
  });

  /// The keyboard hides under the overlay and its height stays occupied, so
  /// the composer does not drop; on close it reopens 50 ms after the close
  /// starts and the hold ends 15 ms after the overlay is gone. The Android
  /// default.
  static const hold = DraftOptionsKeyboard(
    intent: ComposerKeyboardIntent.hold,
    reopenDelay: ChromeKeyboardTiming.heldReopen,
    holdReleaseDelay: ChromeKeyboardTiming.holdRelease,
  );

  /// The keyboard is left as it is: the overlay draws above it, or there is
  /// no soft keyboard.
  static const keep = DraftOptionsKeyboard(intent: ComposerKeyboardIntent.keep);

  /// What the overlay states on open while the keyboard is up; an overlay
  /// opened with the keyboard down keeps it.
  final ComposerKeyboardIntent intent;

  /// From the start of a close to the reopening of a held keyboard, which
  /// then rises while the overlay fades, under the held height. A close by
  /// the remove row does not reopen it.
  final Duration reopenDelay;

  /// From the overlay's full close to the end of the hold. A keyboard that
  /// reopened takes the held height over; otherwise the slot shrinks.
  final Duration holdReleaseDelay;
}

/// How the draft options are presented and applied on one platform family:
/// a pure-Dart value, chosen like the composer's other policies.
///
/// - [DraftOptionsPolicy$Android]: a full-window card, applied live.
/// - [DraftOptionsPolicy$IOS]: content from the strip, applied live.
/// - [DraftOptionsPolicy$Desktop]: a modal box, committed on save.
/// - [DraftOptionsPolicy$Web]: no overlay; the options are a menu anchored at
///   the strip, each choice applied at once.
///
/// Every field is a default a host may override through the variant's
/// constructor.
@immutable
sealed class DraftOptionsPolicy {
  const DraftOptionsPolicy({
    required this.partOrder,
    required this.apply,
    required this.opensOnPending,
    required this.title,
    required this.keyboard,
    required this.linkChoice,
    required this.keepsChosenLinkSelected,
    required this.linkPage,
  });

  /// See [DraftOptionsPolicy$Android].
  const factory DraftOptionsPolicy.android({
    List<DraftPart> partOrder,
    DraftOptionsApply apply,
    bool opensOnPending,
    DraftOptionsTitle title,
    ChromeScrimPreset scrim,
    DraftOptionsKeyboard keyboard,
    DraftOptionsLinkChoice linkChoice,
    bool keepsChosenLinkSelected,
    DraftLinkPagePolicy linkPage,
    DraftOptionsCardLayout card,
    DraftOptionsCardMotion cardMotion,
  }) = DraftOptionsPolicy$Android;

  /// See [DraftOptionsPolicy$IOS].
  const factory DraftOptionsPolicy.ios({
    bool iPad,
    List<DraftPart> partOrder,
    DraftOptionsApply apply,
    bool opensOnPending,
    DraftOptionsTitle title,
    ChromeScrimPreset? scrim,
    DraftOptionsKeyboard keyboard,
    DraftOptionsLinkChoice linkChoice,
    bool keepsChosenLinkSelected,
    DraftLinkPagePolicy linkPage,
    DraftOptionsSpringSurface? surface,
  }) = DraftOptionsPolicy$IOS;

  /// See [DraftOptionsPolicy$Desktop].
  const factory DraftOptionsPolicy.desktop({
    List<DraftPart> partOrder,
    DraftOptionsApply apply,
    bool opensOnPending,
    DraftOptionsTitle title,
    ChromeScrimPreset scrim,
    DraftOptionsKeyboard keyboard,
    DraftOptionsLinkChoice linkChoice,
    bool keepsChosenLinkSelected,
    DraftLinkPagePolicy linkPage,
    DraftOptionsDesktopBox box,
  }) = DraftOptionsPolicy$Desktop;

  /// See [DraftOptionsPolicy$Web].
  const factory DraftOptionsPolicy.web({
    List<DraftPart> partOrder,
    DraftOptionsApply apply,
    bool opensOnPending,
    DraftOptionsKeyboard keyboard,
    DraftOptionsLinkChoice linkChoice,
    DraftLinkPagePolicy linkPage,
    DraftOptionsWebMenuPolicy menu,
  }) = DraftOptionsPolicy$Web;

  /// The default of [platform]: Android (and Fuchsia), iOS (the iPad form
  /// for a [regularWidth] window), desktop for macOS, Windows and Linux.
  ///
  /// The web is not desktop: in a browser every platform takes the web's
  /// menu.
  factory DraftOptionsPolicy.forPlatform(
    TargetPlatform platform, {
    bool isWeb = false,
    bool regularWidth = false,
  }) {
    if (isWeb) return const DraftOptionsPolicy.web();
    return switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia => const DraftOptionsPolicy.android(),
      TargetPlatform.iOS => DraftOptionsPolicy.ios(iPad: regularWidth),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => const DraftOptionsPolicy.desktop(),
    };
  }

  /// The order of the pages, by part; a part absent from the draft has no
  /// page.
  final List<DraftPart> partOrder;

  /// When edits reach the host.
  final DraftOptionsApply apply;

  /// Whether the overlay opens on a page that is still loading (the preview
  /// shows it loading); when false it opens only on a loaded page.
  final bool opensOnPending;

  /// What heads a page.
  final DraftOptionsTitle title;

  /// What the overlay asks of the soft keyboard.
  final DraftOptionsKeyboard keyboard;

  /// Which links a tap in the live preview may choose.
  final DraftOptionsLinkChoice linkChoice;

  /// Whether the chosen link stays highlighted as selected once its page has
  /// loaded; otherwise the highlight goes with the spinner.
  final bool keepsChosenLinkSelected;

  /// The link page's rows: which show and when, their labels, presses and
  /// motion.
  final DraftLinkPagePolicy linkPage;

  /// The presentation family, for the overlay's events.
  DraftOptionsPresentation get presentation;

  /// The scrim under the overlay; null where there is no overlay.
  ChromeScrimPreset? get scrim;

  /// Whether the options open as the overlay; false for the web's menu.
  bool get usesOverlay => scrim != null;

  /// The pages of a draft holding [present], in [partOrder].
  List<DraftPart> pages(Set<DraftPart> present) => [
    for (final part in partOrder)
      if (present.contains(part)) part,
  ];
}

/// The Android form: a full-window card over the chat under the Android
/// scrim, applied live, opening on a pending page; pages reply, forward,
/// link, each headed by a title and subtitle. The card's metrics are [card]
/// and its motion [cardMotion]; the link page's rows stand in a glass menu
/// under it that samples the scrim's glass source.
final class DraftOptionsPolicy$Android extends DraftOptionsPolicy {
  /// The Android policy; every field is the platform's default unless given.
  const DraftOptionsPolicy$Android({
    super.partOrder = const [
      DraftPart.reply,
      DraftPart.forward,
      DraftPart.link,
    ],
    super.apply = DraftOptionsApply.liveApply,
    super.opensOnPending = true,
    super.title = DraftOptionsTitle.titleAndSubtitle,
    this.scrim = ChromeScrimPreset.android,
    super.keyboard = DraftOptionsKeyboard.hold,
    super.linkChoice = DraftOptionsLinkChoice.severalLinks,
    super.keepsChosenLinkSelected = false,
    super.linkPage = DraftLinkPagePolicy.android,
    this.card = DraftOptionsCardLayout.android,
    this.cardMotion = DraftOptionsCardMotion.android,
  });

  @override
  final ChromeScrimPreset scrim;

  /// Where the card and its menu stand, portrait and landscape.
  final DraftOptionsCardLayout card;

  /// How the card opens, closes and follows a change.
  final DraftOptionsCardMotion cardMotion;

  @override
  DraftOptionsPresentation get presentation => DraftOptionsPresentation.android;
}

/// The iOS form: content springing from the strip under the iOS scrim (the
/// iPad one in a regular-width window), applied live, opening on a pending
/// page, with no title.
final class DraftOptionsPolicy$IOS extends DraftOptionsPolicy {
  /// The iOS policy; [iPad] for a regular-width window. Every field is the
  /// platform's default unless given.
  const DraftOptionsPolicy$IOS({
    this.iPad = false,
    super.partOrder = const [
      DraftPart.link,
      DraftPart.reply,
      DraftPart.forward,
    ],
    super.apply = DraftOptionsApply.liveApply,
    super.opensOnPending = true,
    super.title = DraftOptionsTitle.none,
    ChromeScrimPreset? scrim,
    super.keyboard = DraftOptionsKeyboard.keep,
    super.linkChoice = DraftOptionsLinkChoice.anyLink,
    super.keepsChosenLinkSelected = false,
    super.linkPage = DraftLinkPagePolicy.ios,
    DraftOptionsSpringSurface? surface,
  }) : _scrim = scrim,
       _surface = surface;

  /// Whether the window is regular width: the iPad form.
  final bool iPad;

  final ChromeScrimPreset? _scrim;
  final DraftOptionsSpringSurface? _surface;

  /// The content springing from the strip and its actions: their layout,
  /// motion and haptic; the iPad surface in a regular-width window unless
  /// given.
  DraftOptionsSpringSurface get surface =>
      _surface ??
      (iPad ? DraftOptionsSpringSurface.iPad : DraftOptionsSpringSurface.phone);

  @override
  ChromeScrimPreset get scrim =>
      _scrim ?? (iPad ? ChromeScrimPreset.ipad : ChromeScrimPreset.ios);

  @override
  DraftOptionsPresentation get presentation =>
      iPad ? DraftOptionsPresentation.ipad : DraftOptionsPresentation.ios;
}

/// The desktop form: a modal box under the desktop scrim, committed on save,
/// opening only on a loaded page; pages link, reply, forward, a title when
/// there is one part. The box ([box]) takes keyboard focus on open, saves
/// on Enter, discards on Escape and Cancel, and gives focus back to the
/// composer's field on close.
final class DraftOptionsPolicy$Desktop extends DraftOptionsPolicy {
  /// The desktop policy; every field is the platform's default unless given.
  const DraftOptionsPolicy$Desktop({
    super.partOrder = const [
      DraftPart.link,
      DraftPart.reply,
      DraftPart.forward,
    ],
    super.apply = DraftOptionsApply.commitOnSave,
    super.opensOnPending = false,
    super.title = DraftOptionsTitle.titleWithOnePart,
    this.scrim = ChromeScrimPreset.desktop,
    super.keyboard = DraftOptionsKeyboard.keep,
    super.linkChoice = DraftOptionsLinkChoice.anyLink,
    super.keepsChosenLinkSelected = true,
    super.linkPage = DraftLinkPagePolicy.desktop,
    this.box = DraftOptionsDesktopBox.standard,
  });

  @override
  final ChromeScrimPreset scrim;

  /// The modal box: its size, title, buttons and motion.
  final DraftOptionsDesktopBox box;

  @override
  DraftOptionsPresentation get presentation => DraftOptionsPresentation.desktop;
}

/// The web form: no overlay, no scrim, no live preview; the options are a
/// menu anchored at the strip, each choice applied at once.
final class DraftOptionsPolicy$Web extends DraftOptionsPolicy {
  /// The web policy; every field is the web's default unless given.
  const DraftOptionsPolicy$Web({
    super.partOrder = const [
      DraftPart.link,
      DraftPart.reply,
      DraftPart.forward,
    ],
    super.apply = DraftOptionsApply.liveApply,
    super.opensOnPending = true,
    super.keyboard = DraftOptionsKeyboard.keep,
    super.linkChoice = DraftOptionsLinkChoice.anyLink,
    super.linkPage = DraftLinkPagePolicy.web,
    this.menu = DraftOptionsWebMenuPolicy.standard,
  }) : super(title: DraftOptionsTitle.none, keepsChosenLinkSelected: false);

  /// The menu anchored at the strip: how it opens, looks, moves and
  /// closes.
  final DraftOptionsWebMenuPolicy menu;

  @override
  ChromeScrimPreset? get scrim => null;

  @override
  DraftOptionsPresentation get presentation => DraftOptionsPresentation.web;
}
