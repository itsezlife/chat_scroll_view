import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A target of the draft options box that keyboard focus reaches: Tab moves
/// to it in the order the box shows, Enter or Space presses it, and while
/// it is focused with the keyboard it wears the hover fill.
///
/// Its own shortcuts sit under the box's Enter (save), so Enter on a focused
/// row or button presses that target rather than saving: a user who tabbed
/// to Cancel means Cancel. Package-internal: the rows and the box's buttons
/// share it.
class DraftOptionsKeyFocus extends StatelessWidget {
  /// A focusable [child] pressed by [onPressed]; [enabled] false leaves it
  /// out of the focus order.
  const DraftOptionsKeyFocus({
    required this.onPressed,
    required this.child,
    this.enabled = true,
    this.borderRadius = BorderRadius.zero,
    super.key,
  });

  /// What a key press does.
  final VoidCallback onPressed;

  /// Whether the target takes focus.
  final bool enabled;

  /// The corners of the focus fill.
  final BorderRadius borderRadius;

  /// The target.
  final Widget child;

  static const Map<ShortcutActivator, Intent> _keys = {
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: enabled,
    shortcuts: _keys,
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          onPressed();
          return null;
        },
      ),
    },
    // The target's own ink sets the cursor.
    mouseCursor: MouseCursor.defer,
    child: Builder(
      builder: (context) {
        final focused =
            Focus.of(context).hasFocus &&
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional;
        // Always the same box, so the target keeps its state as focus
        // comes and goes.
        return DecoratedBox(
          decoration: BoxDecoration(
            color: focused
                ? ChromeButtonInks.hoverOf(ChromeThemeScope.paletteOf(context))
                : null,
            borderRadius: borderRadius,
          ),
          child: child,
        );
      },
    ),
  );
}
