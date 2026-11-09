import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:bulletins/src/bulletin/bulletin.dart';
import 'package:bulletins/src/ios/bulletin_countdown_ios.dart';
import 'package:bulletins/src/view/bulletin_builders.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The reference iOS client's undo overlay drawn as a bulletin: the builders
/// that go with `BulletinPolicy.ios()`.
///
/// A dark blurred card with continuous corners; the leading in a slot at the
/// card's edge and the text right after it, title over message, every line
/// 14; the action as a 17 label in the accent that dims while pressed, its
/// hit area the card's full height from just before the label to the edge.
/// Metrics come from the policy, colours from the `BulletinTokens` in scope.
///
/// Line numbers are in the reference's
/// `submodules/UndoUI/Sources/UndoOverlayControllerNode.swift`.
abstract final class BulletinIOS {
  /// The builders of the iOS card.
  ///
  /// [animation] and [thumbnail] resolve the sources of an animation and a
  /// thumbnail leading, as on [BulletinBuilders]; pass them here, since the
  /// content builder lays the leading out with them. [tint] and [blurSigma]
  /// are the [frame]'s.
  static BulletinBuilders builders({
    BulletinSourceBuilder? animation,
    BulletinSourceBuilder? thumbnail,
    Color? tint,
    double blurSigma = BulletinIOS.blurSigma,
  }) {
    late final BulletinBuilders built;
    return built = BulletinBuilders(
      frame: (context, view, child) =>
          frame(context, view, child, tint: tint, blurSigma: blurSigma),
      content: (context, view) => content(context, view, built),
      animation: animation,
      thumbnail: thumbnail,
    );
  }

  // --- Frame ---

  /// The blur behind a translucent card.
  ///
  /// The reference draws `UIBlurEffect(style: .dark)` (:1580), a system
  /// material whose recipe is not in its checkout; this and [blurTint]
  /// approximate it.
  static const double blurSigma = 20;

  /// The dark tint over the blur; see [blurSigma].
  static const Color blurTint = Color(0xBF1C1C1E);

