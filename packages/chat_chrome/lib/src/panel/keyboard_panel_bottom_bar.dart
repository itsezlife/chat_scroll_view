import 'package:chat_chrome/src/motion/scale_pressable.dart';
import 'package:chat_chrome/src/panel/backspace_action_button.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_allow.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_bottom_actions.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_labels.dart';
import 'package:chat_chrome/src/panel/emoji_tab_assets.dart';
import 'package:chat_chrome/src/panel/keyboard_panel_type_tabs_pill.dart';
import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Floating solid bottom chrome (text type tabs + trailing action).
///
/// Type pill shrink-wraps (`setShouldExpand(false)`). Selection indicator
/// follows [page] / settles like `PagerSlidingTabStrip` + `AnimatedFloat`.
/// Trailing action swaps with scale+fade (`showBackspaceButton` / 200ms).
class KeyboardPanelBottomBar extends StatelessWidget {
  /// Creates the floating bottom chrome.
  const KeyboardPanelBottomBar({
    required this.tabs,
    required this.page,
    required this.selectedTab,
    required this.labels,
    required this.actions,
    required this.onSelectTab,
    this.pageDragging = false,
    super.key,
  });

  /// Enabled type tabs.
  final List<KeyboardPanelTab> tabs;

  /// Continuous pager position (`PageController.page`).
  final double page;

  /// Settled pager tab (`onPageSelected`) — drives trailing action swap.
  final KeyboardPanelTab selectedTab;

  /// Host-localized tab titles.
  final KeyboardPanelLabels labels;

  /// Per-tab trailing actions.
  final KeyboardPanelBottomActions actions;

  /// True while the user is dragging the [PageView].
  final bool pageDragging;

  /// Selects a type tab.
  final ValueChanged<int> onSelectTab;

  /// Layout host height (pill + bottom pad).
  static const double height = 48;

  /// Type-tab strip height inside the pill.
  static const double stripHeight = 36;

  /// Trailing action paint diameter.
  static const double actionSize = 36;

  /// Drawn action icon.
  static const double iconSize = 22;

  /// Horizontal inset from panel edges.
  static const double padH = 8;

  /// Space under the floating controls.
  static const double padBottom = 4;

  /// Absolute hide slide (`lerp(dp(45), …)` when visibility → 0).
  static const double hideSlide = 45;

  /// Alias kept for callers.
  static const double hideTranslation = hideSlide;

  /// Scroll distance before toggle (`checkBottomTabScroll` emoji page).
  static const double scrollToggleOffset = 38;

  /// Hide/show duration (`BoolAnimator` EASE_OUT_QUINT).
  static const Duration visibilityDuration = Duration(milliseconds: 380);

  /// Indicator settle (`AnimatedFloat` 350 / EASE_OUT_QUINT).
  static const Duration indicatorDuration = Duration(milliseconds: 350);

  /// Trailing action swap (`showBackspaceButton` / EASE_OUT).
  static const Duration actionSwapDuration = Duration(milliseconds: 200);

  /// Indicator expands past text bounds (`lineLeft - dp(11)`).
  static const double indicatorPad = 11;

  @override
  Widget build(BuildContext context) {
    final colors = ChatChromeTheme.of(context);
    final showTypeTabs = tabs.length > 1;
    final action = actions.forTab(selectedTab);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(padH, 0, padH, padBottom),
        child: Stack(
          children: <Widget>[
            if (showTypeTabs)
              Align(
                alignment: Alignment.bottomCenter,
                child: KeyboardPanelTypeTabsPill(
                  tabs: tabs,
                  page: page,
                  pageDragging: pageDragging,
                  labels: labels,
                  onSelectTab: onSelectTab,
                  fill: colors.panelFloatingFill,
                  indicator: colors.panelFloatingSelected,
                  activeText: colors.panelFloatingText,
                  idleText: colors.panelFloatingTextMuted,
                ),
              ),
            Align(
              alignment: Alignment.bottomRight,
              child: _AnimatedActionSlot(
                action: action,
                fill: colors.panelFloatingFill,
                iconColor: colors.panelFloatingText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedActionSlot extends StatelessWidget {
  const _AnimatedActionSlot({
    required this.action,
    required this.fill,
    required this.iconColor,
  });

  final KeyboardPanelBottomAction? action;
  final Color fill;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: KeyboardPanelBottomBar.actionSize,
      height: KeyboardPanelBottomBar.actionSize,
      child: AnimatedSwitcher(
        duration: KeyboardPanelBottomBar.actionSwapDuration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeOut,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: animation, child: child),
        ),
        child: action == null
            ? const SizedBox.shrink(key: ValueKey<String>('none'))
            : _ActionButton(
                key: ValueKey<String>(action!.iconAsset),
                action: action!,
                fill: fill,
                iconColor: iconColor,
              ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.fill,
    required this.iconColor,
    super.key,
  });

  final KeyboardPanelBottomAction action;
  final Color fill;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final icon = Semantics(
      label: action.semanticsLabel,
      button: true,
      child: Image.asset(
        action.iconAsset,
        package: EmojiTabAssets.package,
        width: KeyboardPanelBottomBar.iconSize,
        height: KeyboardPanelBottomBar.iconSize,
        color: iconColor,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
      ),
    );

    final cell = SizedBox(
      width: KeyboardPanelBottomBar.actionSize,
      height: KeyboardPanelBottomBar.actionSize,
      child: Material(
        color: fill,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Center(child: icon),
      ),
    );

    if (action.repeatOnHold) {
      return BackspaceActionButton(onBackspace: action.onPressed, child: cell);
    }

    return ScalePressable(
      onPressed: () {
        HapticFeedback.selectionClick();
        action.onPressed();
      },
      child: cell,
    );
  }
}
