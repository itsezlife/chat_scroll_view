/// A `Decoder` for `catalog_assets` over the image codecs of the engine:
/// stills (PNG, JPEG, WebP, GIF, BMP) and frame sequences (animated WebP and
/// GIF), decoded at the size of the entry's spec.
///
/// The host registers one [ImageCodecDecoder] in its `DecoderRegistry` under
/// each media form whose content arrives in these formats.
library;

export 'src/image_codec_decoder.dart';
