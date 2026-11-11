import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';

/// A sticker in a chat and a panel of stickers beside it, on one texture pool
/// and one frame atlas at the default sizes and budgets, with the four
/// buffers a texture has on Android.
///
/// The chat's sticker is 512 px (a lone sticker on a phone is fitted in about
/// 206 dp, past the 512 px render cap at 3x), so its texture costs 4 MiB and
/// its page slot sits on a 1024 px page. The panel's cells are 240 px, the
/// 256 px class: 1 MiB a texture.
///
/// The panel docks beside the chat, so the chat plays while it is open. When
/// it opens, the chat's viewport shrinks and the sticker leaves the screen;
/// its texture idles, keeping its frame. The panel's cells fill the budget,
/// which destroys that idle texture for room. When the panel hides, its
/// cells are held (their surface keeps its frames, ADR 043 *Amendment:
/// leases of a kept panel*): they keep their textures. The sticker comes
/// back into the chat and finds no texture of its class, and none can be
/// made: the budget is all leased textures.
void main() {
  const chatEdge = 512;
  const cellEdge = 240;
  const cells = 45;

  late FakeFrameRenderer renderer;
  late FakeFrameTextureHost host;
  late FrameTexturePool pool;
  late FakeTextureFrameWriter writer;
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late ManualRetentionTimers timers;
  late LottieFrameScheduler scheduler;
  late List<({int side, int rows})> uploads;
  var time = Duration.zero;

  Future<ui.Image> upload(Uint8List pixels, int side) {
    uploads.add((side: side, rows: pixels.length ~/ (side * 4)));
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawRect(const ui.Rect.fromLTWH(0, 0, 1, 1), ui.Paint());
    final picture = recorder.endRecording();
    final image = picture.toImageSync(2, 2);
    picture.dispose();
    return Future.value(image);
  }

  Future<void> tick() async {
    time += const Duration(milliseconds: 16);
    ticks.tick(time);
    await pumpEventQueue();
  }

  // A sweep period passes; a lease still on a slot warms its class.
  Future<void> sweep() async {
    timers.elapse(const Duration(seconds: 1));
    await pumpEventQueue();
  }

  setUp(() {
    time = Duration.zero;
    uploads = [];
    renderer = FakeFrameRenderer();
    host = FakeFrameTextureHost(buffersPerTexture: 4);
    pool = FrameTexturePool(host: host, reuseDelay: Duration.zero);
    writer = FakeTextureFrameWriter();
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    timers = ManualRetentionTimers();
    scheduler = LottieFrameScheduler(
      atlas: FrameAtlas<Object>(
        renderer: renderer,
        memory: ListFramePageMemory(),
        upload: upload,
      ),
      clock: clock,
      textures: pool,
      textureWriter: writer,
      startTimer: timers.start,
    );
  });
  tearDown(() {
    scheduler.dispose();
    pool.dispose();
    clock.dispose();
  });

  // Up to the panel's close: the chat's sticker away, the panel's cells on
  // textures and held. Returns the cells.
  Future<List<LottieFrameLease>> openPanelAndClose() async {
    await pool.warm(chatEdge, 1);
    final chat = scheduler.acquire('chat', 'src', chatEdge, chatEdge)!;
    for (var frame = 0; frame < 3; frame++) {
      scheduler.want(chat, frame);
      await tick();
    }
    expect(chat.texture, isNotNull, reason: 'the chat plays on a texture');

    // The panel opens beside the chat; the sticker leaves the chat's
    // viewport, and its texture idles with its frame.
    chat.releaseUnlessPainted();
    timers.elapse(Duration.zero);
    expect(pool.keptFrames, 1);

    // The panel plays: its warmer and its leases warm the 256 px class.
    final panel = [
      for (var i = 0; i < cells; i++)
        scheduler.acquire('cell$i', 'src', cellEdge, cellEdge)!,
    ];
    for (var round = 0; round < 4; round++) {
      await pool.warm(256, cells);
      for (final cell in panel) {
        scheduler.want(cell, round);
      }
      await tick();
    }
    expect(
      scheduler.leasePlaces().onTextures,
      cells,
      reason: 'every cell of the panel plays on a texture',
    );
    expect(
      pool.classCounts()[chatEdge],
      (leased: 0, idle: 0, kept: 0),
      reason: "the panel's warm destroyed the chat's idle texture for room",
    );

    // The panel hides: its cells are held, and keep their textures.
    for (final cell in panel) {
      cell.kept = true;
    }
    return panel;
  }

  group('the chat after a panel closes', () {
    test(
      'a chat sticker that comes back plays from a 1024 px page, uploaded on '
      'every frame, while the hidden panel holds the texture budget',
      () async {
        await openPanelAndClose();

        final back = scheduler.acquire('chat', 'src', chatEdge, chatEdge)!;
        uploads.clear();
        for (var frame = 3; frame < 9; frame++) {
          scheduler.want(back, frame);
          await tick();
          if (frame.isOdd) await sweep();
        }

        expect(back.texture, isNull);
        expect(back.sprite, isNotNull, reason: 'it plays on its page slot');
        expect(scheduler.leasePlaces().slotKeys, ['chat']);
        // One upload a frame, of the top 512 rows of a 1024 px page: 2 MiB.
        expect(uploads, hasLength(6));
        expect(uploads.toSet(), {(side: 1024, rows: chatEdge)});
        // Every sweep asked for a texture of its class, and the pool could
        // not make room: the budget is spent, on the panel's held cells and
        // three idle textures of their class, which together free 3 MiB of
        // the 4 a 512 px texture costs.
        expect(pool.warmsShortOfRoom, greaterThanOrEqualTo(3));
        expect(pool.bytes, pool.budgetBytes);
        expect(pool.classCounts()[256], (leased: cells, idle: 3, kept: 0));
      },
    );

    test(
      'a chat sticker that comes back takes a texture from the hidden panel',
      () async {
        await openPanelAndClose();

        final back = scheduler.acquire('chat', 'src', chatEdge, chatEdge)!;
        for (var frame = 3; frame < 9; frame++) {
          scheduler.want(back, frame);
          await tick();
          if (frame.isOdd) await sweep();
        }

        expect(back.texture, isNotNull);
      },
      // The fix proposed in native-media ticket 200: a warm for a lease on
      // screen may take textures from held leases (a hidden panel's), which
      // then show their kept frame from a slot or their still on return.
      skip: 'ticket 200: held leases keep their textures against the chat',
    );
  });
}
