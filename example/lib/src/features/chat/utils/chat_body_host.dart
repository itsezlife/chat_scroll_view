import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatEmojiEmbedFactory, ChatStickerPlayback;
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_play_memory.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// What a message body needs from the chat screen besides the message: the
/// seams that connect the two bodies of the viewport (`ChatMarkdownBody`,
/// `ChatEmojiBody`) to the host's asset cache and decisions.
///
/// One per chat screen, created with it (ADR 029: per-chat controllers), and
/// kept for its life. The embed seams are stable instances because a body
/// disposes and re-makes every embed when handed a different one.
final class ChatBodyHost {
  /// Connects the bodies to [assets] and weighs [policy] for each message.
  ///
  /// [stickerFor] is the host's `unicode` to `document` map for a lone emoji;
  /// by default the animated pack's. [plays] is the memory of what already
  /// played on this screen. [playbackFor] is the host's choice of how the
  /// sticker of an emoji plays, from the kind of asset and the user's
  /// animation settings; by default the reference client's (a unicode emoji
  /// plays once and rests on the first frame, a custom emoji loops).
  ChatBodyHost({
    required AssetCacheScope assets,
    required this.policy,
    ContentKey? Function(ContentKey key) stickerFor =
        AnimatedEmojiPack.stickerFor,
    StickerPlayMemory? plays,
    this.playbackFor = ChatStickerPlayback.defaultFor,
  }) : embedResolver = ContentEmbedResolver(scope: assets),
       embedFactory = ((content, preset) =>
           ContentEmbed(scope: assets, content: content, preset: preset)),
       plays = plays ?? StickerPlayMemory(),
       _stickerFor = stickerFor;

  /// Turns the image spans of a markdown body (`![alt](document:id)`) into
  /// embeds on the cache. A target that is not content (a link, a mention)
  /// is not its to resolve.
  final InlineEmbedResolver embedResolver;

  /// Makes the embed of an emoji-only body's item. It is not an
  /// [InlineEmbedResolver]: the emoji-only body sizes by count with presets
  /// of its own, which a resolver given only text metrics cannot carry.
  final ChatEmojiEmbedFactory embedFactory;

  /// The host's decision for each message, live: the user's setting changes
  /// it while the screen is open.
  final ValueListenable<LargeEmojiPolicy> policy;

  /// Which stickers this screen already played.
  final StickerPlayMemory plays;

  final ContentKey? Function(ContentKey key) _stickerFor;

  /// How the sticker of the lone emoji [emoji] plays.
  final ChatStickerPlayback Function(ContentKey emoji) playbackFor;

  /// The document a lone emoji of [emojiOnly] is shown as, or null for the
  /// text layout: the pack's animation for a unicode emoji it has, the custom
  /// emoji's own document, nothing for more than one emoji.
  ContentKey? stickerOf(EmojiOnly emojiOnly) {
    if (emojiOnly.items.length != 1) return null;
    return switch (emojiOnly.items.single.key) {
      final ContentKey$Unicode key => _stickerFor(key),
      final ContentKey$Document key => key,
      _ => null,
    };
  }
}
