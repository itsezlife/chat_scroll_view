import 'package:chat_composer/src/spec/composer_panel.dart';
import 'package:chat_composer/src/view/composer_metrics.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The default panel of a write access that replaces the input row: the
/// host's [text] as a plain text node and, below it, the host's [action].
///
/// Either may be missing: a join bar is often its verb alone, a ban its
/// text alone. With neither the row is an empty bar (the silent form).
/// Centred, so it mirrors with the layout in right-to-left text.
class ComposerAccessPanel extends StatelessWidget {
  /// A panel of [text] and [action].
  const ComposerAccessPanel({
    required this.text,
    required this.action,
    super.key,
  });

  /// The host's denial text, or null for none.
  final String? text;

  /// The host's action, or null for none.
  final ComposerPanelAction? action;

  // Inside the island's row, clear of its rounded ends.
  static const _padding = EdgeInsetsDirectional.symmetric(
    horizontal: 12,
    vertical: 6,
  );

  @override
  Widget build(BuildContext context) {
    final base = ChromeTypography.of(
      context,
    ).copyWith(fontSize: ComposerMetrics.fieldFontSize);
    return Padding(
      padding: _padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text case final text?)
            Text(
              text,
              textAlign: TextAlign.center,
              style: base.copyWith(
                color: ChromeThemeScope.placeholderOf(context).fieldHint,
              ),
            ),
          if (action case final action?)
            _PanelActionButton(
              action: action,
              style: base.copyWith(
                color: ChromeThemeScope.actionOf(context).send,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _PanelActionButton extends StatelessWidget {
  const _PanelActionButton({required this.action, required this.style});

  final ComposerPanelAction action;
  final TextStyle style;

  static const _activate = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    label: action.label,
    onTap: action.onTap,
    excludeSemantics: true,
    child: FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      shortcuts: _activate,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            action.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(action.label, textAlign: TextAlign.center, style: style),
        ),
      ),
    ),
  );
}
