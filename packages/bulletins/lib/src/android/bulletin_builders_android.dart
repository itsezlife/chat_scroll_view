import 'dart:async';
import 'dart:math' as math;

import 'package:bulletins/src/bulletin/bulletin.dart';
import 'package:bulletins/src/controller/bulletin_controller.dart';
import 'package:bulletins/src/view/bulletin_builders.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Builds a bulletin's message as a span, for a message with links: the
/// reference draws them in the accent and opens them on tap. [linkStyle]
/// carries the accent; the span inherits the message's size and colour.
typedef BulletinMessageBuilder =
    InlineSpan Function(
      BuildContext context,
      BulletinView view,
      TextStyle linkStyle,
    );

/// The reference Android client's bulletin card (`Bulletin.Layout` and its
/// `LottieLayout`, `TwoLineLayout` and `ButtonLayout` variants), as a set of
/// `BulletinBuilders` for a host on the Android policy.
///
/// [create] gives the whole set: the card in the undo background, or glass
/// tinted with it where the surface is a chat (the reference turns the
/// card to glass only there); the leading slot of each kind; the title over
/// the message; and the Undo or button in the accent. Sizes not owned by
/// the policy (the slot boxes, the text insets, the button paddings) are the
/// reference's own and fixed here.
abstract final class BulletinBuilders$Android {
  // --- Metrics (the reference, in dp; the card is the drawn background) ---

  /// The leading box of the Lottie and simple layouts, from the card's start
  /// edge: 56 by 48 (B:1979, the simple layout's 24 icon with 16 / 12
  /// margins, B:1356).
  static const double _slotWidth = 56;
  static const double _slotHeight = 48;

  /// A Lottie icon's size in its box (`setAnimation(resId)`, B:2035); the
  /// copy and link icons use 36 and are drawn by a custom leading.
  static const double _animationSize = 32;

  /// The two-line layout's sticker or photo: 29 square at 12 from the start,
  /// 12 above and below (B:1405); its text block starts at 54 (B:1409).
  static const double _thumbnailSize = 29;
  static const double _thumbnailInset = 12;
  static const double _thumbnailTextStart = 54;

  /// The undo countdown: 20 square at 21 from the start (B:1337).
  static const double _countdownSize = 20;
  static const double _countdownStart = 21;

  /// The text's start without a leading (BF:442), its end without a button
  /// (one line B:2004; under a title 8 + 4 of text padding, B:1458), and its
  /// vertical padding (B:2003, B:1458).
  static const double _textStart = 16;
  static const double _textEnd = 16;
  static const double _titledTextEnd = 12;
  static const double _textVertical = 8;

  /// A button's measured width counts 12 less against the text (B:1300), so
  /// the text's end inset reaches 12 into the button's box.
  static const double _buttonOverlap = 12;

  /// A message beside a custom button: 14, up to three lines (BF:445-449).
  static const double _buttonMessageSize = 14;

  /// The weight of `AndroidUtilities.bold()`: the medium face (500).
  static const FontWeight _medium = FontWeight.w500;

  // --- The set ---

  /// The Android builders. [glass] draws the card as glass over the surface
  /// (a chat), otherwise it is the opaque undo background. [animation] and
  /// [thumbnail] resolve the opaque sources of those leading kinds (a Lottie
  /// from the asset cache, a sticker); [message] draws a message with links.
  static BulletinBuilders create({
    bool glass = false,
    BulletinSourceBuilder? animation,
    BulletinSourceBuilder? thumbnail,
    BulletinMessageBuilder? message,
  }) => BulletinBuilders(
    frame: glass ? glassFrame : frame,
    content: (context, view) => content(
      context,
      view,
      animation: animation,
      thumbnail: thumbnail,
      message: message,
    ),
    animation: animation,
    thumbnail: thumbnail,
  );

  // --- Frame ---

  /// The opaque card: the undo background (0xEA272F38 by default), the
  /// policy's radius and minimum height (`createRoundRectDrawable`, B:811).
  static Widget frame(BuildContext context, BulletinView view, Widget child) =>
      BulletinBuilders.stockFrame(context, view, child);

