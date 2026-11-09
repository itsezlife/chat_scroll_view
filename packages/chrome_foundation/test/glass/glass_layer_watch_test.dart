import 'dart:ui' as ui;

import 'package:chrome_foundation/src/glass/glass_layer_watch.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

PictureLayer _picture(Rect bounds) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(bounds, Paint());
  return PictureLayer(bounds)..picture = recorder.endRecording();
}

class _Unread extends ContainerLayer {}

void main() {
  late OffsetLayer root;
  late GlassLayerWatch watch;

  setUp(() {
    root = OffsetLayer(offset: const Offset(50, 50));
    watch = GlassLayerWatch();
  });

  tearDown(() => root.dispose());

  test('the first look is a change everywhere', () {
    root.append(_picture(const Rect.fromLTWH(0, 0, 10, 10)));

    expect(watch.changeSince(root), same(GlassLayerChange.everywhere));
  });

  test('an unchanged tree is no change', () {
    root.append(_picture(const Rect.fromLTWH(0, 0, 10, 10)));
    watch.changeSince(root);

    expect(watch.changeSince(root).changed, isFalse);
  });

  test('a repaint is bounded by its layer, in the root space', () {
    final child = OffsetLayer(offset: const Offset(100, 0));
    root.append(child);
    child.append(_picture(const Rect.fromLTWH(0, 0, 10, 10)));
    watch.changeSince(root);

    child
      ..removeAllChildren()
      ..append(_picture(const Rect.fromLTWH(0, 0, 10, 10)));
    final change = watch.changeSince(root);

    // The root's own offset is not applied: the region is in its space.
    expect(change.region, const Rect.fromLTWH(100, 0, 10, 10));
    expect(change.touches(const Rect.fromLTWH(0, 0, 50, 50)), isFalse);
    expect(change.touches(const Rect.fromLTWH(105, 5, 50, 50)), isTrue);
  });

  test('a subtree that moved is dirty where it was and where it went', () {
    final child = OffsetLayer();
    root.append(child);
    child.append(_picture(const Rect.fromLTWH(0, 0, 10, 10)));
    watch.changeSince(root);

    child.offset = const Offset(0, 100);
    final change = watch.changeSince(root);

    expect(change.region, const Rect.fromLTWH(0, 0, 10, 110));
  });

  test('a clip above a repaint narrows its region', () {
    final clip = ClipRectLayer(clipRect: const Rect.fromLTWH(0, 0, 5, 5));
    root.append(clip);
    clip.append(_picture(const Rect.fromLTWH(0, 0, 10, 10)));
    watch.changeSince(root);

    clip
      ..removeAllChildren()
      ..append(_picture(const Rect.fromLTWH(0, 0, 10, 10)));

    expect(watch.changeSince(root).region, const Rect.fromLTWH(0, 0, 5, 5));
  });

  test('a texture changes on every look, within its rect', () {
    root.append(
      TextureLayer(rect: const Rect.fromLTWH(20, 20, 10, 10), textureId: 1),
    );
    watch.changeSince(root);

    final change = watch.changeSince(root);

    expect(change.region, const Rect.fromLTWH(20, 20, 10, 10));
  });

  test('a layer type it cannot read changes everywhere, every look', () {
    root.append(_Unread());
    watch.changeSince(root);

    expect(watch.changeSince(root), same(GlassLayerChange.everywhere));
  });

  test('reset forgets the last look', () {
    root.append(_picture(const Rect.fromLTWH(0, 0, 10, 10)));
    watch
      ..changeSince(root)
      ..reset();

    expect(watch.changeSince(root), same(GlassLayerChange.everywhere));
  });
}
