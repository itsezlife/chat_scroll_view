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

// Shift+V with the platform's shortcut key: Command on Apple platforms,
// Control elsewhere. Both are bound, since a policy is per input family, not
// per platform.
const Map<ShortcutActivator, Intent> _pastePlain = {
  SingleActivator(LogicalKeyboardKey.keyV, meta: true, shift: true):
      PastePlainTextIntent(),
  SingleActivator(LogicalKeyboardKey.keyV, control: true, shift: true):
      PastePlainTextIntent(),
};

/// The default key bindings of the composer, chosen like the selection
/// policies: one pure-Dart strategy per input family.
///
/// A host that wants other bindings passes its own map to `ComposerView`;
/// there is no merging with these.
sealed class ComposerShortcutPolicy {
  const ComposerShortcutPolicy();

  /// Touch-first platforms: no key submits, because Enter belongs to the
  /// on-screen keyboard's newline; Escape dismisses the header for attached
  /// keyboards.
  const factory ComposerShortcutPolicy.mobile() = ComposerShortcutPolicy$Mobile;

  /// Keyboard-first platforms: Enter submits, Shift+Enter inserts a newline,
  /// Escape dismisses the header.
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
    if (!inBrowser) ..._pastePlain,
  };
}
