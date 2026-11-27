import 'package:meta/meta.dart';

/// The limits group of the chat capabilities: how long and how large what
/// the user sends may be.
///
/// Lengths count Unicode code points, the unit of the message length budget.
@immutable
final class ChatLimits {
  /// Limits; each omitted one takes the package default.
  const ChatLimits({
    this.messageLength = defaultMessageLength,
    this.captionLength = defaultCaptionLength,
    this.fileSize,
    this.albumSize = defaultAlbumSize,
  });

  /// [messageLength] when the host sets none.
  static const defaultMessageLength = 4096;

  /// [captionLength] when the host sets none.
  static const defaultCaptionLength = 1024;

  /// [albumSize] when the host sets none.
  static const defaultAlbumSize = 10;

  /// The longest message text, in code points.
  final int messageLength;

  /// The longest media caption, in code points; zero allows no caption.
  final int captionLength;

  /// The largest file sent, in bytes; null when unlimited.
  final int? fileSize;

  /// The most media items sent as one album.
  final int albumSize;

  /// A copy with the given limits replaced; [clearFileSize] lifts the file
  /// size limit.
  ChatLimits copyWith({
    int? messageLength,
    int? captionLength,
    int? fileSize,
    bool clearFileSize = false,
    int? albumSize,
  }) => ChatLimits(
    messageLength: messageLength ?? this.messageLength,
    captionLength: captionLength ?? this.captionLength,
    fileSize: clearFileSize ? null : fileSize ?? this.fileSize,
    albumSize: albumSize ?? this.albumSize,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatLimits &&
      other.messageLength == messageLength &&
      other.captionLength == captionLength &&
      other.fileSize == fileSize &&
      other.albumSize == albumSize;

  @override
  int get hashCode =>
      Object.hash(messageLength, captionLength, fileSize, albumSize);

  @override
  String toString() =>
      'ChatLimits(messageLength: $messageLength, captionLength: '
      '$captionLength, fileSize: $fileSize, albumSize: $albumSize)';
}
