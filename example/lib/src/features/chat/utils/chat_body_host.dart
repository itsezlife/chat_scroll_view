import 'package:chat_scroll_view/chat_scroll_view.dart'
    show
        ChatEmojiEmbedFactory,
        ChatMediaItem,
        ChatMediaKind,
        ChatMediaOverlayBuilder,
        ChatMediaSizePolicy,
        ChatStickerPlayback;
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/common/lab_media_trace.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart'
    show DescribeContent;
import 'package:chat_scroll_view_example/src/features/chat/data/demo_documents.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/document_embed.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/reference_media_sizes.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/sticker_play_memory.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart'
    show BuildContext, LayoutBuilder, SizedBox, Widget;
import 'package:listen/listen.dart' as listen;
import 'package:mpx_core/mpx_core.dart';

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
  /// animation settings; by default a unicode emoji plays once and rests on
  /// the first frame, and a custom emoji loops.
  ///
  /// [describe] says what the host knows of a document: a GIF is clear
  /// until its preview or thumbnail, as in the panel's grid, a sticker or
  /// custom emoji waits behind a quiet rounded square. Without it every
  /// document is the latter.
  ///
  /// [downloadContext] is the class of the chat (`ChatKind.downloadContext`):
  /// every embed attaches with it, so the auto-download policy weighs the
  /// chat's media by the conversation it is in. [stages] is how every embed
  /// draws an outline preview (`ContentEmbed.stages`): the screen's loading
  /// style, which the screen feeds again when it changes.
  ///
  /// [held] is the hold on the chat's playback (a popup panel over it): every
  /// embed the bodies make, inline or emoji-only, follows it
  /// (`ContentEmbed.held`), so the chat shows its frames and keeps them.
  ///
  /// It also says which lone document is a sticker or a GIF of its own
  /// ([mediaOf]), drawn at the size [mediaSizes] gives it: the running
  /// platform's sizes by default.
  ChatBodyHost({
    required ContentAssetScope assets,
    required this.policy,
    ContentKey? Function(ContentKey key) stickerFor =
        AnimatedEmojiPack.stickerFor,
    StickerPlayMemory? plays,
    this.playbackFor = ChatStickerPlayback.defaultFor,
    DescribeContent? describe,
    listen.ValueListenable<bool>? held,
    ChatMediaSizePolicy? mediaSizes,
    AutoDownloadContext? downloadContext,
    listen.ValueListenable<MediaStageStyle>? stages,
    ChatDocument? Function(String id) documents = DemoDocuments.document,
    SvgDocumentPreview? documentPreviews = DemoDocuments.previews,
    listen.ValueListenable<DocumentRowStyle>? documentStyle,
  }) : embedResolver = _resolverFor(
         DocumentEmbedResolver(
           scope: assets,
           documents: documents,
           previews: documentPreviews,
           style: documentStyle,
           stages: stages,
           otherwise: ContentEmbedResolver(
             scope: assets,
             held: held,
             downloadContext: downloadContext,
             stages: stages,
           ),
         ),
       ),
       embedFactory = ((content, preset) {
         // The lab tells the chat's uploads and decodes from the panel's.
         if (DemoConfig.scrollLab) LabMediaTrace.noteChat(content);
         return ContentEmbed(
           scope: assets,
           content: content,
           preset: preset,
           held: held,
           downloadContext: downloadContext,
           stages: stages,
           // A document here is a sticker, a custom emoji drawn large or a GIF.
           // A GIF takes the scope's clear default, then its preview and
           // thumbnail; the scope's circle is the stand-in of a glyph.
           placeholder: switch (content) {
             ContentKey$Document()
                 when describe?.call(content)?.semanticKind ==
                     SemanticKind.gif =>
               null,
             ContentKey$Document() => const SoftPlaceholder(),
             _ => null,
           },
         );
       }),
       plays = plays ?? StickerPlayMemory(),
       mediaSizes = mediaSizes ?? ReferenceMediaSizes.forPlatform(),
       _stickerFor = stickerFor,
       _describe = describe;

  // The chat's resolver, noting what it embeds in a scroll lab build.
  static InlineEmbedResolver _resolverFor(InlineEmbedResolver resolver) =>
      DemoConfig.scrollLab ? _LabChatResolver(resolver) : resolver;

  /// What lies over the art of a lone GIF: the status control (cancel and an
  /// arc while it downloads, download while it waits for a tap or failed,
  /// gone once it shows) and the "GIF" badge, read from its embed. A sticker
  /// has none: it always downloads and needs no label.
  final ChatMediaOverlayBuilder mediaOverlay = _mediaOverlay;

  static Widget? _mediaOverlay(
    BuildContext context,
    ChatMediaItem media,
    InlineEmbed embed,
  ) => switch ((media.kind, embed)) {
    // The badge takes its narrow forms by the width of the art.
    (ChatMediaKind.gif, final ContentEmbed embed) => LayoutBuilder(
      builder: (context, constraints) => ContentStatusOverlay(
        binding: embed.binding,
        badge: true,
        width: constraints.maxWidth,
        child: const SizedBox.expand(),
      ),
    ),
    _ => null,
  };

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

  /// How large a lone sticker or GIF is drawn.
  final ChatMediaSizePolicy mediaSizes;

  final ContentKey? Function(ContentKey key) _stickerFor;

  final DescribeContent? _describe;

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

  /// The sticker or GIF [emojiOnly] is, when it is one document the host
  /// describes as either; null for an emoji (unicode or custom), more than
  /// one item, or a document the host does not know, which the emoji-only
  /// policy sizes.
  ChatMediaItem? mediaOf(EmojiOnly emojiOnly) => switch (emojiOnly.items) {
    [EmojiOnlyItem(key: final ContentKey$Document key)] => switch (_describe
        ?.call(key)) {
      ContentDescriptor(semanticKind: SemanticKind.sticker, :final size) =>
        ChatMediaItem(kind: ChatMediaKind.sticker, source: size),
      ContentDescriptor(semanticKind: SemanticKind.gif, :final size) =>
        ChatMediaItem(kind: ChatMediaKind.gif, source: size),
      _ => null,
    },
    _ => null,
  };
}

/// The chat's resolver in a scroll lab build: notes each content key the
/// markdown bodies embed, so the lab tells the chat's uploads and decodes
/// from the panel's.
final class _LabChatResolver implements InlineEmbedResolver {
  _LabChatResolver(this._resolver);

  final InlineEmbedResolver _resolver;

  @override
  InlineEmbed? resolve(InlineEmbedTarget target, InlineEmbedMetrics metrics) {
    if (ContentKey.tryParse('${target.scheme}:${target.id}') case final key?) {
      LabMediaTrace.noteChat(key);
    }
    return _resolver.resolve(target, metrics);
  }
}
