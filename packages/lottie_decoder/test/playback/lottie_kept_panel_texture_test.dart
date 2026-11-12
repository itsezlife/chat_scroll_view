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
/// its page slot sits on a 512 px page of its own. The panel's cells are
/// 240 px, the 256 px class: 1 MiB a texture.
///
/// The panel docks beside the chat, so the chat plays while it is open. When
/// it opens, the chat's viewport shrinks and the sticker leaves the screen;
/// its texture idles, keeping its frame. The panel's cells fill the budget,
/// which destroys that idle texture for room. A panel that moves, or sits
/// under a sheet, holds its cells on screen (ADR 043 *Amendment: leases of a
/// kept panel*): they keep their textures. A hidden panel shows nothing: its
/// cells give their textures back keeping their frames, and keep their
/// leases.
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

  // The panel open beside the chat: the chat's sticker away, the panel's
  // cells playing on textures. Returns the cells.
  Future<List<LottieFrameLease>> openPanel() async {
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
    return panel;
  }

  // The panel's surface holds its cells: on screen (moving, or under a
  // sheet), or hidden, where every cell also left the screen.
  void hold(List<LottieFrameLease> panel, {required bool hidden}) {
    for (final cell in panel) {
      cell.kept = true;
      if (hidden) cell.releaseUnlessPainted();
    }
    timers.elapse(Duration.zero);
  }

  // Up to the panel's close: the chat's sticker away, the panel's cells
  // held, hidden unless [hidden] is false. Returns the cells.
  Future<List<LottieFrameLease>> openPanelAndClose({bool hidden = true}) async {
    final panel = await openPanel();
    hold(panel, hidden: hidden);
    return panel;
  }

  // What the kept budget holds of the panel's cells, 1 MiB each.
  int keptCells() => pool.keptFrameBytes ~/ pool.bytesOfClass(256);

  group('the chat after a panel closes', () {
    test('a chat sticker that comes back while the panel is held on screen '
        'plays from a 512 px page of its own, 1 MiB an upload', () async {
      await openPanelAndClose(hidden: false);

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
      // One upload a frame, of a 512 px page that holds this cell alone.
      expect(uploads, hasLength(6));
      expect(uploads.toSet(), {(side: chatEdge, rows: chatEdge)});
      // Every sweep asked for a texture of its class, and the pool could
      // not make room: the budget is spent, on the panel's held cells and
      // three idle textures of their class, which together free 3 MiB of
      // the 4 a 512 px texture costs.
      expect(pool.warmsShortOfRoom, greaterThanOrEqualTo(3));
      expect(pool.bytes, pool.budgetBytes);
      expect(pool.classCounts()[256], (leased: cells, idle: 3, kept: 0));
    });

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
        expect(scheduler.leasePlaces().slotKeys, isEmpty);
      },
    );

    test('a warm for the chat takes the textures the hidden panel kept '
        'frames on, when nothing else makes room', () async {
      final panel = await openPanelAndClose();
      // The budget held by the panel's kept frames and the chat's warm.
      final room = pool.budgetBytes - pool.bytes;
      final chats = room ~/ pool.bytesOfClass(chatEdge) + 1;

      await pool.warm(chatEdge, chats);

      expect(pool.classCounts()[chatEdge]!.idle, chats);
      expect(pool.keptFrames, lessThan(keptCells()));
      expect(panel.map((cell) => cell.isReleased), everyElement(isFalse));
    });
  });

  group('a hidden panel', () {
    test(
      'gives its textures back keeping their frames, and its leases stay',
      () async {
        final panel = await openPanelAndClose();

        expect(panel.map((cell) => cell.isReleased), everyElement(isFalse));
        expect(scheduler.leasePlaces().onTextures, 0);
        expect(pool.leasedTextures, 0);
        // As many frames as the kept budget holds; the idle limit destroyed
        // the other textures of the class.
        expect(pool.classCounts()[256], (
          leased: 0,
          idle: keptCells(),
          kept: keptCells(),
        ));
        expect(pool.bytes, keptCells() * pool.bytesOfClass(256));
      },
    );

    test('shown again, its cells within the kept budget show their frames at '
        'once, rendering nothing', () async {
      final panel = await openPanelAndClose();
      writer.batches.clear();

      // The panel shows again, still held while it moves in: each cell is
      // painted at the frame it was held on.
      for (final cell in panel) {
        scheduler.want(cell, 3);
      }
      await tick();

      // The cells that gave their textures back last kept their frames.
      final back = panel.sublist(cells - keptCells());
      expect(back.map((cell) => cell.texture), everyElement(isNotNull));
      expect(writer.batches, isEmpty, reason: 'no frame rendered again');
      // The others play on page slots until textures are free for them.
      final lost = panel.sublist(0, cells - keptCells());
      expect(lost.map((cell) => cell.texture), everyElement(isNull));
      expect(scheduler.leasePlaces().onTextures, keptCells());
    });

    test("a cell that lost its frame does not take another cell's", () async {
      final panel = await openPanelAndClose();

      // The first cell lost its frame to the budget; it is painted first.
      scheduler
        ..want(panel.first, 3)
        ..want(panel.last, 3);

      expect(panel.first.texture, isNull);
      expect(panel.last.texture, isNotNull);
    });

    test('a cell painted in the frame that hid it keeps its texture', () async {
      final panel = await openPanel();
      for (final cell in panel) {
        cell
          ..kept = true
          ..releaseUnlessPainted();
      }
      scheduler.want(panel.first, 3);
      timers.elapse(Duration.zero);

      expect(panel.first.texture, isNotNull);
      expect(scheduler.leasePlaces().onTextures, 1);
    });

    test('a cell disposed while hidden forgets its kept frame', () async {
      final panel = await openPanelAndClose();
      final kept = pool.keptFrames;

      panel.last.release();
      scheduler.forget('cell${cells - 1}');

      expect(pool.keptFrames, kept - 1);
    });
  });
}