  /// The card as glass, as the reference's chat draws it (ChatActivity
  /// `onShow`, the `bulletin()` provider in `BlurredBackgroundProviderImpl`):
  /// the undo background over the blurred surface, at the glass's own
  /// opacity (0.76 frosted, 0.85 refracting, multiplied by the colour's
  /// alpha); no edge stroke and no shadow, as that provider leaves their
  /// colours unset.
  ///
  /// The glass stack has no bulletin material, so the card borrows the
  /// floating-button material, whose 0.5 edge width is the provider's, and
  /// recolours it in a nested theme scope. Adding a material to the
  /// foundation for one card would change every host's glass group.
  static Widget glassFrame(
    BuildContext context,
    BulletinView view,
    Widget child,
  ) {
    const none = Color(0x00000000);
    final glass = ChromeThemeScope.glassOf(context);
    return ChromeThemeScope(
      glass: glass.copyWith(
        panelButton: GlassMaterialColors(
          tint: view.tokens.background,
          strokeTop: none,
          strokeBottom: none,
          shadow: none,
        ),
      ),
      child: GlassSurface(
        material: GlassMaterial.panelButton,
        cornerRadius: view.policy.cornerRadius,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: view.policy.minHeight),
          child: child,
        ),
      ),
    );
  }

  // --- Content ---

  /// The leading slot, the title over the message, and the action, laid out
  /// as the reference's layouts place them.
  static Widget content(
    BuildContext context,
    BulletinView view, {
    BulletinSourceBuilder? animation,
    BulletinSourceBuilder? thumbnail,
    BulletinMessageBuilder? message,
  }) {
    final bulletin = view.bulletin;
    final policy = view.policy;
    final foreground = view.tokens.foreground;
    final title = bulletin.title;
    final action = bulletin.action;

    final messageSize = switch ((title, action)) {
      (_?, _) => policy.subtitleTextSize,
      (null, BulletinAction$Button()) => _buttonMessageSize,
      (null, _) => policy.messageTextSize,
    };
    // An undo message wraps to two lines (BF:532), one beside a button to
    // three (BF:448); a subtitle to two (B:1416).
    final maxLines =
        bulletin.maxLines ??
        switch ((title, action)) {
          (_?, _) => 2,
          (null, BulletinAction$Undo()) => 2,
          (null, BulletinAction$Button()) => 3,
          (null, null) => 1,
        };
    final messageStyle = TextStyle(color: foreground, fontSize: messageSize);
    final text = ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _textVertical),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title case final title?)
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: policy.titleTextSize,
                  fontWeight: _medium,
                ),
              ),
            switch (message) {
              final message? => Text.rich(
                message(context, view, TextStyle(color: view.tokens.accent)),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: messageStyle,
              ),
              null => Text(
                bulletin.message,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: messageStyle,
              ),
            },
          ],
        ),
      ),
    );

    final end = title == null ? _textEnd : _titledTextEnd;
    return Row(
      children: [
        _leading(context, view, animation: animation, thumbnail: thumbnail),
        Expanded(child: text),
        if (action == null)
          SizedBox(width: end)
        else ...[
          SizedBox(width: math.max(0, end - _buttonOverlap)),
          _ActionButton$Android(view: view),
        ],
      ],
    );
  }

  static Widget _leading(
    BuildContext context,
    BulletinView view, {
    required BulletinSourceBuilder? animation,
    required BulletinSourceBuilder? thumbnail,
  }) {
    Widget slot(Widget? child) => SizedBox(
      width: _slotWidth,
      height: _slotHeight,
      child: Center(child: child),
    );
    return switch (view.bulletin.leading) {
      null => const SizedBox(width: _textStart),
      BulletinLeading$Icon(:final icon) => slot(
        ChromeIcon(
          icon,
          size: view.policy.iconSize,
          color: view.tokens.foreground,
        ),
      ),
      BulletinLeading$Animation(:final source) => slot(
        SizedBox.square(
          dimension: _animationSize,
          child: animation?.call(context, source, view),
        ),
      ),
      BulletinLeading$Thumbnail(:final source) => Padding(
        padding: const EdgeInsetsDirectional.only(
          start: _thumbnailInset,
          top: _thumbnailInset,
          bottom: _thumbnailInset,
          end: _thumbnailTextStart - _thumbnailInset - _thumbnailSize,
        ),
        child: SizedBox.square(
          dimension: _thumbnailSize,
          child: thumbnail?.call(context, source, view),
        ),
      ),
      BulletinLeading$Countdown() => SizedBox(
        width: _slotWidth,
        height: _slotHeight,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: _countdownStart),
            child: BulletinCountdown$Android(
              handle: view.handle,
              color: view.tokens.countdown,
            ),
          ),
        ),
      ),
      BulletinLeading$Custom(:final builder) => slot(builder(context)),
    };
  }
}

