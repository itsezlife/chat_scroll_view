import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// A **bulletin**: a short notice shown over a surface for a few seconds.
///
/// A value: it says what to show, and a `BulletinController` shows it. One
/// is visible per surface, and showing another replaces it.
///
/// [title] over [message] is the two-line form (a title and its subtitle);
/// without a title the message is one line. [leading] fills the slot before
/// the text, [action] the button after it.
@immutable
final class Bulletin {
  /// A bulletin with [message] and the optional parts.
  const Bulletin({
    required this.message,
    this.title,
    this.leading,
    this.action,
    this.duration,
    this.placement,
    this.maxLines,
    this.onTap,
    this.semanticsLabel,
  });

  /// The text; the subtitle when [title] is given.
  final String message;

  /// The line above [message], drawn bold; null for the one-line form.
  final String? title;

  /// What sits before the text; null for none.
  final BulletinLeading? leading;

  /// The button after the text; null for none.
  final BulletinAction? action;

  /// How long the bulletin stays; null lets [effectiveDuration] choose.
  final BulletinDuration? duration;

  /// Where the bulletin appears; null for the policy's placement.
  final BulletinPlacement? placement;

  /// The most lines [message] takes; null for the default (one line without a
  /// title, two under one).
  final int? maxLines;

  /// Called when the body (not the action) is tapped. The bulletin stays: the
  /// callback dismisses it through its handle when it should go.
  final VoidCallback? onTap;

  /// What assistive technology says; null for [title] and [message].
  final String? semanticsLabel;

  /// The text length under which a bulletin without an undo is short, as the
  /// reference factory decides.
  static const int shortTextLength = 20;

  /// [duration], or the reference factory's rule when it is null: an undo
  /// bulletin is prolonged; otherwise text (title and message together)
  /// under [shortTextLength] characters is short, and longer text is long.
  BulletinDuration get effectiveDuration {
    if (duration case final duration?) return duration;
    if (action case BulletinAction$Undo()) return BulletinDuration.prolonged;
    final length = (title?.length ?? 0) + message.length;
    return length < shortTextLength
        ? BulletinDuration.short
        : BulletinDuration.long;
  }

  /// The label announced and exposed to assistive technology.
  String get spokenLabel =>
      semanticsLabel ??
      switch (title) {
        final title? => '$title\n$message',
        null => message,
      };

  /// The most lines [message] takes.
  int get effectiveMaxLines => maxLines ?? (title == null ? 1 : 2);
}

/// Where a bulletin appears on its surface.
enum BulletinPlacement {
  /// Along the bottom edge, above the bottom obstruction.
  bottom,

  /// Along the top edge, below the top obstruction.
  top,

  /// In the middle of the surface.
  center,
}

// --- Leading ---

/// What sits before a bulletin's text: the **content kind** of a bulletin.
///
/// [animation] and [thumbnail] carry an opaque source the host resolves
/// through its `BulletinBuilders`; without a builder the slot keeps its size
/// and stays empty.
@immutable
sealed class BulletinLeading {
  const BulletinLeading._();

  /// A chrome icon, tinted with the bulletin's foreground colour.
  const factory BulletinLeading.icon(ChromeIconId icon) = BulletinLeading$Icon;

  /// A short vector animation, such as a "copied" check, played once.
  const factory BulletinLeading.animation(Object source) =
      BulletinLeading$Animation;

  /// A picture of the content the notice is about: a sticker, a photo.
  const factory BulletinLeading.thumbnail(Object source) =
      BulletinLeading$Thumbnail;

  /// A ring that empties over the time left, with the seconds left inside.
  const factory BulletinLeading.countdown() = BulletinLeading$Countdown;

  /// Anything else, built by the caller.
  const factory BulletinLeading.custom(WidgetBuilder builder) =
      BulletinLeading$Custom;
}

/// The [BulletinLeading.icon] kind.
final class BulletinLeading$Icon extends BulletinLeading {
  /// A leading [icon].
  const BulletinLeading$Icon(this.icon) : super._();

  /// The icon's semantic id.
  final ChromeIconId icon;

  @override
  bool operator ==(Object other) =>
      other is BulletinLeading$Icon && other.icon == icon;

  @override
  int get hashCode => Object.hash(BulletinLeading$Icon, icon);
}

/// The [BulletinLeading.animation] kind.
final class BulletinLeading$Animation extends BulletinLeading {
  /// A leading animation from [source].
  const BulletinLeading$Animation(this.source) : super._();

  /// What the host's animation builder plays (an asset key, a content key).
  final Object source;

  @override
  bool operator ==(Object other) =>
      other is BulletinLeading$Animation && other.source == source;

  @override
  int get hashCode => Object.hash(BulletinLeading$Animation, source);
}

/// The [BulletinLeading.thumbnail] kind.
final class BulletinLeading$Thumbnail extends BulletinLeading {
  /// A leading picture of [source].
  const BulletinLeading$Thumbnail(this.source) : super._();

  /// What the host's thumbnail builder draws (a content key, an image key).
  final Object source;

