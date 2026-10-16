import 'dart:async';

import 'package:catalog_assets/src/asset/asset_cache_budgets.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:catalog_assets/src/pipeline/content_fetcher.dart';
import 'package:catalog_assets/src/pipeline/decoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a [Decoder] contract run needs besides the decoder.
final class DecoderHarness {
  /// Creates a harness around [decoder].
  const DecoderHarness({
    required this.decoder,
    required this.valid,
    required this.invalid,
  });

  /// The decoder under test.
  final Decoder decoder;

  /// A request for [part] of content the decoder can decode, as [spec].
  final DecodeRequest Function(FetchPart part, AssetSpec spec) valid;

  /// A content request whose data cannot be decoded.
  final DecodeRequest Function() invalid;
}

/// Everything a decoder reported, and when it was done.
final class _Report implements AssetProgress {
  final List<({AssetStage stage, int bytes, AssetTier tier})> advances = [];
  final List<AssetPaintable> paintables = [];
  Object? error;
  bool failed = false;
  bool cancelledByDecoder = false;
  final Completer<void> _done = Completer();

  Future<void> get done => _done.future;

  @override
  void advance(
    AssetStage stage,
    AssetPaintable paintable, {
    required int bytes,
    AssetTier tier = AssetTier.still,
  }) {
    advances.add((stage: stage, bytes: bytes, tier: tier));
    paintables.add(paintable);
    _maybeDone();
  }

  @override
  void fail(
    Object error, [
    StackTrace? stackTrace,
    AssetFailureKind kind = AssetFailureKind.transient,
  ]) {
    failed = true;
    this.error = error;
    _complete();
  }

  @override
  void cancelled() {
    cancelledByDecoder = true;
    _complete();
  }

  AssetStage? finalStage;

  void _maybeDone() {
    if (finalStage != null && advances.last.stage == finalStage) _complete();
  }

  void _complete() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// The contract every [Decoder] meets; see its documentation.
abstract final class DecoderContract {
  /// Runs it as a test group. [create] builds a fresh harness for each test.
  static void run(DecoderHarness Function() create) {
    group('Decoder contract', () {
      late DecoderHarness harness;

      setUp(() => harness = create());

      Future<_Report> decode(
        DecodeRequest request, {
        required AssetStage until,
      }) async {
        final report = _Report()..finalStage = until;
        final task = harness.decoder.decode(request, report);
        await report.done.timeout(
          const Duration(seconds: 10),
          onTimeout: () => fail('the decoder never finished ${request.part}'),
        );
        task.cancel();
        return report;
      }

      const full = AssetSpec(pixelWidth: 64, pixelHeight: 64);
      const firstFrameOnly = AssetSpec(
        pixelWidth: 64,
        pixelHeight: 64,
        variant: AssetVariant.firstFrame,
      );

      test('ends a thumbnail with one placeholder', () async {
        final report = await decode(
          harness.valid(FetchPart.thumbnail, full),
          until: AssetStage.placeholder,
        );

        expect(report.failed, isFalse);
        expect(report.advances.map((a) => a.stage), [AssetStage.placeholder]);
      });

      test('ends content with the full stage, improving only', () async {
        final report = await decode(
          harness.valid(FetchPart.content, full),
          until: AssetStage.full,
        );

        final stages = report.advances.map((a) => a.stage).toList();
        expect(stages.last, AssetStage.full);
        expect(stages, isNot(contains(AssetStage.placeholder)));
        for (var i = 1; i < stages.length; i++) {
          expect(
            stages[i].index,
            greaterThanOrEqualTo(stages[i - 1].index),
            reason: 'a stage never goes backwards: $stages',
          );
        }
      });

      test('ends first-frame-only content at the first frame', () async {
        final report = await decode(
          harness.valid(FetchPart.content, firstFrameOnly),
          until: AssetStage.firstFrame,
        );

        expect(report.advances.map((a) => a.stage).toSet(), {
          AssetStage.firstFrame,
        });
      });

      test('reports what each paintable costs', () async {
        final report = await decode(
          harness.valid(FetchPart.content, full),
          until: AssetStage.full,
        );

        expect(report.advances, isNotEmpty);
        for (final advance in report.advances) {
          expect(advance.bytes, greaterThan(0));
        }
      });

      test(
        'fails undecodable data through the progress, not by throwing',
        () async {
          final report = _Report();
          late final AssetTask task;

          expect(
            () => task = harness.decoder.decode(harness.invalid(), report),
            returnsNormally,
          );
          await report.done.timeout(
            const Duration(seconds: 10),
            onTimeout: () => fail('the decoder never reported the bad data'),
          );
          task.cancel();

          expect(report.failed, isTrue);
          expect(report.advances, isEmpty);
        },
      );

      test('reports nothing after it is cancelled', () async {
        final report = _Report()..finalStage = AssetStage.full;
        final task = harness.decoder.decode(
          harness.valid(FetchPart.content, full),
          report,
        );
        task.cancel();
        final seen = report.advances.length;

        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(report.advances, hasLength(seen));
      });
    });
  }
}
