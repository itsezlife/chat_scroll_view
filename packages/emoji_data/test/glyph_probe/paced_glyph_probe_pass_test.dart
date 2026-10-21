/// The probe's own rasterisation pass, for a host with no bake to share: it
/// draws a few glyphs per frame, and stays out of the way of the open
/// animation and of scrolling.
///
/// **Seam:** `PacedGlyphProbePass.run` with an injected cell renderer, a frame
/// clock the test advances by hand and a pause flag the test flips. No font,
/// no scheduler.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

const _reference = 'REF';

// Eight pixels whose solid ink is the bits of the glyph's last code unit: the
// probe compares cells by their solid ink.
Uint8List _art(String glyph) => Uint8List.fromList([
  for (var bit = 0; bit < 8; bit++) ...[
    0x80,
    0x80,
    0x80,
    if (glyph.codeUnits.last >> bit & 1 == 1) 255 else 20,
  ],
]);

/// A frame clock that ticks only when told to.
final class _ManualFrames {
  Completer<void> _next = Completer<void>();
  int ticks = 0;

  Future<void> nextFrame() => _next.future;

  Future<void> tick() async {
    ticks++;
    final frame = _next;
    _next = Completer<void>();
    frame.complete();
    await pumpEventQueue();
  }
}

void main() {
  late List<String> glyphs;
  late MissingGlyphProbe probe;
  late _ManualFrames frames;
  late List<String> rendered;
  late bool paused;
  var perFrame = 3;

  PacedGlyphProbePass pass({Set<String> failing = const {}}) =>
      PacedGlyphProbePass(
        probe: probe,
        cellOf: (glyph) async {
          rendered.add(glyph);
          if (failing.contains(glyph)) throw StateError('no font for $glyph');
          return glyph == _reference ? _art('~') : _art(glyph);
        },
        nextFrame: frames.nextFrame,
        isPaused: () => paused,
        glyphsPerFrame: () => perFrame,
      );

  setUp(() {
    glyphs = [for (var i = 0; i < 8; i++) 'g$i'];
    probe = MissingGlyphProbe(
      glyphs: glyphs,
      references: const [_reference],
      store: FakeKeyValueStore(),
      artVersion: () async => 'art-1',
    );
    addTearDown(probe.dispose);
    frames = _ManualFrames();
    rendered = [];
    paused = false;
    perFrame = 3;
  });

  /// Ticks frames until [rendered] stops growing; returns the per-frame draw
  /// counts.
  Future<List<int>> runToEnd(Future<void> done) async {
    final counts = <int>[];
    var finished = false;
    unawaited(done.whenComplete(() => finished = true));
    await pumpEventQueue();
    for (var i = 0; i < 20 && !finished; i++) {
      final before = rendered.length;
      await frames.tick();
      counts.add(rendered.length - before);
    }
    return counts;
  }

  test('draws the reference and every glyph once, then stops', () async {
    final counts = await runToEnd(pass().run());

    expect(rendered.toSet(), {_reference, ...glyphs});
    expect(rendered, hasLength(glyphs.length + 1));
    expect(probe.isComplete, isTrue);
    expect(counts.where((c) => c > 0), isNotEmpty);
  });

  test('never draws more than the governor allows in one frame', () async {
    final counts = await runToEnd(pass().run());

    expect(counts.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(3));
  });

  test('follows the governor when it changes its mind', () async {
    final done = pass().run();
    await pumpEventQueue();
    await frames.tick();
    perFrame = 1;
    final before = rendered.length;
    await frames.tick();

    expect(rendered.length - before, 1);
    await runToEnd(done);
  });

  test('draws nothing while paused, and goes on afterwards', () async {
    paused = true;
    final done = pass().run();
    await pumpEventQueue();
    for (var i = 0; i < 4; i++) {
      await frames.tick();
    }
    expect(rendered, isEmpty);

    paused = false;
    await runToEnd(done);

    expect(probe.isComplete, isTrue);
  });

  test('cancel stops it between frames', () async {
    final subject = pass();
    final done = subject.run();
    await pumpEventQueue();
    await frames.tick();
    final drawn = rendered.length;

    subject.cancel();
    await frames.tick();
    await done;

    expect(rendered, hasLength(drawn));
    expect(probe.isComplete, isFalse);
  });

  test(
    'a glyph that cannot be drawn is reported once and left unknown',
    () async {
      final errors = <Object>[];
      await runZonedGuarded(() async {
        await runToEnd(pass(failing: {'g2'}).run());
      }, (error, _) => errors.add(error));

      expect(errors, hasLength(1));
      expect(rendered.where((g) => g == 'g2'), hasLength(1));
      expect(probe.verdictOf('g2'), isNull);
      expect(probe.supports(const ContentKey$Unicode('g2')), isTrue);
      expect(probe.verdictOf('g3'), isTrue);
    },
  );

  test('has nothing to draw for a probe that is complete', () async {
    await runToEnd(pass().run());
    rendered.clear();

    await pass().run();

    expect(rendered, isEmpty);
  });
}
