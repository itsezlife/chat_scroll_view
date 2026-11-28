import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart'
    show
        LinkPreviewState$Loaded,
        LinkPreviewState$None,
        LinkPreviewState$Pending;
import 'package:flutter/widgets.dart';

/// A [DraftOptionsBubbleBuilder] for tests: a plain box naming the preview's
/// state in chrome text, keeping each preview it was asked for.
final class FakeDraftBubbleBuilder {
  final List<DraftOptionsPreview> _previews = [];

  /// The key of the bubble it builds.
  static const Key bubbleKey = ValueKey('fakeDraftBubble');

  /// Every preview built, oldest first.
  List<DraftOptionsPreview> get previews => List.unmodifiable(_previews);

  /// The builder to hand the overlay.
  Widget call(BuildContext context, DraftOptionsPreview preview) {
    _previews.add(preview);
    final part = preview.part;
    final page = switch (preview.page) {
      LinkPreviewState$Loaded() => 'loaded',
      LinkPreviewState$Pending() => 'pending',
      LinkPreviewState$None() => 'none',
    };
    return SizedBox(
      key: bubbleKey,
      width: 240,
      height: 120,
      child: Text(
        '$page ${part.options.media.value}'
        '${part.invertMedia ? ' above' : ''}'
        '${part.options.removed ? ' removed' : ''}',
        style: ChromeTypography.of(context),
      ),
    );
  }
}
