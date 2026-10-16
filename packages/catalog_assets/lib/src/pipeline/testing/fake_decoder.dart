import 'dart:math' as math;
import 'dart:typed_data';

import 'package:catalog_assets/src/asset/asset_cache_budgets.dart';
import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:catalog_assets/src/asset/testing/fake_asset_paintable.dart';
import 'package:catalog_assets/src/pipeline/content_fetcher.dart';
import 'package:catalog_assets/src/pipeline/decoder.dart';

/// One decode a [FakeDecoder] was asked for; a test plays the codec by
/// calling [complete] and [fail].
final class FakeDecode implements AssetTask {
  FakeDecode._(this.request, this._progress, this._decoder);

  /// What was asked for.
  final DecodeRequest request;

  final AssetProgress _progress;
  final FakeDecoder _decoder;
  bool _settled = false;

  /// Whether the pipeline cancelled this decode.
  bool isCancelled = false;

  /// Whether the decode has an outcome (final stage, failure or cancel).
  bool get isSettled => _settled;

  /// Paintables this decode handed to the cache, oldest first.
  final List<FakeAssetPaintable> paintables = [];

  /// Reports the stages a decoder of this request ends with: a placeholder
  /// for a thumbnail; for content the first frame (when the decoder is set to
  /// report it early and the spec wants more) and the final stage. Fails
  /// instead when the data is [FakeDecoder.corrupt]. Does nothing once
  /// settled.
  void complete() {
    if (_settled) return;
    final content = request.content;
    if (content is FetchedBytes && _same(content.bytes, FakeDecoder.corrupt)) {
      fail(const FormatException('cannot decode'));
      return;
    }
    switch (request.part) {
      case FetchPart.thumbnail:
        _advance(AssetStage.placeholder, last: true);
      case FetchPart.content:
        final firstFrameOnly = request.spec.variant == AssetVariant.firstFrame;
        if (_decoder.reportFirstFrame && !firstFrameOnly) {
          _advance(AssetStage.firstFrame);
        }
        _advance(
          firstFrameOnly ? AssetStage.firstFrame : AssetStage.full,
          last: true,
        );
    }
  }

  /// Reports one stage without ending the decode, as a decoder that is still
  /// working on the full asset does.
  FakeAssetPaintable advance(AssetStage stage) => _advance(stage);

  /// Fails the decode. Does nothing once settled.
  void fail(Object error) {
    if (_settled) return;
    _settle();
    _progress.fail(error, StackTrace.current, AssetFailureKind.permanent);
  }

  @override
  void cancel() {
    isCancelled = true;
    _settle();
  }

  // [last] ends the decode before reporting, as a real decoder is done
  // before the consumer reacts to its last stage.
  FakeAssetPaintable _advance(AssetStage stage, {bool last = false}) {
    final paintable = FakeAssetPaintable(
      label: '${request.descriptor.key}@${request.part.name}.${stage.name}',
      isAnimated: request.descriptor.animated,
    );
    paintables.add(paintable);
    if (last) _settle();
    _progress.advance(
      stage,
      paintable,
      bytes: request.spec.estimatedBytes,
      tier: request.descriptor.animated ? AssetTier.animated : AssetTier.still,
    );
    return paintable;
  }

  void _settle() {
    if (_settled) return;
    _settled = true;
    _decoder._active--;
  }

  static bool _same(Uint8List a, Uint8List b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
}

/// An in-memory [Decoder] for tests: it "decodes" any bytes into a
/// [FakeAssetPaintable] and either answers at once or waits for the test.
///
/// Follows the whole seam contract. Bytes equal to [corrupt] cannot be
/// decoded.
final class FakeDecoder implements Decoder {
  /// Creates a decoder. With [autoRespond] each decode ends inside `decode`;
  /// without it each waits for [FakeDecode.complete]. [reportFirstFrame] makes
  /// a full-variant content decode report `firstFrame` before `full`.
  FakeDecoder({this.autoRespond = true, this.reportFirstFrame = false});

  /// Bytes this decoder cannot decode.
  static final Uint8List corrupt = Uint8List.fromList(const [0xBA, 0xD0]);

  /// Whether decodes end by themselves.
  final bool autoRespond;

  /// Whether a content decode reports the first frame early.
  final bool reportFirstFrame;

  /// Every decode, oldest first.
  final List<FakeDecode> decodes = [];
  int _active = 0;
  int _peak = 0;

  /// How many decodes are unsettled right now.
  int get active => _active;

  /// The most decodes that were ever unsettled at once.
  int get peakConcurrency => _peak;

  /// Decodes that have no outcome yet.
  List<FakeDecode> get pending => [
    for (final decode in decodes)
      if (!decode.isSettled) decode,
  ];

  @override
  AssetTask decode(DecodeRequest request, AssetProgress progress) {
    final decode = FakeDecode._(request, progress, this);
    decodes.add(decode);
    _peak = math.max(_peak, ++_active);
    if (autoRespond) decode.complete();
    return decode;
  }
}
