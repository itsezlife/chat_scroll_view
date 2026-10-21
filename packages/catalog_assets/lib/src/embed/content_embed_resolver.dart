import 'package:catalog_assets/src/asset/asset_cache_scope.dart';
import 'package:catalog_assets/src/asset/asset_preset.dart';
import 'package:catalog_assets/src/embed/content_embed.dart';
import 'package:catalog_assets/src/embed/inline_embed.dart';
import 'package:content_model/content_model.dart';

/// An [InlineEmbedResolver] that resolves a target spelled as the storage
/// encoding of a `ContentKey` (`unicode:1F44D`, `document:5368`,
/// `external:...`, the schemes the rich-text markdown helper writes) to a
/// [ContentEmbed] on one [AssetCacheScope].
///
/// A target whose scheme is not a content scheme (a mention, a web link), or
/// whose id does not read as a key, is not this resolver's: it returns null
/// and the body shows the alternative text. Every embed it makes attaches to
/// the scope and is the body's to dispose.
final class ContentEmbedResolver implements InlineEmbedResolver {
  /// Creates a resolver over [scope].
  ///
  /// [presetFor] chooses the preset of an embed from the text around it; by
  /// default `AssetPresets.inlineMessage` at that font size and density.
  ContentEmbedResolver({
    required AssetCacheScope scope,
    AssetPreset Function(InlineEmbedMetrics metrics)? presetFor,
  }) : _scope = scope,
       _presetFor = presetFor ?? _inlineMessage;

  final AssetCacheScope _scope;
  final AssetPreset Function(InlineEmbedMetrics metrics) _presetFor;

  static AssetPreset _inlineMessage(InlineEmbedMetrics metrics) =>
      AssetPresets.inlineMessage(
        ascent: metrics.ascent,
        descent: metrics.descent,
        devicePixelRatio: metrics.devicePixelRatio,
      );

  @override
  InlineEmbed? resolve(InlineEmbedTarget target, InlineEmbedMetrics metrics) {
    final content = ContentKey.tryParse('${target.scheme}:${target.id}');
    if (content == null) return null;
    return ContentEmbed(
      scope: _scope,
      content: content,
      preset: _presetFor(metrics),
    );
  }
}
