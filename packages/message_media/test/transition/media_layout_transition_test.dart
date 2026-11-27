/// The transition policy's per-platform values and one leg's frames:
/// move, enter, exit, the move delay, and a leg started mid-flight.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatMessageChangeParams;
import 'package:content_model/content_model.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

MediaCell _cell(String id, Rect rect, {double radius = 0}) => MediaCell(
  itemId: MediaItemId(id),
  kind: MediaItemKind.photo,
  rect: rect,
  fit: const MediaFit.crop(),
  neighbours: MediaNeighbours.bubble,
  radii: MediaCornerRadii.all(radius),
);

MediaLayout _layout(List<MediaCell> cells) {
  final bounds = cells
      .map((cell) => cell.rect)
      .reduce((a, b) => a.expandToInclude(b));
  return MediaLayout(
    size: bounds.size,
    blocks: [MediaBlock.mosaic(rect: bounds, cells: cells)],
  );
}

const _ms = Duration(milliseconds: 1);

void main() {
  const a = MediaItemId('a');
  const b = MediaItemId('b');

  final one = _layout([_cell('a', const Rect.fromLTWH(0, 0, 200, 100))]);
  final two = _layout([
    _cell('a', const Rect.fromLTWH(0, 0, 100, 100)),
    _cell('b', const Rect.fromLTWH(100, 0, 100, 100)),
  ]);
  final tall = _layout([
    _cell('a', const Rect.fromLTWH(0, 0, 200, 300), radius: 12),
  ]);
  final short = _layout([_cell('a', const Rect.fromLTWH(0, 0, 200, 100))]);

  MediaLayoutTransition leg(
    MediaLayout from,
    MediaLayout to,
    MediaTransitionPolicy policy,
  ) => MediaLayoutTransition(
    from: MediaTransitionFrame.settled(from),
    to: to,
    policy: policy,
  );

  group('policy values', () {
    test('Android: the list-item change timing, 120 ms exit, 0.9 enter', () {
      const policy = MediaTransitionPolicy.android();
      expect(policy.move, ChatMessageChangeParams.duration);
      expect(policy.move, const Duration(milliseconds: 250));
      expect(policy.moveCurve, ChatMessageChangeParams.curve);
      expect(policy.moveCurve, isA<Cubic>());
      final cubic = policy.moveCurve as Cubic;
      expect(cubic.a, closeTo(0.199, 0.001));
      expect(cubic.b, closeTo(0.011, 0.001));
      expect(cubic.c, closeTo(0.279, 0.001));
      expect(cubic.d, closeTo(0.910, 0.001));
      expect(policy.lerpRadii, isTrue);
      expect(policy.exitFade, const Duration(milliseconds: 120));
      expect(policy.moveDelayOnExit, const Duration(milliseconds: 120));
      expect(policy.enterFade, const Duration(milliseconds: 250));
      expect(policy.enterScale, 0.9);
      expect(policy.animates, isTrue);
    });

    test('iOS: 0.4 s system curve, corners snap, 0.25 s fades', () {
      const policy = MediaTransitionPolicy.ios();
      expect(policy.move, const Duration(milliseconds: 400));
      expect(policy.moveCurve, const Cubic(0.23, 1, 0.32, 1));
      expect(policy.lerpRadii, isFalse);
      expect(policy.exitFade, const Duration(milliseconds: 250));
      expect(policy.moveDelayOnExit, Duration.zero);
      expect(policy.enterFade, const Duration(milliseconds: 250));
      expect(policy.enterScale, 1);
    });

    test('desktop: none', () {
      const policy = MediaTransitionPolicy.desktop();
      expect(policy, const MediaTransitionPolicy.none());
      expect(policy.animates, isFalse);
    });

    test('MessageMediaPolicy carries each family\'s transition', () {
      expect(
        const MessageMediaPolicy.android().transition,
        const MediaTransitionPolicy.android(),
      );
      expect(
        const MessageMediaPolicy.ios().transition,
        const MediaTransitionPolicy.ios(),
      );
      expect(
        const MessageMediaPolicy.desktop().transition,
        const MediaTransitionPolicy.desktop(),
      );
      final custom = const MessageMediaPolicy.android().copyWith(
        transition: const MediaTransitionPolicy.none(),
      );
      expect(custom.transition, const MediaTransitionPolicy.none());
    });

    test('copyWith replaces one track', () {
      final policy = const MediaTransitionPolicy.android().copyWith(
        move: const Duration(milliseconds: 200),
      );
      expect(policy.move, const Duration(milliseconds: 200));
      expect(policy.exitFade, const Duration(milliseconds: 120));
    });
  });

  group('move', () {
    test('Android: rect and radii follow the curve over 250 ms', () {
      final run = leg(short, tall, const MediaTransitionPolicy.android());
      expect(run.duration, const Duration(milliseconds: 250));

      final start = run.frameAt(Duration.zero);
      expect(start.layout.cellOf(a)!.rect.height, 100);
      expect(start.progress, 0);

      final mid = run.frameAt(_ms * 125);
      final t = ChatMessageChangeParams.curve.transform(0.5);
      expect(mid.progress, closeTo(t, 1e-9));
      expect(mid.layout.cellOf(a)!.rect.height, closeTo(100 + 200 * t, 1e-6));
      expect(mid.layout.cellOf(a)!.radii.topLeft, closeTo(12 * t, 1e-6));
      expect(mid.layout.size.height, closeTo(100 + 200 * t, 1e-6));
      expect(mid.isSettled, isFalse);

      final end = run.frameAt(_ms * 250);
      expect(end.isSettled, isTrue);
      expect(end.layout, tall);
    });

    test('iOS: rects over 400 ms, corners snap', () {
      final run = leg(short, tall, const MediaTransitionPolicy.ios());
      expect(run.duration, const Duration(milliseconds: 400));
      final mid = run.frameAt(_ms * 200);
      expect(mid.layout.cellOf(a)!.radii, const MediaCornerRadii.all(12));
      final t = const Cubic(0.23, 1, 0.32, 1).transform(0.5);
      expect(mid.layout.cellOf(a)!.rect.height, closeTo(100 + 200 * t, 1e-6));
    });

    test('desktop: the first frame is the end', () {
      final run = leg(short, tall, const MediaTransitionPolicy.desktop());
      expect(run.duration, Duration.zero);
      expect(run.frameAt(Duration.zero).isSettled, isTrue);
      expect(run.frameAt(Duration.zero).layout, tall);
    });
  });

  group('enter', () {
    test('Android: fade and scale 0.9 to 1 over 250 ms', () {
      final run = leg(one, two, const MediaTransitionPolicy.android());
      expect(run.entering, {b});
      expect(run.exiting, isEmpty);
      expect(run.moveDelay, Duration.zero);

      final start = run.frameAt(Duration.zero);
      expect(start.fadeOf(b), const MediaCellFade(opacity: 0, scale: 0.9));
      expect(start.fadeOf(a), MediaCellFade.settled);

      final mid = run.frameAt(_ms * 125);
      final f = Curves.easeInOutSine.transform(0.5);
      expect(mid.fadeOf(b).opacity, closeTo(f, 1e-9));
      expect(mid.fadeOf(b).scale, closeTo(0.9 + 0.1 * f, 1e-9));
      // The cell that enters sits at its new rect from the start.
      expect(mid.layout.cellOf(b)!.rect, const Rect.fromLTWH(100, 0, 100, 100));

      expect(run.frameAt(_ms * 250).fades, isEmpty);
    });

    test('iOS: fade over 250 ms, no scale', () {
      final run = leg(one, two, const MediaTransitionPolicy.ios());
      final start = run.frameAt(Duration.zero);
      expect(start.fadeOf(b), const MediaCellFade(opacity: 0, scale: 1));
      final mid = run.frameAt(_ms * 125);
      expect(
        mid.fadeOf(b).opacity,
        closeTo(Curves.easeInOut.transform(0.5), 1e-9),
      );
      expect(run.frameAt(_ms * 250).fadeOf(b), MediaCellFade.settled);
      expect(run.duration, const Duration(milliseconds: 400));
    });

    test('desktop: none', () {
      final run = leg(one, two, const MediaTransitionPolicy.desktop());
      expect(run.frameAt(Duration.zero).fades, isEmpty);
    });
  });

  group('exit', () {
    test('Android: 120 ms fade at the last rect; the move waits 120 ms', () {
      final run = leg(two, one, const MediaTransitionPolicy.android());
      expect(run.exiting, {b});
      expect(run.moveDelay, const Duration(milliseconds: 120));
      expect(run.duration, const Duration(milliseconds: 370));

      final fading = run.frameAt(_ms * 60);
      expect(
        fading.fadeOf(b).opacity,
        closeTo(1 - Curves.easeInOutSine.transform(0.5), 1e-9),
      );
      expect(
        fading.layout.exiting.single.rect,
        const Rect.fromLTWH(100, 0, 100, 100),
      );
      // The survivor has not moved yet.
      expect(fading.progress, 0);
      expect(
        fading.layout.cellOf(a)!.rect,
        const Rect.fromLTWH(0, 0, 100, 100),
      );

      final moving = run.frameAt(_ms * 245);
      expect(moving.layout.exiting, isEmpty, reason: 'the exit has ended');
      expect(moving.fades, isEmpty);
      final t = ChatMessageChangeParams.curve.transform(0.5);
      expect(moving.progress, closeTo(t, 1e-9));
      expect(moving.layout.cellOf(a)!.rect.width, closeTo(100 + 100 * t, 1e-6));

      expect(run.frameAt(_ms * 370).layout, one);
    });

    test('iOS: 250 ms fade, the move does not wait', () {
      final run = leg(two, one, const MediaTransitionPolicy.ios());
      expect(run.moveDelay, Duration.zero);
      final mid = run.frameAt(_ms * 125);
      expect(mid.progress, greaterThan(0));
      expect(
        mid.fadeOf(b).opacity,
        closeTo(1 - Curves.easeInOut.transform(0.5), 1e-9),
      );
      expect(mid.layout.exiting.single.itemId, b);
      expect(run.frameAt(_ms * 250).layout.exiting, isEmpty);
    });

    test('desktop: none', () {
      final frame = leg(
        two,
        one,
        const MediaTransitionPolicy.desktop(),
      ).frameAt(Duration.zero);
      expect(frame.layout, one);
      expect(frame.layout.exiting, isEmpty);
    });
  });

  group('mid-flight re-layout', () {
    test('the next leg starts from the frame reached', () {
      const policy = MediaTransitionPolicy.android();
      final first = leg(short, tall, policy);
      final reached = first.frameAt(_ms * 100);
      final reachedHeight = reached.layout.cellOf(a)!.rect.height;
      expect(reachedHeight, inExclusiveRange(100, 300));

      final wider = _layout([_cell('a', const Rect.fromLTWH(0, 0, 300, 200))]);
      final next = MediaLayoutTransition(
        from: reached,
        to: wider,
        policy: policy,
      );

      final start = next.frameAt(Duration.zero);
      expect(start.layout.cellOf(a)!.rect.height, reachedHeight);
      expect(start.layout.size, reached.layout.size);
      expect(next.frameAt(_ms * 250).layout, wider);
    });

    test('a cell fading in keeps fading from its opacity, not from 0', () {
      const policy = MediaTransitionPolicy.android();
      final reached = leg(one, two, policy).frameAt(_ms * 125);
      final opacity = reached.fadeOf(b).opacity;
      expect(opacity, inExclusiveRange(0, 1));

      final moved = _layout([
        _cell('a', const Rect.fromLTWH(0, 0, 150, 100)),
        _cell('b', const Rect.fromLTWH(150, 0, 50, 100)),
      ]);
      final next = MediaLayoutTransition(
        from: reached,
        to: moved,
        policy: policy,
      );
      expect(next.entering, isEmpty);
      expect(next.frameAt(Duration.zero).fadeOf(b), MediaCellFade.settled);
    });

    test('a cell fading out that comes back fades in from where it was', () {
      const policy = MediaTransitionPolicy.android();
      final reached = leg(two, one, policy).frameAt(_ms * 60);
      final opacity = reached.fadeOf(b).opacity;
      expect(opacity, inExclusiveRange(0, 1));

      final next = MediaLayoutTransition(
        from: reached,
        to: two,
        policy: policy,
      );
      expect(next.entering, {b});
      final start = next.frameAt(Duration.zero);
      expect(start.fadeOf(b).opacity, closeTo(opacity, 1e-9));
      expect(start.layout.exiting, isEmpty);
      expect(next.frameAt(next.duration).layout, two);
    });

    test('a cell still fading out keeps fading out from its opacity', () {
      const policy = MediaTransitionPolicy.android();
      final reached = leg(two, one, policy).frameAt(_ms * 60);
      final opacity = reached.fadeOf(b).opacity;

      final next = MediaLayoutTransition(
        from: reached,
        to: tall,
        policy: policy,
      );
      expect(next.exiting, {b});
      expect(next.frameAt(Duration.zero).fadeOf(b).opacity, opacity);
    });
  });
}
