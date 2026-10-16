import 'dart:ui' show Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colours of "nothing here yet": empty-state text, field hints and the
/// skeleton fill drawn while content loads.
///
/// Derived from a [ChromePalette] by [PlaceholderTokens.fromPalette]; a host
/// overrides single fields with [copyWith] or supplies the whole group to a
/// `ChromeThemeScope`.
@immutable
final class PlaceholderTokens {
  /// A placeholder token group with every colour given.
  const PlaceholderTokens({
    required this.emptyState,
    required this.fieldHint,
    required this.skeleton,
  });

  /// The default mapping of [palette] roles onto placeholder fields.
  factory PlaceholderTokens.fromPalette(ChromePalette palette) =>
      PlaceholderTokens(
        emptyState: palette.onSurfaceMuted,
        fieldHint: palette.onSurfaceMuted,
        skeleton: palette.onSurface.withAlpha(0x0F),
      );

  /// Text of an empty list or a search with no results.
  final Color emptyState;

  /// Hint text of an empty input field.
  final Color fieldHint;

  /// Skeleton shape fill, translucent over the surface it sits on.
  final Color skeleton;

  /// A copy with the named fields replaced.
  PlaceholderTokens copyWith({
    Color? emptyState,
    Color? fieldHint,
    Color? skeleton,
  }) => PlaceholderTokens(
    emptyState: emptyState ?? this.emptyState,
    fieldHint: fieldHint ?? this.fieldHint,
    skeleton: skeleton ?? this.skeleton,
  );

  /// Interpolates every field between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static PlaceholderTokens lerp(
    PlaceholderTokens a,
    PlaceholderTokens b,
    double t,
  ) => PlaceholderTokens(
    emptyState: Color.lerp(a.emptyState, b.emptyState, t)!,
    fieldHint: Color.lerp(a.fieldHint, b.fieldHint, t)!,
    skeleton: Color.lerp(a.skeleton, b.skeleton, t)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaceholderTokens &&
          emptyState == other.emptyState &&
          fieldHint == other.fieldHint &&
          skeleton == other.skeleton;

  @override
  int get hashCode => Object.hash(emptyState, fieldHint, skeleton);

  @override
  String toString() => 'PlaceholderTokens(emptyState: $emptyState)';
}
