import 'dart:ui' show Size;

import 'package:content_model/content_model.dart' show ContentSize;
import 'package:meta/meta.dart';

/// What the lone document of a message is to the user, when the message is
/// that document and nothing else: a sticker sent as such, or a GIF.
///
/// A lone custom emoji is neither: it is an emoji drawn large, sized by the
/// emoji-only policy (`ChatEmojiPolicy.stickerExtentFor`).
enum ChatMediaKind {
  /// A sticker: fitted in a square, its own proportion kept.
  sticker,

  /// A GIF (an animated image or a short silent clip): sized by its own
  /// proportion.
  gif,
}

/// A message's lone sticker or GIF, as the host knows it before it loads.
///
/// The host builds it from what it holds of the document (its kind and the
/// source size, `ContentDescriptor.size`); the viewport never looks the
/// document up.
@immutable
final class ChatMediaItem {
  /// A [kind] of [source] pixels, or of an unknown size.
  const ChatMediaItem({required this.kind, this.source});

  /// What the document is.
  final ChatMediaKind kind;

  /// The source media's size in pixels, or null when the host does not know
  /// it: the policy then falls back to a shape of its own (a square).
  final ContentSize? source;

  @override
  bool operator ==(Object other) =>
      other is ChatMediaItem && other.kind == kind && other.source == source;

  @override
  int get hashCode => Object.hash(kind, source);

  @override
  String toString() => 'ChatMediaItem(${kind.name}, $source)';
}

/// The **media size policy**: how large a message's lone sticker or GIF is
/// drawn, the host's to choose.
///
/// The clients differ in kind: a phone sizes a sticker by a share of the
/// screen and a GIF by a share of the chat's width with a floor on its height,
/// a desktop fits both in fixed boxes whatever the window. So the viewport
/// holds no rule: the host passes one strategy per platform family, and the
/// emoji-only body (`ChatEmojiBody`, its sticker layout) lays out and decodes
/// at the size it answers. Pure Dart, read while the body builds: answer from
/// the arguments alone.
abstract interface class ChatMediaSizePolicy {
  /// The logical size [item] is drawn at, for a screen of [viewport] (the
  /// `MediaQuery` size) and a chat [parentWidth] wide (the chat column's
  /// width, the viewport's when the chat is the whole window).
  ///
  /// The size is the art's: the body adds no margin around it.
  Size sizeFor(
    ChatMediaItem item, {
    required Size viewport,
    required double parentWidth,
  });

  /// The most device pixels the longer side of a decode takes, or null for
  /// none: a box larger than that at the screen's density is drawn from a
  /// decode of this size (the shorter side scaled with it).
  int? get maxDecodeExtent;
}
