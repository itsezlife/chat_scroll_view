/// The production composition of the art version signal: sentinel glyphs drawn
/// by the system rasteriser, one per frame, fingerprinted.
///
/// **Seam:** `SentinelGlyphArtVersion` with a fake rasteriser and a frame
/// clock the test controls.
library;

import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('draws one sentinel per frame and answers a fingerprint', () async {
    final rasteriser = FakeGlyphRasteriser();
    final frames = <Completer<void>>[];
    final source = SentinelGlyphArtVersion(
      rasteriser: rasteriser,
      sentinels: const ['a', 'b'],
      nextFrame: () {
        final frame = Completer<void>();
        frames.add(frame);
        return frame.future;
      },
    );

    final version = source.read();
    await pumpEventQueue();
    expect(rasteriser.painted, isEmpty);

    frames.last.complete();
    await pumpEventQueue();
    expect(rasteriser.painted, ['a']);

    await pumpEventQueue();
    frames.last.complete();
    expect(await version, startsWith('art1-'));
    expect(rasteriser.painted, ['a', 'b']);
  });

  test('another art for the same sentinels is another version', () async {
    Future<String> versionOf(String redrawnAs) => SentinelGlyphArtVersion(
      rasteriser: _Redrawing(redrawnAs),
      sentinels: const ['a', 'b'],
      nextFrame: () async {},
    ).read();

    expect(await versionOf('v1'), await versionOf('v1'));
    expect(await versionOf('v1'), isNot(await versionOf('v2')));
  });

  test('asks the system once however often it is read', () async {
    final rasteriser = FakeGlyphRasteriser();
    final source = SentinelGlyphArtVersion(
      rasteriser: rasteriser,
      sentinels: const ['a'],
      nextFrame: () async {},
    );

    await source.read();
    await source.read();

    expect(rasteriser.painted, ['a']);
  });
}

/// A system whose art for every glyph is named by [style].
final class _Redrawing implements GlyphRasteriser {
  _Redrawing(this.style);

  final String style;
  final FakeGlyphRasteriser _inner = FakeGlyphRasteriser();

  @override
  void paint(canvas, String glyph, rect) =>
      _inner.paint(canvas, '$glyph$style', rect);
}
