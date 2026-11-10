import 'dart:async';
import 'dart:math' as math;

import 'package:bulletins/src/bulletin/bulletin.dart';
import 'package:bulletins/src/controller/bulletin_controller.dart';
import 'package:bulletins/src/policy/bulletin_policy.dart';
import 'package:bulletins/src/view/bulletin_message.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What a builder draws a bulletin from: its handle, the surface's policy,
/// and the colours and labels in scope.
@immutable
final class BulletinView {
  /// The view of [handle] under [policy], [tokens] and [strings].
  const BulletinView({
    required this.handle,
    required this.policy,
    required this.tokens,
    required this.strings,
  });

  /// The bulletin's handle: its timer, its action and its dismissal.
  final BulletinHandle handle;

  /// The surface's policy: metrics and text sizes.
  final BulletinPolicy policy;

  /// The bulletin colours in scope.
  final BulletinTokens tokens;

  /// The bulletin labels in scope.
  final BulletinStrings strings;

  /// The bulletin shown.
  Bulletin get bulletin => handle.bulletin;
}

/// Wraps a bulletin's content in its surface: shape, fill, glass, blur.
typedef BulletinFrameBuilder =
    Widget Function(BuildContext context, BulletinView view, Widget child);

/// Builds one part of a bulletin (its content, leading or action).
typedef BulletinPartBuilder =
    Widget Function(BuildContext context, BulletinView view);

/// Builds what an opaque leading source stands for (an animation, a
/// thumbnail).
typedef BulletinSourceBuilder =
    Widget Function(BuildContext context, Object source, BulletinView view);

/// How a bulletin host draws a bulletin: one builder per part, each
/// replaceable.
///
/// A null builder uses the stock one: [stockFrame], [stockContent],
/// [stockLeading] and [stockAction] paint with the token group and the
/// policy's metrics, flat. A host builder may wrap a stock one by calling
/// it. [animation] and [thumbnail] have no stock: they resolve the sources of
/// [BulletinLeading.animation] and [BulletinLeading.thumbnail], and without
/// them the leading slot keeps its size and stays empty.
@immutable
final class BulletinBuilders {
  /// Builders where each one given replaces the stock one.
  const BulletinBuilders({
    this.frame,
    this.content,
    this.leading,
    this.action,
    this.animation,
    this.thumbnail,
  });

  /// The card's surface around the content.
  final BulletinFrameBuilder? frame;

  /// Everything inside the frame.
  final BulletinPartBuilder? content;

  /// The leading slot's content.
  final BulletinPartBuilder? leading;

  /// The action button.
  final BulletinPartBuilder? action;

  /// Plays the source of a [BulletinLeading.animation].
  final BulletinSourceBuilder? animation;

  /// Draws the source of a [BulletinLeading.thumbnail].
  final BulletinSourceBuilder? thumbnail;

  /// A copy with the named builders replaced.
  BulletinBuilders copyWith({
    BulletinFrameBuilder? frame,
    BulletinPartBuilder? content,
    BulletinPartBuilder? leading,
    BulletinPartBuilder? action,
    BulletinSourceBuilder? animation,
    BulletinSourceBuilder? thumbnail,
  }) => BulletinBuilders(
    frame: frame ?? this.frame,
    content: content ?? this.content,
    leading: leading ?? this.leading,
    action: action ?? this.action,
    animation: animation ?? this.animation,
    thumbnail: thumbnail ?? this.thumbnail,
  );

  // --- Stock builders ---

