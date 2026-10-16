# Changelog

All notable changes to `image_decoder` are documented in this file. The format
is loosely based on [Keep a Changelog](https://keepachangelog.com/); this
package is pre-1.0.

## [Unreleased]

### Added

- `ImageCodecDecoder`: the `catalog_assets` decoder for engine-decodable
  images, stills and animated WebP / GIF, decoded at the spec's size. It meets
  `DecoderContract`. A frame sequence plays one frame ahead of the one shown,
  by the shared playback clock, in the animated tier.
