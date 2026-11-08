# Changelog

All notable changes to `image_decoder` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Changed (the panel keeps its animations)

- `PlayingImagePaintable` keeps its first frame as a still
  (`AssetPaintable.firstFrame`), which a sibling binding borrows instead of
  the frame the loop is at; a playing entry charges one frame more (three
  frames plus the encoded data).

### Changed

- A decoded image is placed by `AssetPaintContext.fit` (contain by default).

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
