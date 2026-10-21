# Changelog

All notable changes to `image_decoder` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `ImageCodecDecoder`: the `catalog_assets` decoder for engine-decodable
  images, stills and animated WebP / GIF, decoded at the spec's size. It meets
  `DecoderContract`. A frame sequence plays one frame ahead of the one shown,
  by the shared playback clock, in the animated tier. A paint that does not
  animate (`AssetPaintContext.animate`) neither steps it nor starts its first
  frame, and a clock that starts again behind the shown frame restarts the
  timing instead of freezing the image. A playing image counts its two
  frames and the encoded data its codec keeps. A file on the web fails for
  good with a message that says the web needs bytes.
