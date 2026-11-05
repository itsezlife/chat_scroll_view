import 'package:catalog_assets/src/pool/frame_renderer.dart';
import 'package:catalog_assets/src/pool/frame_slot_allocator.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a [FrameRenderer] contract run needs besides the renderer.
final class FrameRendererHarness {
  /// Creates a harness around [renderer], which writes into [memory].
  const FrameRendererHarness({
    required this.renderer,
    required this.memory,
    required this.job,
    required this.unrenderable,
  });

  /// The renderer under test.
  final FrameRenderer renderer;

  /// The memory it writes into. Its page side must be a multiple of 64.
  final FramePageMemory memory;

  /// A job for frame [frame] of an animation the renderer can render, drawn
  /// at 48 x 48 pixels into [slot] (which is 64 x 64). Frames 0 and 1 must
  /// look different.
  final FrameJob Function(FrameSlot slot, int frame) job;

  /// A job the renderer cannot render (a file it rejects).
  final FrameJob Function(FrameSlot slot) unrenderable;
}

/// The behaviour every [FrameRenderer] shares, run over its fake and over a
/// native adapter alike.
abstract final class FrameRendererContract {
  /// Registers the contract's tests; [create] builds a fresh harness for each.
  static void run(FrameRendererHarness Function() create) {
    group('FrameRenderer contract', () {
      late FrameRendererHarness harness;
      late FrameSlotAllocator allocator;

      setUp(() {
        harness = create();
        allocator = FrameSlotAllocator(
          pageSide: harness.memory.pageSide,
          maxPages: 2,
          sizeClasses: const [64],
        );
      });

      List<int> region(FrameSlot slot) {
        final side = harness.memory.pageSide;
        final bytes = harness.memory.page(slot.pageIndex);
        final out = <int>[];
        for (var y = slot.rect.top.toInt(); y < slot.rect.bottom; y++) {
          for (var x = slot.rect.left.toInt(); x < slot.rect.right; x++) {
            final at = (y * side + x) * 4;
            out.addAll(bytes.sublist(at, at + 4));
          }
        }
        return out;
      }

      List<int> wholePage(int pageIndex) =>
          List<int>.of(harness.memory.page(pageIndex));

      test('an empty batch renders nothing and completes', () async {
        final rendered = await harness.renderer.render(
          const <FrameJob>[],
          harness.memory,
        );

        expect(rendered, isEmpty);
      });

      test('a job is answered once it has written its frame', () async {
        final slot = allocator.allocate(48, 48)!;
        final job = harness.job(slot, 0);

        final rendered = await harness.renderer.render([job], harness.memory);

        expect(rendered, [job]);
        expect(
          region(slot).any((byte) => byte != 0),
          isTrue,
          reason: 'the frame is in the slot',
        );
      });

      test('pixels are premultiplied: no channel above alpha', () async {
        final slot = allocator.allocate(48, 48)!;

        await harness.renderer.render([harness.job(slot, 0)], harness.memory);

        final pixels = region(slot);
        for (var i = 0; i < pixels.length; i += 4) {
          final alpha = pixels[i + 3];
          expect(pixels[i], lessThanOrEqualTo(alpha), reason: 'red at $i');
          expect(
            pixels[i + 1],
            lessThanOrEqualTo(alpha),
            reason: 'green at $i',
          );
          expect(pixels[i + 2], lessThanOrEqualTo(alpha), reason: 'blue at $i');
        }
      });

      test('a job writes inside its slot and nowhere else', () async {
        final slot = allocator.allocate(48, 48)!;
        final other = allocator.allocate(48, 48)!;
        final beforeOther = region(other);
        final outside = wholePage(slot.pageIndex);

        await harness.renderer.render([harness.job(slot, 0)], harness.memory);

        expect(
          region(other),
          beforeOther,
          reason: 'the neighbour is untouched',
        );
        final after = wholePage(slot.pageIndex);
        final side = harness.memory.pageSide;
        for (var i = 0; i < after.length; i++) {
          final pixel = i ~/ 4;
          final x = pixel % side;
          final y = pixel ~/ side;
          if (slot.rect.contains(Offset(x.toDouble(), y.toDouble()))) {
            continue;
          }
          expect(after[i], outside[i], reason: 'byte $i is outside the slot');
        }
      });

      test('a later frame replaces the one in the slot', () async {
        final slot = allocator.allocate(48, 48)!;
        await harness.renderer.render([harness.job(slot, 0)], harness.memory);
        final first = region(slot);

        await harness.renderer.render([harness.job(slot, 1)], harness.memory);

        expect(region(slot), isNot(first));
      });

      test('a batch renders every slot on every page it names', () async {
        final slots = [for (var i = 0; i < 6; i++) allocator.allocate(48, 48)!];
        final jobs = [for (final slot in slots) harness.job(slot, 0)];

        final rendered = await harness.renderer.render(jobs, harness.memory);

        expect(rendered, unorderedEquals(jobs));
      });

      test(
        'a job it cannot render is left out and spares the others',
        () async {
          final good = allocator.allocate(48, 48)!;
          final bad = allocator.allocate(48, 48)!;
          final beforeBad = region(bad);
          final goodJob = harness.job(good, 0);

          final rendered = await harness.renderer.render([
            harness.unrenderable(bad),
            goodJob,
          ], harness.memory);

          expect(rendered, [goodJob]);
          expect(
            region(bad),
            beforeBad,
            reason: 'the failed slot keeps its frame',
          );
        },
      );
    });
  }
}
