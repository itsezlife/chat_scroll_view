import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_shell/src/page/panel_page.dart';
import 'package:panel_shell/src/widgets/hold_repeat_button.dart';
import 'package:panel_shell/src/widgets/panel_type_tabs.dart';

/// What the bottom bar asks of the shell when the user triggers an action.
typedef PanelActionHandler = void Function(PanelPage page, PageAction action);

/// The floating bottom chrome: the type tabs pill at the center and the
/// action row of the selected page at the end side.
///
/// Layout is directional: the action row sits at the end side of the reading
/// direction and the tabs are ordered start to end. Text is clamped to a
/// maximum scale because the pill has a fixed height.
class PanelBottomBar extends StatelessWidget {
  /// A bar for [pages] with [selected] showing its actions.
  const PanelBottomBar({
    required this.pages,
    required this.selected,
    required this.position,
    required this.dragging,
    required this.display,
    required this.onAction,
    super.key,
  });

  /// All pages, for the tabs.
  final List<PanelPage> pages;

  /// The selected page, whose actions the row shows.
  final PanelPage selected;

  /// The pager's continuous page.
  final ValueListenable<double> position;

  /// Whether the pager is between pages.
  final ValueListenable<bool> dragging;

  /// Whether tabs show names or icons.
  final PanelTabDisplay display;

  /// Called when the user triggers an action.
  final PanelActionHandler onAction;

  /// Layout height of the bar (pill plus the space under it).
  static const double height = 48;

  /// Diameter of an action button.
  static const double actionSize = 36;

  /// Size of an action icon.
  static const double iconSize = 22;

  /// Inset from the panel edges.
  static const double padHorizontal = 8;

  /// Space under the floating controls.
  static const double padBottom = 4;

  /// How far the bar slides down to hide, before the safe inset.
  static const double hideSlide = 45;

  /// Largest text scale the fixed-height controls honour.
  static const double maxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final showTabs = pages.length > 1;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            padHorizontal,
            0,
            padHorizontal,
            padBottom,
          ),
          child: Stack(
            children: [
              if (showTabs)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: PanelTypeTabs(
                    pages: pages,
                    position: position,
                    dragging: dragging,
                    selectedPageId: selected.id,
                    display: display,
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: _ActionRow(page: selected, onAction: onAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.page, required this.onAction});

  final PanelPage page;
  final PanelActionHandler onAction;

  @override
  Widget build(BuildContext context) {
    final fade = ChromeMotionScope.of(context).specOf(MotionRole.fade);
    return AnimatedSwitcher(
      duration: fade.duration,
      switchInCurve: fade.curve,
      switchOutCurve: fade.curve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Row(
        key: ValueKey<String>(page.id),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in page.capabilities.actions)
            _ActionButton(
              action: action,
              onTrigger: () => onAction(page, action),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.onTrigger});

  final PageAction action;
  final VoidCallback onTrigger;

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.actionOf(context);
    final label = action.semanticLabel(ChromeStringsScope.of(context));
    final cell = SizedBox.square(
      dimension: PanelBottomBar.actionSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.floatingFill,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: ChromeIcon(
            action.icon,
            size: PanelBottomBar.iconSize,
            color: tokens.floatingLabel,
          ),
        ),
      ),
    );
    if (action.repeatOnHold) {
      return HoldRepeatButton(
        onTrigger: onTrigger,
        semanticLabel: label,
        child: cell,
      );
    }
    return Semantics(
      button: true,
      label: label,
      onTap: onTrigger,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTrigger();
              return null;
            },
          ),
        },
        child: ExcludeSemantics(
          child: ScalePressable(onPressed: onTrigger, child: cell),
        ),
      ),
    );
  }
}
