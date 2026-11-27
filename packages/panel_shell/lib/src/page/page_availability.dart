import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:meta/meta.dart';

/// Whether a registered page can be used now, and how it shows when it
/// cannot: the **page availability** the host sets on the registry.
///
/// The shell knows no reason a page is not available; the host decides it
/// (a chat that does not allow stickers, say) and gives the text to show.
/// A text is null for the silent form of [dimmed] (no hint) and of
/// [replaced] (an empty page).
///
/// | Form | Tab | Selecting it | Content |
/// |---|---|---|---|
/// | [available] | as always | selects | the page's |
/// | [dimmed] | drawn faint, still focusable, spoken as not available | refused; the panel leaves the page, and the attempt shows the hint at the tab | none |
/// | [hidden] | removed | refused; the panel leaves the page | none |
/// | [replaced] | as always | selects | the text in place of the page |
///
/// The default of an unavailable page per platform is
/// [PageUnavailableForm.forPlatform]; a host may set any form.
@immutable
sealed class PageAvailability {
  const PageAvailability._();

  /// The page as registered: the default.
  const factory PageAvailability.available() = PageAvailability$Available;

  /// The tab drawn faint; trying the page shows [hint] at its tab.
  const factory PageAvailability.dimmed([String? hint]) =
      PageAvailability$Dimmed;

  /// The tab and the page removed from the panel.
  const factory PageAvailability.hidden() = PageAvailability$Hidden;

  /// The tab kept and the page's content replaced by [text].
  const factory PageAvailability.replaced([String? text]) =
      PageAvailability$Replaced;

  /// Whether the page can be the selected one: [available] or [replaced].
  bool get isSelectable;

  /// Whether the page has a tab and a place in the pager: every form but
  /// [hidden].
  bool get isShown;

  /// The form's name in diagnostics events: `available`, `dimmed`, `hidden`
  /// or `replaced`. Never the text.
  String get diagnosticForm;
}

/// [PageAvailability.available].
final class PageAvailability$Available extends PageAvailability {
  /// The page as registered.
  const PageAvailability$Available() : super._();

  @override
  bool get isSelectable => true;

  @override
  bool get isShown => true;

  @override
  String get diagnosticForm => 'available';

  @override
  bool operator ==(Object other) => other is PageAvailability$Available;

  @override
  int get hashCode => (PageAvailability$Available).hashCode;

  @override
  String toString() => 'PageAvailability.available()';
}

/// [PageAvailability.dimmed].
final class PageAvailability$Dimmed extends PageAvailability {
  /// A faint tab whose attempt shows [hint].
  const PageAvailability$Dimmed([this.hint]) : super._();

  /// What the tab's hint says and its spoken hint is; null for none.
  final String? hint;

  @override
  bool get isSelectable => false;

  @override
  bool get isShown => true;

  @override
  String get diagnosticForm => 'dimmed';

  @override
  bool operator ==(Object other) =>
      other is PageAvailability$Dimmed && other.hint == hint;

  @override
  int get hashCode => Object.hash(PageAvailability$Dimmed, hint);

  @override
  String toString() => 'PageAvailability.dimmed()';
}

/// [PageAvailability.hidden].
final class PageAvailability$Hidden extends PageAvailability {
  /// No tab and no page.
  const PageAvailability$Hidden() : super._();

  @override
  bool get isSelectable => false;

  @override
  bool get isShown => false;

  @override
  String get diagnosticForm => 'hidden';

  @override
  bool operator ==(Object other) => other is PageAvailability$Hidden;

  @override
  int get hashCode => (PageAvailability$Hidden).hashCode;

  @override
  String toString() => 'PageAvailability.hidden()';
}

/// [PageAvailability.replaced].
final class PageAvailability$Replaced extends PageAvailability {
  /// The tab kept, the page showing [text].
  const PageAvailability$Replaced([this.text]) : super._();

  /// What the page shows in place of its content; null for an empty page.
  final String? text;

  @override
  bool get isSelectable => true;

  @override
  bool get isShown => true;

  @override
  String get diagnosticForm => 'replaced';

  @override
  bool operator ==(Object other) =>
      other is PageAvailability$Replaced && other.text == text;

  @override
  int get hashCode => Object.hash(PageAvailability$Replaced, text);

  @override
  String toString() => 'PageAvailability.replaced()';
}

/// The form an unavailable page takes, before its text is known: the
/// presentation policy of an unavailable page.
///
/// A host that finds a page unavailable builds its availability with
/// [withText] from the form of its platform ([forPlatform]) or one of its
/// own choosing.
enum PageUnavailableForm {
  /// [PageAvailability.dimmed]: the tab faint, the hint shown on a tap. The
  /// Android family's form.
  dimmed,

  /// [PageAvailability.hidden]: the tab removed. The iOS form.
  hidden,

  /// [PageAvailability.replaced]: the page's content replaced by the text.
  /// The desktop form.
  replaced;

  /// The form of the family of [platform]: [dimmed] on Android (and
  /// Fuchsia), [hidden] on iOS, [replaced] on macOS, Windows and Linux.
  ///
  /// A web host passes the platform it presents as (the browser's family,
  /// or what its input and width call for), never the desktop one by
  /// default.
  static PageUnavailableForm forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.android || TargetPlatform.fuchsia => dimmed,
        TargetPlatform.iOS => hidden,
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => replaced,
      };

  /// This form with [text]: the hint of [dimmed], the content of
  /// [replaced]; [hidden] shows none.
  PageAvailability withText(String? text) => switch (this) {
    dimmed => PageAvailability.dimmed(text),
    hidden => const PageAvailability.hidden(),
    replaced => PageAvailability.replaced(text),
  };
}
