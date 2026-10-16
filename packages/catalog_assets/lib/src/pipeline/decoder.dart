import 'package:catalog_assets/src/asset/asset_producer.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:catalog_assets/src/pipeline/content_fetcher.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// What a [Decoder] is asked to decode.
@immutable
final class DecodeRequest {
  /// Creates a request to decode [content] as [spec].
  const DecodeRequest({
    required this.descriptor,
    required this.spec,
    required this.part,
    required this.content,
  });

  /// What is known about the content.
  final ContentDescriptor descriptor;

  /// The pixels wanted.
  final AssetSpec spec;

  /// Whether [content] is the thumbnail or the content itself.
  final FetchPart part;

  /// The encoded data.
  final FetchedContent content;
}

/// Turns fetched data into paintables, for one media form.
///
/// Adapter packages provide decoders (a still image, a vector animation, a
/// video clip) and the host registers each in a `DecoderRegistry` under the
/// `MediaForm` it decodes. A decoder neither fetches nor caches: it gets bytes
/// and a spec and reports stages.
///
/// ## Contract
///
/// - [decode] runs on the UI isolate and returns at once. The work may use
///   isolates or native threads; results are reported on the UI isolate, and
///   synchronously from [decode] if they are already at hand.
/// - A [FetchPart.thumbnail] request ends with one `AssetStage.placeholder`.
/// - A [FetchPart.content] request reports `AssetStage.firstFrame` as soon as
///   the first frame is drawable, if it can do so earlier than the whole,
///   and ends with the stage that is final for the spec: `full`, or
///   `firstFrame` when `AssetSpec.variant` asks for the first frame only.
///   Each paintable is sized to the spec and its `bytes` is what it costs.
/// - Data it cannot decode ends the request with `AssetProgress.fail`; the
///   pipeline treats every decode failure as permanent. It never throws.
/// - It reports nothing after the returned task is cancelled, and a paintable
///   passed to `advance` belongs to the cache from that call on.
abstract interface class Decoder {
  /// Starts decoding [request], reporting to [progress].
  AssetTask decode(DecodeRequest request, AssetProgress progress);
}

/// The decoders of a host, one per `MediaForm`.
///
/// The pipeline looks the decoder of a descriptor's media form up here; a
/// form with none leaves its entries at `AssetStage.none`. The glyph form has
/// no decoder on purpose: unicode glyphs bind to baked sprites through the
/// scope's glyph source and never reach the pipeline.
final class DecoderRegistry {
  /// Creates an empty registry.
  DecoderRegistry();

  final Map<MediaForm, Decoder> _decoders = {};

  /// Registers [decoder] for [form].
  ///
  /// Throws an [ArgumentError] for [MediaForm.glyph] and [MediaForm.unknown],
  /// which are not decoded, and a [StateError] if [form] already has a
  /// decoder: two adapters claiming one form is a wiring bug to see.
  void register(MediaForm form, Decoder decoder) {
    if (form == MediaForm.glyph || form == MediaForm.unknown) {
      throw ArgumentError.value(
        form,
        'form',
        'is not decoded: glyphs bind through the scope glyph source and an '
            'unknown form has nothing to decode',
      );
    }
    if (_decoders.containsKey(form)) {
      throw StateError('A decoder is already registered for ${form.name}.');
    }
    _decoders[form] = decoder;
  }

  /// The decoder registered for [form], or null.
  Decoder? decoderFor(MediaForm form) => _decoders[form];
}
