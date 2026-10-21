/// The system emoji art version signal: a fingerprint of the pixels a few
/// sentinel glyphs render to, computed through an injected renderer.
///
/// **Seam:** `GlyphArtFingerprint.compute` with a renderer that answers bytes
/// from a table and a frame clock the test advances by hand. No font, no
/// platform channel.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

Uint8List _bytes(int seed) =>
    Uint8List.fromList([for (var i = 0; i < 64; i++) (seed * 31 + i) & 0xFF]);

void main() {
  const sentinels = ['a', 'b', 'c'];

  /// A renderer drawing each sentinel from [art].
  Future<Uint8List> Function(String) renderer(Map<String, int> art) =>
      (glyph) async => _bytes(art[glyph]!);

  Future<void> noWait() async {}

  test('the same art gives the same fingerprint', () async {
    final art = {'a': 1, 'b': 2, 'c': 3};

    final first = await GlyphArtFingerprint.compute(
      sentinels: sentinels,
      pixelsOf: renderer(art),
      nextFrame: noWait,
    );
    final second = await GlyphArtFingerprint.compute(
      sentinels: sentinels,
      pixelsOf: renderer(art),
      nextFrame: noWait,
    );

    expect(first, second);
  });

  test('one sentinel drawn differently changes the fingerprint', () async {
    final before = await GlyphArtFingerprint.compute(
      sentinels: sentinels,
      pixelsOf: renderer({'a': 1, 'b': 2, 'c': 3}),
      nextFrame: noWait,
    );
    final after = await GlyphArtFingerprint.compute(
      sentinels: sentinels,
      pixelsOf: renderer({'a': 1, 'b': 2, 'c': 4}),
      nextFrame: noWait,
    );

    expect(after, isNot(before));
  });

  test('the same art on other sentinels is another fingerprint', () async {
    final art = {'a': 1, 'b': 2, 'c': 3};
    final abc = await GlyphArtFingerprint.compute(
      sentinels: ['a', 'b'],
      pixelsOf: renderer(art),
      nextFrame: noWait,
    );
    final ba = await GlyphArtFingerprint.compute(
      sentinels: ['b', 'a'],
      pixelsOf: renderer(art),
      nextFrame: noWait,
    );

    expect(ba, isNot(abc));
  });

  group('the supplementary signal', () {
    final art = {'a': 1, 'b': 2, 'c': 3};

    Future<String> fingerprint({String? supplement}) =>
        GlyphArtFingerprint.compute(
          sentinels: sentinels,
          pixelsOf: renderer(art),
          nextFrame: noWait,
          supplement: supplement,
        );

    test('changes the fingerprint when it changes', () async {
      expect(
        await fingerprint(supplement: 'os 14'),
        isNot(await fingerprint(supplement: 'os 15')),
      );
    });

    test('is part of the identity: with and without differ', () async {
      expect(
        await fingerprint(supplement: 'os 14'),
        isNot(await fingerprint()),
      );
    });

    test(
      'keeps the pixel-only fingerprint of a host that passes none',
      () async {
        expect(await fingerprint(), await fingerprint(supplement: null));
      },
    );
  });

  test('renders one sentinel per frame, never two in a row', () async {
    final rendered = <String>[];
    var frames = 0;
    final waiting = <Completer<void>>[];
    final done = GlyphArtFingerprint.compute(
      sentinels: sentinels,
      pixelsOf: (glyph) async {
        rendered.add(glyph);
        return _bytes(1);
      },
      nextFrame: () {
        frames++;
        final frame = Completer<void>();
        waiting.add(frame);
        return frame.future;
      },
    );

    // Nothing is drawn before the first frame.
    await pumpEventQueue();
    expect(rendered, isEmpty);

    for (var expected = 1; expected <= sentinels.length; expected++) {
      waiting.last.complete();
      await pumpEventQueue();
      expect(rendered, hasLength(expected));
    }
    await done;
    expect(frames, sentinels.length);
  });

  test('a renderer that fails fails the fingerprint, not silently', () async {
    final future = GlyphArtFingerprint.compute(
      sentinels: sentinels,
      pixelsOf: (_) async => throw StateError('no font'),
      nextFrame: noWait,
    );

    await expectLater(future, throwsStateError);
  });

  test('the default sentinels are distinct emoji of different eras', () {
    expect(
      GlyphArtFingerprint.defaultSentinels.toSet(),
      hasLength(GlyphArtFingerprint.defaultSentinels.length),
    );
    expect(GlyphArtFingerprint.defaultSentinels.length, inInclusiveRange(3, 6));
  });
}
