import 'dart:ui';

import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:meta/meta.dart';

/// A named recipe a surface attaches with: the logical [size] it shows an
/// asset at, and the [spec] and [profile] that size and use imply.
///
/// A surface does not choose pixels, decode modes or playback flags itself; it
/// picks a preset, so two surfaces that mean the same thing share one decode
/// (the spec is part of the entry identity) and a host changes how a class of
/// surfaces looks in one place. Presets are plain values: a host builds its
/// own with the constructor, and `AssetPresets` has the ones the packages
/// share.
@immutable
final class AssetPreset {
  /// Creates a preset showing assets at [size] (logical pixels), decoded as
  /// [spec] and used as [profile] says.
  const AssetPreset({
    required this.size,
    required this.spec,
    required this.profile,
  });

  /// The logical box the surface shows the asset in. It is the size hint of an
  /// inline embed and the natural size of a `ContentView`.
  final Size size;

  /// What is decoded: the pixels [size] takes at the device density.
  final AssetSpec spec;

  /// How the surface uses the asset.
  final AssetProfile profile;

  @override
  bool operator ==(Object other) =>
      other is AssetPreset &&
      other.size == size &&
      other.spec == spec &&
      other.profile == profile;

  @override
  int get hashCode => Object.hash(size, spec, profile);

  @override
  String toString() => 'AssetPreset($size, $spec, $profile)';
}

/// The presets of the surfaces that draw content: a cell of a content grid,
/// and a piece of content set inside message text.
abstract final class AssetPresets {
  /// A cell of a content grid or strip: a square of [extent] logical pixels,
  /// decoded at [devicePixelRatio].
  ///
  /// Plays and loops while visible unless [animate] is false (a grid that
  /// should show stills).
  static AssetPreset keyboardCell({
    required double extent,
    required double devicePixelRatio,
    bool animate = true,
  }) => _square(
    extent: extent,
    devicePixelRatio: devicePixelRatio,
    profile: AssetProfile(animate: animate),
  );

  /// Content set inline in text of [fontSize]: a square [extentPerFontSize]
  /// times the font size, because an emoji is wider than the em of the font
  /// it sits in.
  ///
  /// Plays and loops while visible unless [animate] is false. Pass
  /// [AssetDecodeMode.template] for content the surrounding text colour
  /// tints.
  static AssetPreset inlineMessage({
    required double fontSize,
    required double devicePixelRatio,
    double extentPerFontSize = 1.2,
    AssetDecodeMode decodeMode = AssetDecodeMode.original,
    bool animate = true,
  }) => _square(
    extent: fontSize * extentPerFontSize,
    devicePixelRatio: devicePixelRatio,
    decodeMode: decodeMode,
    profile: AssetProfile(animate: animate),
  );

  static AssetPreset _square({
    required double extent,
    required double devicePixelRatio,
    required AssetProfile profile,
    AssetDecodeMode decodeMode = AssetDecodeMode.original,
  }) => AssetPreset(
    size: Size.square(extent),
    spec: AssetSpec.atDensity(
      logicalWidth: extent,
      logicalHeight: extent,
      devicePixelRatio: devicePixelRatio,
      decodeMode: decodeMode,
    ),
    profile: profile,
  );
}
