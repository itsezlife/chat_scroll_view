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
  const factory ComposerShortcutPolicy.desktop() =
      ComposerShortcutPolicy$Desktop;

  /// The policy for [platform]; the web counts as desktop.
  factory ComposerShortcutPolicy.forPlatform(
    TargetPlatform platform, {
    bool isWeb = false,
  }) {
    if (isWeb) return const ComposerShortcutPolicy.desktop();
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
  const ComposerShortcutPolicy$Desktop();

  @override
  Map<ShortcutActivator, Intent> get shortcuts => const {
    SingleActivator(LogicalKeyboardKey.enter): SubmitComposerIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): SubmitComposerIntent(),
    SingleActivator(LogicalKeyboardKey.escape): DismissComposerHeaderIntent(),
    ..._pastePlain,
  };
}
