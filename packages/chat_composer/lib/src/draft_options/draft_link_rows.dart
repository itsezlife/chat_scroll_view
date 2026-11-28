import 'package:chat_composer/src/draft_options/draft_link_page.dart';
import 'package:chat_composer/src/draft_options/draft_link_page_policy.dart';
import 'package:chat_composer/src/draft_options/draft_options_key_focus.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The link page's rows as the draft options overlay draws them: one
/// [DraftLinkRowView] per row of [page], the separator and, where the policy
/// has it, the hint that a link can be chosen.
///
/// Labels come from the chrome strings and styles from the chrome
/// typography. The rows are at least the policy's width beyond the widest
/// label, and every row takes that width.
class DraftLinkRows extends StatelessWidget {
  /// The rows of [page].
  const DraftLinkRows({required this.page, super.key});

  /// The headless rows.
  final DraftLinkPage page;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: page.changes,
    builder: (context, _) {
      final policy = page.policy;
      final strings = ChromeStringsScope.composerOf(context).draftOptions;
      final palette = ChromeThemeScope.of(context).palette;
      final metrics = policy.rowMetrics;
      final style = ChromeTypography.of(
        context,
      ).copyWith(fontSize: metrics.fontSize);
      final rows = page.rows;
      final labels = [for (final row in rows) row.label.of(strings)];
      final separator = SizedBox(
        height: policy.separatorExtent,
        child: ColoredBox(
          color: palette.onSurface.withValues(alpha: policy.separatorOpacity),
        ),
      );
      // The gap sits between the toggles and the closing rows.
      final gapAt = rows.indexWhere(
        (row) =>
            row.row == DraftLinkRow.apply || row.row == DraftLinkRow.remove,
      );
      final children = <Widget>[
        if (policy.separator == DraftLinkSeparator.skipAbove) separator,
        for (final (i, row) in rows.indexed) ...[
          if (policy.separator == DraftLinkSeparator.gap && i == gapAt && i > 0)
            separator,
          DraftLinkRowView(
            state: row,
            label: labels[i],
            policy: policy,
            style: style,
            onTap: () => page.tap(row.row),
          ),
        ],
        if (page.showsLinkHint)
          Padding(
            padding:
                policy.linkHintPadding ??
                EdgeInsetsDirectional.only(
                  start: metrics.iconStart,
                  end: metrics.iconStart,
                  top: policy.separatorExtent,
                  bottom: policy.separatorExtent,
                ),
            child: Text(
              strings.chooseLinkHint,
              textAlign: policy.linkHintAlign,
              style: ChromeTypography.of(
                context,
              ).copyWith(color: palette.onSurfaceMuted),
            ),
          ),
      ];
      return IntrinsicWidth(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth:
                metrics.minWidthBeyondLabel + _widest(context, labels, style),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
    },
  );

  static double _widest(
    BuildContext context,
    List<String> labels,
    TextStyle style,
  ) {
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }
}

/// One row of the link page: its icon at the policy's start inset, its
/// label after it, pressed with the policy's ink; an inert row is faded and
/// takes its touch without feedback.
///
/// The icon animates a change of state through the chrome icon morph where
/// the policy has it; the label cross-fades over the policy's label change,
/// or changes at once.
/// In a right-to-left text the icon stands at the end. Under the policy's
/// keyboard focus the row takes focus and Enter or Space presses it.
class DraftLinkRowView extends StatelessWidget {
  /// A row showing [state] as [label].
  const DraftLinkRowView({
    required this.state,
    required this.label,
    required this.policy,
    required this.style,
    required this.onTap,
    super.key,
  });

  /// What the row shows.
  final DraftLinkRowState state;

  /// The label, from the chrome strings.
  final String label;

  /// The link page's rules: metrics, ink, motion.
  final DraftLinkPagePolicy policy;

  /// The label's style, from the chrome typography.
  final TextStyle style;

  /// The tap, inert or not: the headless page decides what it does.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.of(context).palette;
    final metrics = policy.rowMetrics;
    final destructive = state.row == DraftLinkRow.remove;
    final textColor = destructive ? palette.destructive : palette.onSurface;
    final iconColor = destructive ? palette.destructive : palette.iconIdle;
    final text = Text(
      label,
      key: ValueKey(state.label),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: style.copyWith(color: textColor),
    );
    final change = policy.labelChange;
    final shownLabel = change.duration == Duration.zero
        ? text
        : AnimatedSwitcher(
            duration: change.duration,
            switchInCurve: change.curve,
            switchOutCurve: change.curve,
            layoutBuilder: (current, previous) => Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [...previous, ?current],
            ),
            child: text,
          );
    final body = SizedBox(
      height: metrics.height,
      child: Stack(
        children: [
          PositionedDirectional(
            start: metrics.iconStart,
            top: (metrics.height - metrics.iconSize) / 2,
            child: policy.iconMorph
                ? AnimatedChromeIcon(
                    state.icon,
                    size: metrics.iconSize,
                    color: iconColor,
                  )
                : ChromeIcon(
                    state.icon,
                    size: metrics.iconSize,
                    color: iconColor,
                  ),
          ),
          PositionedDirectional(
            start: metrics.labelStart,
            end: metrics.iconStart,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: shownLabel,
            ),
          ),
        ],
      ),
    );
    final Widget pressable;
    if (state.inert) {
      // Faded and without feedback: the page ignores the touch.
      pressable = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(opacity: policy.inertOpacity, child: body),
      );
    } else {
      pressable = ChromeInk(
        kind: policy.ink,
        color: destructive
            ? palette.destructive.withValues(alpha: policy.removePressOpacity)
            : ChromeButtonInks.pressOf(palette),
        hoverColor: ChromeButtonInks.hoverOf(palette),
        onTap: onTap,
        child: body,
      );
    }
    return Semantics(
      button: true,
      enabled: !state.inert,
      label: label,
      excludeSemantics: true,
      onTap: state.inert ? null : onTap,
      child: policy.keyboardFocus
          ? DraftOptionsKeyFocus(
              enabled: !state.inert,
              onPressed: onTap,
              child: pressable,
            )
          : pressable,
    );
  }
}
