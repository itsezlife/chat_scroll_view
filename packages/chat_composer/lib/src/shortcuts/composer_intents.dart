import 'package:chat_composer/src/shortcuts/composer_formatting_intents.dart';
import 'package:content_model/content_model.dart'
    show EntityListKind, EntityStyle;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Asks the composer to submit: invokes its primary action.
///
/// Does nothing while the input method is composing, the spec is busy or
/// disabled, or there is no tappable primary action, so the shortcut never
/// swallows the key that confirms a composition.
class SubmitComposerIntent extends Intent {
  /// Creates the intent.
  const SubmitComposerIntent();
}

/// Asks the composer to dismiss its header: cancels a reply or an edit.
///
/// Does nothing when there is no header or it has no dismiss handler.
class DismissComposerHeaderIntent extends Intent {
  /// Creates the intent.
  const DismissComposerHeaderIntent();
}

/// Asks the composer to paste the clipboard's plain text, without its
/// formatting.
///
/// Does nothing when the composer has no clipboard.
class PastePlainTextIntent extends Intent {
  /// Creates the intent.
  const PastePlainTextIntent();
}

/// Asks the composer to open its pointer menu from the keyboard, at the caret.
///
/// Bound to the Menu key and Shift+F10 by the desktop policy; answered only
/// where the composer's menu policy has a pointer menu.
class ShowComposerMenuIntent extends Intent {
  /// Creates the intent.
  const ShowComposerMenuIntent();
}

// Shift+V with the platform's shortcut key: Command on Apple platforms,
// Control elsewhere. Both are bound, since a policy is per input family, not
// per platform.
const Map<ShortcutActivator, Intent> _pastePlain = {
  SingleActivator(LogicalKeyboardKey.keyV, meta: true, shift: true):
      PastePlainTextIntent(),
  SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
      PastePlainTextIntent(),
};

// The reference desktop client's formatting keys, with the platform's shortcut key: Command
// on Apple platforms, Control elsewhere. Both are bound, since a policy is per
// input family, not per platform. The digit keys are the vendored list
// editor's: 7 is numbered, 8 is bullets.
const Map<ShortcutActivator, Intent> _formatting = {
  SingleActivator(LogicalKeyboardKey.keyB, meta: true): ToggleStyleIntent(
    EntityStyle.bold,
  ),
  SingleActivator(LogicalKeyboardKey.keyB, control: true): ToggleStyleIntent(
    EntityStyle.bold,
  ),
  SingleActivator(LogicalKeyboardKey.keyI, meta: true): ToggleStyleIntent(
    EntityStyle.italic,
  ),
  SingleActivator(LogicalKeyboardKey.keyI, control: true): ToggleStyleIntent(
    EntityStyle.italic,
  ),
  SingleActivator(LogicalKeyboardKey.keyU, meta: true): ToggleStyleIntent(
    EntityStyle.underline,
  ),
  SingleActivator(LogicalKeyboardKey.keyU, control: true): ToggleStyleIntent(
    EntityStyle.underline,
  ),
  SingleActivator(LogicalKeyboardKey.keyX, meta: true, shift: true):
      ToggleStyleIntent(EntityStyle.strike),
  SingleActivator(LogicalKeyboardKey.keyX, control: true, shift: true):
      ToggleStyleIntent(EntityStyle.strike),
  SingleActivator(LogicalKeyboardKey.keyM, meta: true, shift: true):
      ToggleStyleIntent(EntityStyle.code),
  SingleActivator(LogicalKeyboardKey.keyM, control: true, shift: true):
      ToggleStyleIntent(EntityStyle.code),
  SingleActivator(LogicalKeyboardKey.keyP, meta: true, shift: true):
      ToggleStyleIntent(EntityStyle.spoiler),
  SingleActivator(LogicalKeyboardKey.keyP, control: true, shift: true):
      ToggleStyleIntent(EntityStyle.spoiler),
  SingleActivator(LogicalKeyboardKey.period, meta: true, shift: true):
      ToggleStyleIntent(EntityStyle.quote),
  SingleActivator(LogicalKeyboardKey.period, control: true, shift: true):
      ToggleStyleIntent(EntityStyle.quote),
  SingleActivator(LogicalKeyboardKey.keyK, meta: true): ApplyLinkIntent(),
  SingleActivator(LogicalKeyboardKey.keyK, control: true): ApplyLinkIntent(),
  SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true):
      ClearFormattingIntent(),
  SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
      ClearFormattingIntent(),
  SingleActivator(LogicalKeyboardKey.digit7, meta: true, shift: true):
      ToggleListIntent(EntityListKind.ordered),
  SingleActivator(LogicalKeyboardKey.digit7, control: true, shift: true):
      ToggleListIntent(EntityListKind.ordered),
  SingleActivator(LogicalKeyboardKey.digit8, meta: true, shift: true):
      ToggleListIntent(EntityListKind.bullet),
  SingleActivator(LogicalKeyboardKey.digit8, control: true, shift: true):
      ToggleListIntent(EntityListKind.bullet),
};

