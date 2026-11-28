import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// What a received message's link preview needs: nothing, a page to draw,
/// or a lookup the receiver does itself.
@immutable
sealed class ChatReceivedLinkPreview {
  const ChatReceivedLinkPreview._();

  /// The sender's page, drawn as it arrived.
  const factory ChatReceivedLinkPreview.show(MessageLinkPreview preview) =
      ChatReceivedLinkPreview$Show;

  /// A lookup of [candidates] the receiver makes through its own resolver,
  /// with the sender's [options] when there are any.
  const factory ChatReceivedLinkPreview.resolve(
    List<Uri> candidates, {
    LinkPreviewOptions? options,
  }) = ChatReceivedLinkPreview$Resolve;

  /// Reads [payload], a received message's map, whose markdown body is
  /// [body].
  ///
  /// The `linkPreview` field decides: `removed` shows nothing, a `page` is
  /// drawn, a field without a page is looked up by its URL. A message
  /// without the field (history, older clients) shows nothing, unless
  /// [resolveWithoutField] is on: then the body's URLs are looked up, as the
  /// receive-time fallback of entity detection does. It is off by default,
  /// since it asks the resolver for every such message that scrolls by.
  factory ChatReceivedLinkPreview.read(
    Map<String, Object?> payload, {
    required RichText body,
    bool resolveWithoutField = false,
    String? scrollId,
  }) => switch (LinkPreviewWire.readLinkPreview(payload, scrollId: scrollId)) {
    MessageLinkPreview(options: LinkPreviewOptions(removed: true)) => none,
    final preview? when preview.page != null => ChatReceivedLinkPreview.show(
      preview,
    ),
    final preview? => ChatReceivedLinkPreview.resolve([
      preview.options.url,
    ], options: preview.options),
    null when resolveWithoutField => switch (_urlsOf(body)) {
      [] => none,
      final urls => ChatReceivedLinkPreview.resolve(urls),
    },
    null => none,
  };

  /// No preview: the sender removed it, or the message carries none.
  static const ChatReceivedLinkPreview none = ChatReceivedLinkPreview$None();

  static List<Uri> _urlsOf(RichText body) {
    final found = EntityDetection.apply(body, DetectionPolicy.urlsOnly);
    return [
      for (final entity in found.entities)
        if (entity.kind case EntityKind$Link(:final url)) ?_absolute(url),
    ];
  }

  static Uri? _absolute(String text) => switch (Uri.tryParse(text)) {
    final uri? when uri.isAbsolute => uri,
    _ => null,
  };
}

/// See [ChatReceivedLinkPreview.none].
final class ChatReceivedLinkPreview$None extends ChatReceivedLinkPreview {
  /// No preview.
  const ChatReceivedLinkPreview$None() : super._();

  @override
  bool operator ==(Object other) => other is ChatReceivedLinkPreview$None;

  @override
  int get hashCode => (ChatReceivedLinkPreview$None).hashCode;
}

/// See [ChatReceivedLinkPreview.show].
final class ChatReceivedLinkPreview$Show extends ChatReceivedLinkPreview {
  /// The sender's [preview], page included.
  const ChatReceivedLinkPreview$Show(this.preview) : super._();

  /// The options and the page.
  final MessageLinkPreview preview;

  @override
  bool operator ==(Object other) =>
      other is ChatReceivedLinkPreview$Show && other.preview == preview;

  @override
  int get hashCode => preview.hashCode;
}

/// See [ChatReceivedLinkPreview.resolve].
final class ChatReceivedLinkPreview$Resolve extends ChatReceivedLinkPreview {
  /// A lookup of [candidates].
  const ChatReceivedLinkPreview$Resolve(this.candidates, {this.options})
    : super._();

  /// The URLs to look up, in text order.
  final List<Uri> candidates;

  /// The sender's options, or null for a message that carried none.
  final LinkPreviewOptions? options;

  @override
  bool operator ==(Object other) =>
      other is ChatReceivedLinkPreview$Resolve &&
      other.options == options &&
      listEquals(other.candidates, candidates);

  @override
  int get hashCode => Object.hash(Object.hashAll(candidates), options);
}
