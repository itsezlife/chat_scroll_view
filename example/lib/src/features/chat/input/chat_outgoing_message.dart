import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// What one send of the composer hands the screen: the markdown body and
/// the message's link preview fields beside it (ADR 034's amendment).
@immutable
final class ChatOutgoingMessage {
  /// A message of [body], with [linkPreview] and [invertMedia] when the
  /// composer has them.
  const ChatOutgoingMessage({
    required this.body,
    this.linkPreview,
    this.invertMedia = false,
  });

  /// The markdown body.
  final String body;

  /// The link preview: its options and, when the composer had it loaded,
  /// the page. A receiver that gets no page resolves the URL itself.
  final MessageLinkPreview? linkPreview;

  /// Whether the message puts its media above its text.
  final bool invertMedia;

  /// The message payload: `{ body, linkPreview?, invertMedia? }`, the two
  /// link preview fields in `LinkPreviewWire`'s form.
  Map<String, Object?> toJson() {
    final json = <String, Object?>{'body': body};
    LinkPreviewWire.write(
      json,
      linkPreview: linkPreview,
      invertMedia: invertMedia,
    );
    return json;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatOutgoingMessage &&
      other.body == body &&
      other.linkPreview == linkPreview &&
      other.invertMedia == invertMedia;

  @override
  int get hashCode => Object.hash(body, linkPreview, invertMedia);

  @override
  String toString() =>
      'ChatOutgoingMessage(${body.length} chars, $linkPreview, '
      'invertMedia: $invertMedia)';
}