// --- Action ---

/// The reference's `UndoButton` with text (B:2256-2263): the label 14 medium
/// in the accent, padded 12 / 8 inside a box 8 from its neighbours, with a
/// 6-radius highlight of the accent at 0x19 while pressed (the ripple's
/// colour and mask). A custom button is the same with its own label
/// (BF:450).
class _ActionButton$Android extends StatefulWidget {
  const _ActionButton$Android({required this.view});

  final BulletinView view;

  @override
  State<_ActionButton$Android> createState() => _ActionButton$AndroidState();
}

class _ActionButton$AndroidState extends State<_ActionButton$Android> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (pressed == _pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final label = switch (view.bulletin.action) {
      BulletinAction$Undo() => view.strings.undoAction,
      BulletinAction$Button(:final label) => label,
      null => '',
    };
    final accent = view.tokens.accent;
    // A pointer listener, not the tap's down callback: the card's horizontal
    // drag shares the arena, which holds a tap down back until it resolves,
    // while the reference shows its pressed state at once.
    return Semantics(
      button: true,
      child: Listener(
        onPointerDown: (_) => _press(true),
        onPointerUp: (_) => _press(false),
        onPointerCancel: (_) => _press(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: view.handle.pressAction,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: accent.withAlpha(_pressed ? 0x19 : 0),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: BulletinBuilders$Android._medium,
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

// --- Countdown ---

/// The reference's undo `TimerView` (B:2360-2455): a 20 ring, 2 wide with
/// round caps, inset by 1, that empties counter-clockwise from the top over
/// the time left, with the whole seconds left in 12 digits inside. When the
/// second changes the old digit slides 10 down and fades while the new one
/// slides in from 10 above, over about 150 ms (16/150 of the way per
/// frame).
///
/// Reads the handle's remaining time every frame while mounted. Draws
/// nothing for a bulletin without a timeout.
class BulletinCountdown$Android extends StatefulWidget {
  /// The countdown of [handle] in [color].
  const BulletinCountdown$Android({
    required this.handle,
    required this.color,
    super.key,
  });

  /// The bulletin counted down.
  final BulletinHandle handle;

  /// The ring and digit colour (the reference's info colour).
  final Color color;

  /// How long a digit change takes.
  static const Duration digitChange = Duration(milliseconds: 150);

  /// How far a changing digit slides.
  static const double digitSlide = 10;

  @override
  State<BulletinCountdown$Android> createState() =>
      _BulletinCountdown$AndroidState();
}

class _BulletinCountdown$AndroidState extends State<BulletinCountdown$Android>
    with SingleTickerProviderStateMixin {
  late final Ticker _$ticker;
  Duration _$now = Duration.zero;
  int? _$seconds;
  int? _$previous;
  Duration _$changedAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _$ticker = createTicker((elapsed) => setState(() => _$now = elapsed));
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
    final seconds = math.max(0, (remaining.inMilliseconds / 1000).ceil());
    if (seconds != _$seconds) {
      // The first value appears without a change, as the reference's first
      // frame has no outgoing layout.
      _$previous = _$seconds;
      _$seconds = seconds;
      _$changedAt = _$now;
    }
    final instant = ChromeMotionScope.of(context).speed.isInstant;
    final progress = instant
        ? 1.0
        : ((_$now - _$changedAt).inMicroseconds /
                  BulletinCountdown$Android.digitChange.inMicroseconds)
              .clamp(0.0, 1.0);
    final fraction = remaining.inMicroseconds / timeout.inMicroseconds;
    final style = TextStyle(
      color: widget.color,
      fontSize: 12,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1,
    );
    const slide = BulletinCountdown$Android.digitSlide;
    Widget digit(int value, double opacity, double dy) => Transform.translate(
      // The reference lifts its digits by half a point.
      offset: Offset(0, dy - 0.5),
      child: Opacity(
        opacity: opacity,
        child: Text('$value', style: style),
      ),
    );
    return SizedBox.square(
      dimension: BulletinBuilders$Android._countdownSize,
      child: CustomPaint(
        painter: _RingPainter(fraction: fraction, color: widget.color),
        child: Stack(
          alignment: Alignment.center,
          children: switch (_$previous) {
            final previous? when progress < 1 => [
              digit(previous, 1 - progress, slide * progress),
              digit(seconds, progress, -slide * (1 - progress)),
            ],
            _ => [digit(seconds, 1, 0)],
          },
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
    final rect = (Offset.zero & size).deflate(1);
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
