/// Which glyphs the system cannot draw: cells rendered identical to a
/// missing-glyph reference, or not rendered at all.
///
/// **Seam:** `MissingGlyphProbe.observe` fed cell pixels the way the bake pass
/// feeds them, read back through `supports`, `completed` and the snapshot.
/// Pixels are plain bytes, so nothing here needs a rasteriser or a font.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:emoji_data/emoji_data.dart';
import 'package:test/test.dart';

const _reference = 'REF';

Uint8List _art(int seed) =>
    Uint8List.fromList([for (var i = 0; i < 32; i++) (seed * 7 + i) & 0xFF]);

final Uint8List _tofu = _art(99);
final Uint8List _blank = Uint8List(32);

MissingGlyphProbe _probe(
  List<String> glyphs, {
  String artVersion = 'art-1',
  GlyphProbeSnapshot? restored,
}) => MissingGlyphProbe(
  glyphs: glyphs,
  references: const [_reference],
  artVersion: artVersion,
  restored: restored,
);

void main() {
  test('a glyph drawn like the missing-glyph reference is unsupported', () {
    final probe = _probe(['a', 'b']);

    probe.observe(_reference, _tofu);
    probe.observe('a', _art(1));
    probe.observe('b', Uint8List.fromList(_tofu));

    expect(probe.supports('a'), isTrue);
    expect(probe.supports('b'), isFalse);
  });

  test('a glyph that drew nothing is unsupported, whatever the reference', () {
    final probe = _probe(['a']);

    probe.observe('a', _blank);

    expect(probe.supports('a'), isFalse);
  });

  test('a glyph is not judged before the reference has been seen', () {
    final probe = _probe(['a']);

    probe.observe('a', _tofu);
    expect(probe.supports('a'), isNull);

    probe.observe(_reference, _tofu);
    expect(probe.supports('a'), isFalse);
  });

  test('a glyph not yet observed has no verdict', () {
    final probe = _probe(['a', 'b']);
    probe.observe(_reference, _tofu);
    probe.observe('a', _art(1));

    expect(probe.supports('b'), isNull);
    expect(probe.supports('not planned'), isNull);
  });

  test('it asks for what it lacks and nothing it already has', () {
    final probe = _probe(['a', 'b']);
    expect(probe.pendingReferences, [_reference]);
    expect(probe.wants('a'), isTrue);
    expect(probe.wants('not planned'), isFalse);

    probe.observe(_reference, _tofu);
    probe.observe('a', _art(1));

    expect(probe.pendingReferences, isEmpty);
    expect(probe.wants('a'), isFalse);
    expect(probe.wants('b'), isTrue);
  });

  test('completed fires once the references and every glyph are in', () async {
    final probe = _probe(['a', 'b']);
    var done = false;
    unawaited(probe.completed.then((_) => done = true));

    probe.observe('a', _art(1));
    probe.observe('b', _art(2));
    await pumpEventQueue();
    expect(done, isFalse, reason: 'no reference yet');

    probe.observe(_reference, _tofu);
    await pumpEventQueue();
    expect(done, isTrue);
    expect(probe.isComplete, isTrue);
  });

  test('the unsupported glyphs are listed once the probe is complete', () {
    final probe = _probe(['a', 'b', 'c']);
    probe.observe(_reference, _tofu);
    probe.observe('a', _art(1));
    probe.observe('b', _tofu);
    probe.observe('c', _blank);

    expect(probe.unsupported, unorderedEquals(['b', 'c']));
  });

  group('a snapshot', () {
    MissingGlyphProbe finished({String artVersion = 'art-1'}) {
      final probe = _probe(['a', 'b'], artVersion: artVersion);
      probe.observe(_reference, _tofu);
      probe.observe('a', _art(1));
      probe.observe('b', _tofu);
      return probe;
    }

    test('restores the verdicts without observing anything', () {
      final json = finished().snapshot().toJson();

      final restored = _probe([
        'a',
        'b',
      ], restored: GlyphProbeSnapshot.fromJson(json));

      expect(restored.isComplete, isTrue);
      expect(restored.supports('a'), isTrue);
      expect(restored.supports('b'), isFalse);
      expect(restored.pendingReferences, isEmpty);
      expect(restored.wants('a'), isFalse);
    });

    test('is dropped when the art version differs: the glyphs are probed '
        'again', () {
      final snapshot = finished(artVersion: 'art-1').snapshot();

      final probe = _probe(['a', 'b'], artVersion: 'art-2', restored: snapshot);

      expect(probe.isComplete, isFalse);
      expect(probe.supports('b'), isNull);
      expect(probe.pendingReferences, [_reference]);
      expect(probe.wants('a'), isTrue);
    });

    test('keeps its verdicts and probes only a glyph added since', () {
      final snapshot = finished().snapshot();

      final probe = _probe(['a', 'b', 'c'], restored: snapshot);

      expect(probe.isComplete, isFalse);
      expect(probe.supports('b'), isFalse);
      expect(probe.wants('a'), isFalse);
      expect(probe.wants('c'), isTrue);
      expect(probe.pendingReferences, isEmpty);
    });

    test('with damaged json is a FormatException', () {
      expect(
        () => GlyphProbeSnapshot.fromJson({'artVersion': 3}),
        throwsFormatException,
      );
    });
  });
}
