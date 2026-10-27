import 'dart:ui' show Canvas, Rect, Size;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_md/flutter_md.dart';
import 'package:meta/meta.dart' show internal;

/// The one place `catalog_assets`' embed seam meets the markdown library's.
///
/// The library owns its own contract and knows no asset type, and the cache
/// owns [InlineEmbedResolver]; neither may import the other, so the root
/// package, which depends on both, translates. Every method forwards one call
/// and renames nothing but the types: a resolver written against the cache's
/// contract (`ContentEmbedResolver`, or a host's own composition by scheme)
/// is the resolver of a body.
@internal
final class ChatInlineEmbedAdapter implements MarkdownInlineEmbedResolver {
  /// Adapts [resolver] for a markdown body.
  const ChatInlineEmbedAdapter(this.resolver);

  /// The resolver whose embeds the body paints.
  final InlineEmbedResolver resolver;

  @override
  MarkdownInlineEmbed? resolve(MarkdownInlineEmbedTarget target, MarkdownInlineEmbedMetrics metrics) {
    // The cache sizes an embed by the font's height; a font that reports none
    // has nothing to size it by, so the body shows the alternative text.
    if (metrics.ascent <= 0 || metrics.descent <= 0) return null;
    final embed = resolver.resolve(
      InlineEmbedTarget(scheme: target.scheme, id: target.id, alt: target.alt),
      InlineEmbedMetrics(
        fontSize: metrics.fontSize,
        ascent: metrics.ascent,
        descent: metrics.descent,
        devicePixelRatio: metrics.devicePixelRatio,
      ),
    );
    return embed == null ? null : _AdaptedEmbed(embed);
  }
}

final class _AdaptedEmbed implements MarkdownInlineEmbed {
  _AdaptedEmbed(this._embed);

  final InlineEmbed _embed;

  @override
  Size get size => _embed.sizeHint;

  @override
  bool get visible => _embed.visible;

  @override
  set visible(bool value) => _embed.visible = value;

  @override
  void paint(Canvas canvas, Rect rect, MarkdownInlineEmbedPaintContext context) =>
      _embed.paint(canvas, rect, InlineEmbedPaintContext(tint: context.tint, opacity: context.opacity));

  @override
  void addListener(VoidCallback listener) => _embed.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _embed.removeListener(listener);

  @override
  void dispose() => _embed.dispose();
}