  /// The card's surface: the blurred backdrop under a tint, clipped to the
  /// policy's corner radius with continuous corners (:1576, :1700), at least
  /// the policy's minimum height.
  ///
  /// The tint is [tint] when given. Otherwise it is the token background
  /// when that is opaque (a high-contrast card, which no blur would show
  /// through), and [blurTint] over the blur when it is not: the token
  /// group's stock background is the Android card's fill and would hide the
  /// blur the iOS card is.
  static Widget frame(
    BuildContext context,
    BulletinView view,
    Widget child, {
    Color? tint,
    double blurSigma = BulletinIOS.blurSigma,
  }) {
    final background = view.tokens.background;
    final fill = tint ?? (background.a == 1 ? background : blurTint);
    Widget card = ColoredBox(
      color: fill,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: view.policy.minHeight),
        child: child,
      ),
    );
    if (fill.a < 1 && blurSigma > 0) {
      card = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: card,
      );
    }
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(view.policy.cornerRadius),
      child: card,
    );
  }

  // --- Content ---

  /// The most lines a message takes when the bulletin names none: the
  /// reference's usual cap (:265, :941, :1154). The title has none (:102).
  static const int maxLines = 5;

  /// The space between the title and the message (:1985).
  static const double titleGap = 1;

  /// The space after the text when there is no action: the reference keeps
  /// the text 8 short of where a button would start and measures from the
  /// margin twice (:1940-1944, :1949), which leaves 12.
  static const double textEndInset = 12;

  /// The space between the text and the action's hit area; with the hit
  /// area's own 8 before its label, the text ends 20 before the label
  /// (:1949, :2023).
  static const double actionGap = 12;

  /// The leading slot from the card's edge, the text centred on the card's
  /// height with the policy's vertical padding around it, and the action.
  ///
  /// Without a leading the text starts at the policy's left padding, a case
  /// the reference does not have (every overlay there has an icon).
  static Widget content(
    BuildContext context,
    BulletinView view,
    BulletinBuilders builders,
  ) {
    final bulletin = view.bulletin;
    final policy = view.policy;
    final padding = policy.contentPadding;
    final foreground = view.tokens.foreground;
    final text = ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bulletin.title case final title?) ...[
            Text(
              title,
              style: TextStyle(
                color: foreground,
                fontSize: policy.titleTextSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: titleGap),
          ],
          Text(
            bulletin.message,
            maxLines: bulletin.maxLines ?? maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: bulletin.title == null
                  ? policy.messageTextSize
                  : policy.subtitleTextSize,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
    final leadingBuilder =
        builders.leading ??
        (BuildContext context, BulletinView view) =>
            leading(context, view, builders);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bulletin.leading != null)
            BulletinLeadingSlot(
              width: policy.leadingWidth,
              child: leadingBuilder(context, view),
            )
          else
            SizedBox(width: padding.left),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: padding.top,
                bottom: padding.bottom,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: text,
              ),
            ),
          ),
          if (bulletin.action != null) ...[
            const SizedBox(width: actionGap),
            (builders.action ?? action)(context, view),
          ] else
            const SizedBox(width: textEndInset),
        ],
      ),
    );
  }

  // --- Leading ---

  /// The fitting box of a thumbnail leading (:902).
  static const double thumbnailSize = 34;

  /// The diameter of the countdown ring (:2156).
  static const double countdownSize = 30;

  /// Each leading kind at its reference size: an icon and an animation in
  /// the policy's icon size (an animated leading's 32, :2138), a thumbnail in
  /// [thumbnailSize], the countdown ring in [countdownSize] with its digits.
  static Widget leading(
    BuildContext context,
    BulletinView view,
    BulletinBuilders builders,
  ) {
    final size = view.policy.iconSize;
    return switch (view.bulletin.leading) {
      BulletinLeading$Icon(:final icon) => ChromeIcon(
        icon,
        size: size,
        color: view.tokens.foreground,
      ),
      BulletinLeading$Animation(:final source) => SizedBox.square(
        dimension: size,
        child: builders.animation?.call(context, source, view),
      ),
      BulletinLeading$Thumbnail(:final source) => SizedBox.square(
        dimension: thumbnailSize,
        child: builders.thumbnail?.call(context, source, view),
      ),
      BulletinLeading$Countdown() => BulletinCountdownIOS(
        handle: view.handle,
        color: view.tokens.countdown,
        size: countdownSize,
      ),
      BulletinLeading$Custom(:final builder) => builder(context),
      null => const SizedBox.shrink(),
    };
  }

  // --- Action ---

  /// The action label's text size (:1565).
  static const double actionTextSize = 17;

  /// The hit area before the action label (:2024).
  static const double actionLead = 8;

  /// The action: Undo labelled from the strings or a button's own label, 17
  /// regular in the accent, ending at the policy's right padding. Its hit
  /// area runs the card's full height from [actionLead] before the label to
  /// the card's edge (:2024). While pressed the label is at 0.4 opacity
  /// and returns to 1 over 0.2 s on release (:1655-1663).
  static Widget action(BuildContext context, BulletinView view) {
    final label = switch (view.bulletin.action) {
      BulletinAction$Undo() => view.strings.undoAction,
      BulletinAction$Button(:final label) => label,
      null => null,
    };
    if (label == null) return const SizedBox.shrink();
    return _ActionIOS(view: view, label: label);
  }
}

class _ActionIOS extends StatefulWidget {
  const _ActionIOS({required this.view, required this.label});

  final BulletinView view;
  final String label;

  @override
  State<_ActionIOS> createState() => _ActionIOSState();
}

class _ActionIOSState extends State<_ActionIOS>
    with SingleTickerProviderStateMixin {
  static const double _pressedOpacity = 0.4;

  late final AnimationController _$opacity = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    lowerBound: _pressedOpacity,
    value: 1,
  );

  @override
  void dispose() {
    _$opacity.dispose();
    super.dispose();
  }

  // The reference sets the dim at once on touch down and animates only the
  // way back, with Core Animation's default ease-in-ease-out.
  void _down() => _$opacity
    ..stop()
    ..value = _pressedOpacity;

  void _up() => unawaited(
    _$opacity
        .animateTo(1, curve: Curves.easeInOut)
        .orCancel
        .then((_) {}, onError: (_) {}),
  );

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    return Semantics(
      button: true,
      child: Listener(
        onPointerDown: (_) => _down(),
        onPointerUp: (_) => _up(),
        onPointerCancel: (_) => _up(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: view.handle.pressAction,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              start: BulletinIOS.actionLead,
              end: view.policy.contentPadding.right,
            ),
            child: Center(
              child: AnimatedBuilder(
                animation: _$opacity,
                builder: (context, child) =>
                    Opacity(opacity: _$opacity.value, child: child),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: view.tokens.accent,
                    fontSize: BulletinIOS.actionTextSize,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