// The keys of list editing. Each is answered only where the text controller
// has lists on and the command would do something, so everywhere else the key
// reaches the field (Tab moves focus, Backspace deletes, Shift+Enter breaks
// the line).
const Map<ShortcutActivator, Intent> _listEditing = {
  SingleActivator(LogicalKeyboardKey.tab): IndentListItemsIntent(),
  SingleActivator(LogicalKeyboardKey.tab, shift: true):
      OutdentListItemsIntent(),
  SingleActivator(LogicalKeyboardKey.enter, shift: true):
      InsertSoftBreakIntent(),
  SingleActivator(LogicalKeyboardKey.backspace): OutdentOrExitListItemIntent(),
};

/// The default key bindings of the composer, chosen like the selection
/// policies: one pure-Dart strategy per input family.
///
/// A host that wants other bindings passes its own map to `ComposerView`;
/// there is no merging with these.
sealed class ComposerShortcutPolicy {
  const ComposerShortcutPolicy();

  /// Touch-first platforms: no key submits, because Enter belongs to the
  /// on-screen keyboard's newline; Escape dismisses the header and the
  /// formatting keys format, for attached keyboards.
  const factory ComposerShortcutPolicy.mobile() = ComposerShortcutPolicy$Mobile;

  /// Keyboard-first platforms: Enter submits, Shift+Enter inserts a newline,
  /// Escape dismisses the header, and the reference desktop client's formatting keys
  /// apply (Ctrl or Cmd with B, I, U, K; with Shift also X strikethrough,
  /// M monospace, P spoiler, `.` quote, N clear formatting, 7 numbered list,
  /// 8 bullet list). The code block has no key. The list editing keys (Tab,
  /// Shift+Tab, Shift+Enter, Backspace) are bound too and answered only by a
  /// text with lists on. The Menu key and Shift+F10 are bound to
  /// [ShowComposerMenuIntent], which the field answers where its menu policy
  /// has a pointer menu.
  ///
  /// [inBrowser] leaves paste as plain text to the browser: Flutter leaves the
  /// clipboard keys of a text field to it, and it pastes as plain text with
  /// Shift itself, with no permission to ask for.
  const factory ComposerShortcutPolicy.desktop({bool inBrowser}) =
      ComposerShortcutPolicy$Desktop;

  /// The policy for [platform]; the web counts as desktop, in a browser.
  factory ComposerShortcutPolicy.forPlatform(
    TargetPlatform platform, {
    bool isWeb = false,
  }) {
    if (isWeb) return const ComposerShortcutPolicy.desktop(inBrowser: true);
    return switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => const ComposerShortcutPolicy.mobile(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => const ComposerShortcutPolicy.desktop(),
    };
  }

  /// The key bindings.
  Map<ShortcutActivator, Intent> get shortcuts;
}

/// Bindings for touch-first platforms; see [ComposerShortcutPolicy.mobile].
final class ComposerShortcutPolicy$Mobile extends ComposerShortcutPolicy {
  /// Creates the policy.
  const ComposerShortcutPolicy$Mobile();

  @override
  Map<ShortcutActivator, Intent> get shortcuts => const {
    SingleActivator(LogicalKeyboardKey.escape): DismissComposerHeaderIntent(),
    ..._pastePlain,
    ..._formatting,
    ..._listEditing,
  };
}

/// Bindings for keyboard-first platforms; see
/// [ComposerShortcutPolicy.desktop].
final class ComposerShortcutPolicy$Desktop extends ComposerShortcutPolicy {
  /// Creates the policy.
  const ComposerShortcutPolicy$Desktop({this.inBrowser = false});

  /// Whether the composer runs in a browser, which pastes as plain text
  /// itself; see [ComposerShortcutPolicy.desktop].
  final bool inBrowser;

  @override
  Map<ShortcutActivator, Intent> get shortcuts => {
    const SingleActivator(LogicalKeyboardKey.enter):
        const SubmitComposerIntent(),
    const SingleActivator(LogicalKeyboardKey.numpadEnter):
        const SubmitComposerIntent(),
    const SingleActivator(LogicalKeyboardKey.escape):
        const DismissComposerHeaderIntent(),
    const SingleActivator(LogicalKeyboardKey.contextMenu):
        const ShowComposerMenuIntent(),
    const SingleActivator(LogicalKeyboardKey.f10, shift: true):
        const ShowComposerMenuIntent(),
    if (!inBrowser) ..._pastePlain,
    ..._formatting,
    ..._listEditing,
  };
}
