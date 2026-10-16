import 'package:flutter/widgets.dart';

/// Strip / section chrome for one category.
@immutable
sealed class EmojiStripIcon {
  const EmojiStripIcon();

  /// Unicode glyph drawn in the category strip.
  const factory EmojiStripIcon.glyph(String glyph) = EmojiStripIconGlyph;

  /// Package-relative asset path for the strip cell.
  const factory EmojiStripIcon.asset(String assetPath, {String? package}) =
      EmojiStripIconAsset;

  /// Host-built widget (custom packs, branded art).
  const factory EmojiStripIcon.widget(WidgetBuilder builder) =
      EmojiStripIconWidget;
}

/// Unicode glyph drawn in the category strip.
@immutable
final class EmojiStripIconGlyph extends EmojiStripIcon {
  /// Creates a glyph strip icon.
  const EmojiStripIconGlyph(this.glyph);

  /// Glyph to paint.
  final String glyph;
}

/// Package-relative asset path for the strip cell.
@immutable
final class EmojiStripIconAsset extends EmojiStripIcon {
  /// Creates an asset strip icon.
  const EmojiStripIconAsset(this.assetPath, {this.package});

  /// Asset path.
  final String assetPath;

  /// Optional package name for [Image.asset].
  final String? package;
}

/// Host-built strip cell content.
@immutable
final class EmojiStripIconWidget extends EmojiStripIcon {
  /// Creates a widget strip icon.
  const EmojiStripIconWidget(this.builder);

  /// Builds the strip cell (selection tint is host-owned).
  final WidgetBuilder builder;
}