  @override
  bool operator ==(Object other) =>
      other is BulletinLeading$Thumbnail && other.source == source;

  @override
  int get hashCode => Object.hash(BulletinLeading$Thumbnail, source);
}

/// The [BulletinLeading.countdown] kind.
final class BulletinLeading$Countdown extends BulletinLeading {
  /// The countdown ring.
  const BulletinLeading$Countdown() : super._();

  @override
  bool operator ==(Object other) => other is BulletinLeading$Countdown;

  @override
  int get hashCode => (BulletinLeading$Countdown).hashCode;
}

/// The [BulletinLeading.custom] kind.
final class BulletinLeading$Custom extends BulletinLeading {
  /// A leading built by [builder].
  const BulletinLeading$Custom(this.builder) : super._();

  /// Builds the leading.
  final WidgetBuilder builder;
}

// --- Action ---

/// The button after a bulletin's text. Pressing it closes the bulletin.
@immutable
sealed class BulletinAction {
  const BulletinAction._();

  /// Undo: [onUndo] runs when it is pressed; [onCommit] runs once when the
  /// bulletin closes any other way (**commit on leave**). The label is the
  /// host's `BulletinStrings.undoAction`.
  const factory BulletinAction.undo({
    required VoidCallback onUndo,
    VoidCallback? onCommit,
  }) = BulletinAction$Undo;

  /// A button with the caller's [label]; [onPressed] runs when it is pressed.
  const factory BulletinAction.button({
    required String label,
    required VoidCallback onPressed,
  }) = BulletinAction$Button;
}

/// The [BulletinAction.undo] action.
final class BulletinAction$Undo extends BulletinAction {
  /// An undo action.
  const BulletinAction$Undo({required this.onUndo, this.onCommit}) : super._();

  /// Takes the change back; runs when Undo is pressed.
  final VoidCallback onUndo;

  /// Makes the change final; runs once when the bulletin closes without
  /// Undo. Null when there is nothing to commit.
  final VoidCallback? onCommit;
}

/// The [BulletinAction.button] action.
final class BulletinAction$Button extends BulletinAction {
  /// A button action.
  const BulletinAction$Button({required this.label, required this.onPressed})
    : super._();

  /// The button's label.
  final String label;

  /// Runs when the button is pressed.
  final VoidCallback onPressed;
}

// --- Duration ---

/// The class of a bulletin's duration; a `BulletinPolicy` maps each to a
/// timeout of its platform.
enum BulletinDurationClass {
  /// A short notice ("Copied").
  short,

  /// A notice with more to read.
  long,

  /// A notice with an Undo, or a large two-line one.
  prolonged,
}

/// How long a bulletin stays: a duration class, an exact time, or until it is
/// dismissed.
@immutable
sealed class BulletinDuration {
  const BulletinDuration._();

  /// Exactly [timeout], whatever the platform.
  const factory BulletinDuration.exactly(Duration timeout) =
      BulletinDuration$Exactly;

  /// The short class.
  static const BulletinDuration short = BulletinDuration$Class(
    BulletinDurationClass.short,
  );

  /// The long class.
  static const BulletinDuration long = BulletinDuration$Class(
    BulletinDurationClass.long,
  );

  /// The prolonged class.
  static const BulletinDuration prolonged = BulletinDuration$Class(
    BulletinDurationClass.prolonged,
  );

  /// No timeout: the bulletin stays until dismissed, replaced or swiped.
  static const BulletinDuration untilDismissed =
      BulletinDuration$UntilDismissed();
}

/// A [BulletinDurationClass] the policy maps to a timeout.
final class BulletinDuration$Class extends BulletinDuration {
  /// The class [value].
  const BulletinDuration$Class(this.value) : super._();

  /// The class.
  final BulletinDurationClass value;

  @override
  bool operator ==(Object other) =>
      other is BulletinDuration$Class && other.value == value;

  @override
  int get hashCode => Object.hash(BulletinDuration$Class, value);

  @override
  String toString() => 'BulletinDuration.${value.name}';
}

/// The [BulletinDuration.exactly] duration.
final class BulletinDuration$Exactly extends BulletinDuration {
  /// Exactly [timeout]; must be positive (the controller asserts it).
  const BulletinDuration$Exactly(this.timeout) : super._();

  /// The timeout.
  final Duration timeout;

  @override
  bool operator ==(Object other) =>
      other is BulletinDuration$Exactly && other.timeout == timeout;

  @override
  int get hashCode => Object.hash(BulletinDuration$Exactly, timeout);

  @override
  String toString() => 'BulletinDuration.exactly($timeout)';
}

/// The [BulletinDuration.untilDismissed] duration.
final class BulletinDuration$UntilDismissed extends BulletinDuration {
  /// No timeout.
  const BulletinDuration$UntilDismissed() : super._();

  @override
  bool operator ==(Object other) => other is BulletinDuration$UntilDismissed;

  @override
  int get hashCode => (BulletinDuration$UntilDismissed).hashCode;

  @override
  String toString() => 'BulletinDuration.untilDismissed';
}
