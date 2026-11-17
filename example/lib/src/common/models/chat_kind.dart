import 'package:mpx_core/mpx_core.dart';

/// The class of a conversation, as the auto-download policy weighs it.
///
/// Each kind is one of the media core's well-known tags: the policy's
/// presets may let a private chat download more than a channel. A surface of
/// the chat (its bodies' embeds, its stickers and GIFs) attaches with the
/// tag of the chat it shows; a panel has none and reads the policy's default.
enum ChatKind {
  /// A one-to-one chat.
  privateChat(AutoDownloadContext.privateChats),

  /// A group chat.
  group(AutoDownloadContext.groups),

  /// A channel.
  channel(AutoDownloadContext.channels);

  const ChatKind(this.downloadContext);

  /// The tag this kind's surfaces attach with.
  final AutoDownloadContext downloadContext;
}
