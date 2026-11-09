/// Ticket 150: an animated GIF or WebP played by the engine's codec, stopped
/// (its cell scrolled off) and played again, goes on from the frame it left
/// on, one frame of the clip at a time at the clip's rate: no hold and no
/// catch-up a few frames later.
///
/// The fixtures are the demo's frame counter clips: each frame carries its
/// index in a binary bar (the layout is in the example's
/// `tool/frame_counter.dart`), read here from what the paintable paints.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_decoder/image_decoder.dart';

// The frame: 192 x 144; ten bar cells of 16 x 24 from (16, 8), the last eight
// the frame's index, most significant first.
const int _width = 192;
const int _height = 144;

/// The index the bar of what [paintable] paints at [time] says.
Future<int> _indexAt(AssetPaintable paintable, Duration time) async {
  final recorder = ui.PictureRecorder();
  paintable.paint(
    ui.Canvas(recorder),
    const ui.Rect.fromLTWH(0, 0, _width * 1.0, _height * 1.0),
    AssetPaintContext(time: time),
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  final pixels = (await image.toByteData())!;
  image.dispose();
  var index = 0;
  for (var cell = 2; cell < 10; cell++) {
    final at = (20 * _width + 24 + 16 * cell) * 4;
    index = index << 1 | (pixels.getUint8(at) > 128 ? 1 : 0);
  }
  return index;
}

Future<AssetPaintable> _decode(String fixture) async {
  final paintable = Completer<AssetPaintable>();
  const ImageCodecDecoder().decode(
    DecodeRequest(
      descriptor: const ContentDescriptor(
        key: ContentKey.document('counter'),
        semanticKind: SemanticKind.gif,
        mediaForm: MediaForm.animatedImage,
        animated: true,
      ),
      spec: const AssetSpec(pixelWidth: _width, pixelHeight: _height),
      part: FetchPart.content,
      content: FetchedContent.bytes(
        File('test/fixtures/$fixture').readAsBytesSync(),
      ),
    ),
    _Progress(paintable),
  );
  return paintable.future.timeout(const Duration(seconds: 10));
}

final class _Progress implements AssetProgress {
  _Progress(this.paintable);

  final Completer<AssetPaintable> paintable;

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) => this.paintable.complete(paintable);

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) => paintable.completeError(error, stackTrace);

  @override
  void download(double fraction) {}

  @override
  void cancelled() {}
}

void main() {
  for (final (fixture, rate) in const [
    ('frame_counter_15fps.gif', 15),
    ('frame_counter_25fps.webp', 25),
  ]) {
    for (final away in const [
      Duration(milliseconds: 300),
      Duration(seconds: 1),
    ]) {
      test('$fixture stopped for ${away.inMilliseconds} ms goes on from the '
          'frame it left on, one frame of the clip at a time', () async {
        final paintable = await _decode(fixture);
        addTearDown(paintable.dispose);
        // Display frames of 16 ms, each after the codec had a moment to
        // decode the next frame ahead, as a device's frame interval gives it.
        var time = const Duration(seconds: 1);
        Future<int> frame() async {
          time += const Duration(milliseconds: 16);
          final index = await _indexAt(paintable, time);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return index;
        }

        int? left;
        for (var i = 0; i < 40; i++) {
          left = await frame();
        }
        // Off screen: nothing paints it; back, its surface says playback
        // resumed before the first paint.
        time += away;
        paintable.playbackResumed();
        final shown = [for (var i = 0; i < 60; i++) await frame()];

        expect(
          shown.first,
          left,
          reason: 'the first frame back is the one it left on; shown: $shown',
        );
        for (var k = 1; k < shown.length; k++) {
          expect(
            shown[k] - shown[k - 1],
            inInclusiveRange(0, 1),
            reason: 'no catch-up at display frame $k; shown: $shown',
          );
        }
        for (var k = 0; k < shown.length; k++) {
          // GIF delays are whole hundredths: 15 fps is 70 or 60 ms a frame.
          final due = left! + (k * 16 * rate / 1000).floor();
          expect(
            shown[k],
            inInclusiveRange(due - 1, due + 1),
            reason: 'display frame $k back shows frame $due; shown: $shown',
          );
        }
      });
    }
  }
}