  /// A flat card: the token background, the policy's corner radius and
  /// minimum height.
  static Widget stockFrame(
    BuildContext context,
    BulletinView view,
    Widget child,
  ) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: view.policy.minHeight),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: view.tokens.background,
        borderRadius: BorderRadius.circular(view.policy.cornerRadius),
      ),
      child: child,
    ),
  );

  /// The leading slot, the title over the message, and the action, in a row
  /// padded by the policy's content padding.
  static Widget stockContent(
    BuildContext context,
    BulletinView view,
    BulletinBuilders builders,
  ) {
    final bulletin = view.bulletin;
    final policy = view.policy;
    final foreground = view.tokens.foreground;
    final text = ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bulletin.title case final title?)
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: policy.titleTextSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          BulletinMessage(
            message: bulletin.message,
            links: bulletin.links,
            linkColor: view.tokens.accent,
            maxLines: bulletin.effectiveMaxLines,
            style: TextStyle(
              color: foreground,
              fontSize: bulletin.title == null
                  ? policy.messageTextSize
                  : policy.subtitleTextSize,
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: policy.contentPadding,
      child: Row(
        children: [
          if (bulletin.leading != null)
            BulletinLeadingSlot(
              width: policy.leadingWidth,
              child: (builders.leading ?? _leadingWith(builders))(
                context,
                view,
              ),
            ),
          Expanded(child: text),
          if (bulletin.action != null)
            (builders.action ?? stockAction)(context, view),
        ],
      ),
    );
  }

  static BulletinPartBuilder _leadingWith(BulletinBuilders builders) =>
      (context, view) => stockLeading(context, view, builders);

  /// The stock leading of each kind: a tinted chrome icon, the host's
  /// animation or thumbnail (empty without a builder), the countdown ring,
  /// or the caller's custom widget.
  static Widget stockLeading(
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
        dimension: size,
        child: builders.thumbnail?.call(context, source, view),
      ),
      BulletinLeading$Countdown() => BulletinCountdown(
        handle: view.handle,
        color: view.tokens.countdown,
        size: size,
      ),
      BulletinLeading$Custom(:final builder) => builder(context),
      null => const SizedBox.shrink(),
    };
  }

  /// The action as accent text: Undo labelled from the strings, a button
  /// with its own label. Pressing it presses the handle's action.
  static Widget stockAction(BuildContext context, BulletinView view) {
    final label = switch (view.bulletin.action) {
      BulletinAction$Undo() => view.strings.undoAction,
      BulletinAction$Button(:final label) => label,
      null => null,
    };
    if (label == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: view.handle.pressAction,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: view.tokens.accent,
              fontSize: view.policy.titleTextSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// The fixed-width slot before a bulletin's text; its content is centred
/// across the slot and is as tall as its content, so a card whose height is
/// not fixed (the desktop toast) stays as tall as its text.
class BulletinLeadingSlot extends StatelessWidget {
  /// A slot [width] wide around [child].
  const BulletinLeadingSlot({
    required this.width,
    required this.child,
    super.key,
  });

  /// The slot's width.
  final double width;

  /// What fills the slot.
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Center(heightFactor: 1, child: child),
  );
}

/// A ring that empties over a bulletin's time left, with the whole seconds
/// left inside it. Draws nothing for a bulletin without a timeout.
///
/// Reads the handle's remaining time every frame while mounted.
class BulletinCountdown extends StatefulWidget {
  /// A countdown of [handle] in [color], [size] square.
  const BulletinCountdown({
    required this.handle,
    required this.color,
    required this.size,
    super.key,
  });

  /// The bulletin counted down.
  final BulletinHandle handle;

  /// The ring and digit colour.
  final Color color;

  /// The ring's diameter.
  final double size;

  @override
  State<BulletinCountdown> createState() => _BulletinCountdownState();
}

class _BulletinCountdownState extends State<BulletinCountdown>
    with SingleTickerProviderStateMixin {
  late final Ticker _$ticker;

  @override
  void initState() {
    super.initState();
    _$ticker = createTicker((_) => setState(() {}));
    unawaited(_$ticker.start());
  }

  @override
  void dispose() {
    _$ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle;
    final (timeout, remaining) = (handle.timeout, handle.remaining);
    if (timeout == null || remaining == null) return const SizedBox.shrink();
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final fraction = remaining.inMicroseconds / timeout.inMicroseconds;
    return SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _RingPainter(fraction: fraction, color: widget.color),
        child: Center(
          child: Text(
            '$seconds',
            style: TextStyle(
              color: widget.color,
              fontSize: widget.size / 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    // Starts at the top and empties counter-clockwise.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      -2 * math.pi * fraction.clamp(0, 1),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}
