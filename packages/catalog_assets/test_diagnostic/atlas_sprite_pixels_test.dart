// Diagnostic (ticket 57), not in unit_test.dart.
//
//   cd packages/catalog_assets && flutter test test_diagnostic/atlas_sprite_pixels_test.dart
//
// Invariant that is the user's symptom: whenever a FrameHandle offers a
// sprite, the page image behind it holds that handle's pixels in the sprite's
// region (a sprite over a transparent region paints nothing = "loaded blank").
// Test 1 churns the real FrameAtlas (random acquire / render / release /
// releaseUnpinned, tight budget): expected green, rules out pool / slot /
// ordering causes. Test 2 swaps in the uploader the perf-ceilings branch
// (nm/53-perf-ceilings, `upload_skip`) installs: expected RED, the symptom.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter_test/flutter_test.dart';

const _sizeClass = 128;
const _side = 256; // 4 cells per page
final _images = Expando<Uint8List>('image pixels');

Future<ui.Image> _snapshotUpload(Uint8List pixels, int side) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  _images[image] = Uint8List.fromList(pixels);
  return Future.value(image);
}

/// The ceiling: a page that already has an image keeps it.

final class _MarkRenderer implements FrameRenderer {
  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    for (var i = 0; i < jobs.length; i++) {
      final slot = jobs[i].slot;
      final bytes = memory.page(slot.pageIndex, side: slot.pageSide);
      final mark = jobs[i].source as int;
      final x0 = slot.rect.left.toInt(), y0 = slot.rect.top.toInt();
      for (var y = 0; y < _sizeClass; y++) {
        for (var x = 0; x < _sizeClass; x++) {
          final o = ((y0 + y) * slot.pageSide + x0 + x) * 4;
          bytes[o + 3] = mark;
        }
      }
    }
    return [for (var i = 0; i < jobs.length; i++) i];
  }
}

/// Number of live handles whose sprite region lacks their mark.
int _blankSprites(Map<String, (FrameHandle<String>, int)> live) {
  var blank = 0;
  for (final (handle, mark) in live.values) {
    final sprite = handle.sprite;
    if (sprite == null) continue;
    final px = _images[sprite.page]!;
    final pageSide = math.sqrt(px.length ~/ 4).round();
    final x = sprite.source.left.toInt() + 5, y = sprite.source.top.toInt() + 5;
    if (px[(y * pageSide + x) * 4 + 3] != mark) blank++;
  }
  return blank;
}

Future<int> _churn(FramePageUploader upload, {int seed = 7}) async {
  final atlas = FrameAtlas<String>(
    renderer: _MarkRenderer(),
    memory: ListFramePageMemory(),
    budgetBytes: 3 * _side * _side * 4, // 12 cells: forces eviction
    pageSideFor: (_) => _side,
    sizeClasses: const [_sizeClass],
    upload: upload,
  );
  final rng = math.Random(seed);
  final live = <String, (FrameHandle<String>, int)>{};
  var worst = 0;
  for (var step = 0; step < 400; step++) {
    final key = 'k${rng.nextInt(30)}';
    final held = live[key];
    switch (rng.nextInt(4)) {
      case 0 || 1:
        if (held == null) {
          final mark = 1 + int.parse(key.substring(1)); // stable per key
          final h = atlas.acquire(key, source: mark, width: 100, height: 100);
          if (h != null) live[key] = (h, mark);
        }
      case 2:
        if (held != null) {
          await atlas.render([(handle: held.$1, frame: step)]);
        }
      case 3:
        if (held != null) {
          held.$1.release();
          live.remove(key);
        }
        if (rng.nextInt(10) == 0) atlas.releaseUnpinned();
    }
    worst = math.max(worst, _blankSprites(live));
  }
  atlas.dispose();
  return worst;
}

void main() {
  test(
    'real pipeline: no sprite ever sits over a region without its pixels',
    () async {
      expect(await _churn(_snapshotUpload), 0);
    },
  );

  test(
    'upload_skip ceiling: later cells of a page stay blank (RED = symptom)',
    () async {
      late Uint8List first;
      var firstImage = true;
      Future<ui.Image> keepOld(Uint8List pixels, int side) async {
        final image = await _snapshotUpload(pixels, side);
        if (firstImage) {
          first = _images[image]!;
          firstImage = false;
        } else {
          _images[image] = first; // pixels of the first upload only
        }
        return image;
      }

      expect(await _churn(keepOld), 0, reason: 'sprites over blank regions');
    },
  );
}
