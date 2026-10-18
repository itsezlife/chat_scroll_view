import 'package:catalog_assets/catalog_assets.dart'
    show AssetPreset, AssetPresets, AssetProfile, InlineEmbed;
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_sizes.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_markdown_body.dart'
    show ChatMarkdownBodyRegistration;
import 'package:chat_scroll_view/src/chat_widgets/render_chat_emoji_body.dart';
import 'package:content_model/content_model.dart'
    show ContentKey, ContentKey$Document, ContentKey$Unicode, EmojiOnly;
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/widgets.dart';

/// Makes the embed that draws [content] the way [preset] says: the host's
/// link between an emoji-only body and its asset cache.
///
/// With `catalog_assets` it is one line over the host's scope:
/// `(content, preset) => ContentEmbed(scope: scope, content: content,
/// preset: preset)`. Null shows nothing in the item's square (the host's cache
/// does not know the content). The body owns the embed it gets and disposes
/// it. `InlineEmbedResolver` does not fit here: it sizes an embed from text
/// metrics, and an emoji-only body sizes by count with presets of its own.
typedef ChatEmojiEmbedFactory =
    InlineEmbed? Function(ContentKey content, AssetPreset preset);

/// Which of the two layouts of [ChatEmojiBody] a message gets.
enum ChatEmojiLayoutKind {
  /// One emoji shown as a sticker, in a margin, with the reply header beside
  /// it.
  sticker,

  /// Emoji set as enlarged text, with the reply header above it.
  text,
}

/// A bubble-less message of nothing but emoji, laid out the way Telegram
/// Android does.
///
/// The host classifies the text (`EmojiOnlyText.of`, once, when it
/// materialises the message) and adds the facts only it has: that the message
/// has no media, the large-emoji setting and the chat's permission. It then
/// shows this body instead of [ChatMarkdownBody]; the viewport never
/// re-detects.
///
/// ## Layouts
///
/// - **Sticker**: [sticker] is given and there is exactly one item. The
///   sticker is a square of [ChatEmojiSizes.stickerExtentFor] of the screen in
///   a [ChatEmojiSizes.stickerInset] margin.
/// - **Text**: otherwise. The items are squares of the font step their count
///   gives, in lines that wrap and honour the message's line breaks; the text
///   scale plays no part.
///
/// A custom emoji is drawn through [embedFactory] and animates and loops. A
/// unicode emoji in the text layout is a glyph at the step's font size (iOS
/// and Desktop do this; Android draws the first frame of the animated
/// sticker). The sticker of a unicode emoji plays when [autoplay] says so; a
/// custom emoji's sticker always plays.
///
/// ## Selection and taps
///
/// The body registers with the facade as a non-text body
/// (`ChatSelectionController.putNonTextBody`): there is no text to select, a
/// long press is message selection, and Copy is the message's own. The
/// viewport arbitrates taps: a custom emoji of the text layout reports
/// `ChatInlineHit.embed` (when `handlesEmbedHits`), and the sticker reports
/// `ChatInlineHit.sticker`, always; on that tap the body plays the sticker
/// again.
///
/// ## Chrome
///
/// The time pill, reactions, reply and forward headers are the host's. The
/// body's box is its geometry: the text layout shrinks to its widest line and
/// the sticker layout is the sticker plus its inset. Over the box's bottom
/// trailing corner goes the pill; the reply goes beside a [sticker] layout
/// and above a text layout ([layoutKindFor] says which), and [hasHeader]
/// tells the text layout to wrap narrower for it.
class ChatEmojiBody extends StatefulWidget {
  /// Creates the body of [messageId] for [emojiOnly].
  const ChatEmojiBody({
    required this.controller,
    required this.messageId,
    required this.emojiOnly,
    required this.embedFactory,
    this.sticker,
    this.autoplay = true,
    this.hasHeader = false,
    this.sizes = const ChatEmojiSizes(),
    this.semanticsLabel,
    super.key,
  });

  /// Which layout [emojiOnly] gets when the host resolved [sticker].
  static ChatEmojiLayoutKind layoutKindFor(
    EmojiOnly emojiOnly, {
    ContentKey? sticker,
  }) => sticker != null && emojiOnly.items.length == 1
      ? ChatEmojiLayoutKind.sticker
      : ChatEmojiLayoutKind.text;

  /// The facade the body registers with.
  final ChatSelectionController controller;

  /// The message this is the body of.
  final int messageId;

  /// The emoji of the message, from `EmojiOnlyText.of`.
  final EmojiOnly emojiOnly;

  /// Where the body gets the embeds of custom emoji and of the sticker. Keep
  /// it stable: another function disposes every embed and makes them again.
  final ChatEmojiEmbedFactory embedFactory;

  /// The document a lone emoji is shown as: the animated-emoji pack's
  /// document for a unicode emoji (the host's map), the custom emoji's own
  /// document for a custom one. Null, or more than one item, gives the text
  /// layout.
  final ContentKey? sticker;

  /// Whether the sticker of a unicode emoji starts playing when it appears.
  /// The host remembers what already played on this screen (Android plays it
  /// the first time a chat shows it); a sticker held at its first frame
  /// plays on a tap.
  final bool autoplay;

  /// Whether a reply or forward header sits above the text layout, which then
  /// wraps at [ChatEmojiSizes.headerWrapFraction] of the row's width.
  final bool hasHeader;

  /// The sizes; Android's by default.
  final ChatEmojiSizes sizes;

  /// What a screen reader says, the plain text of the message. The default is
  /// made from the unicode emoji alone: a custom emoji has no text in
  /// [emojiOnly].
  final String? semanticsLabel;

  @override
  State<ChatEmojiBody> createState() => _ChatEmojiBodyState();
}

class _ChatEmojiBodyState extends State<ChatEmojiBody>
    implements ChatNonTextBody {
  final _leafKey = GlobalKey();

  List<ChatEmojiLeaf> _leaves = const [];
  Object? _plan;
  int _replays = 0;
  bool _replayed = false;

  late double _dpr;
  late Size _viewport;
  late TextStyle _style;

  ChatSelectionController? _registeredWith;
  int? _registeredId;
  Object? _token;
  MouseCursor _cursor = MouseCursor.defer;

  bool get _isSticker =>
      ChatEmojiBody.layoutKindFor(widget.emojiOnly, sticker: widget.sticker) ==
      ChatEmojiLayoutKind.sticker;

  bool get _allCustom =>
      widget.emojiOnly.items.every((item) => item.key is ContentKey$Document);

  double get _font => widget.sizes.fontSizeFor(
    widget.emojiOnly.items.length,
    allCustom: _allCustom,
  );

  double get _extent => widget.sizes.stickerExtentFor(_viewport);

  @override
  void initState() {
    super.initState();
    widget.controller.addInteractionListener(_onInteraction);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dpr = MediaQuery.devicePixelRatioOf(context);
    _viewport = MediaQuery.sizeOf(context);
    _style = DefaultTextStyle.of(context).style;
    _syncRegistration();
    _syncLeaves();
  }

  @override
  void didUpdateWidget(ChatEmojiBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeInteractionListener(_onInteraction);
      widget.controller.addInteractionListener(_onInteraction);
    }
    if (oldWidget.emojiOnly != widget.emojiOnly ||
        oldWidget.sticker != widget.sticker) {
      _replayed = false;
    }
    _syncRegistration();
    _syncLeaves();
  }

  @override
  void dispose() {
    widget.controller.removeInteractionListener(_onInteraction);
    _unregister();
    _disposeLeaves();
    super.dispose();
  }

  // --- Registration ------------------------------------------------------

  // An edit-morph twin shares the live body's message id and must not
  // replace its entry (see [ChatMarkdownBodyRegistration]).
  void _syncRegistration() {
    final wants = ChatMarkdownBodyRegistration.allows(context);
    if (wants &&
        _token != null &&
        identical(_registeredWith, widget.controller) &&
        _registeredId == widget.messageId) {
      return;
    }
    _unregister();
    if (!wants) return;
    _registeredWith = widget.controller;
    _registeredId = widget.messageId;
    _token = widget.controller.putNonTextBody(widget.messageId, this);
  }

  void _unregister() {
    if (_token case final token?) {
      _registeredWith?.removeNonTextBody(_registeredId!, token: token);
    }
    _token = null;
    _registeredWith = null;
    _registeredId = null;
  }

  RenderChatEmojiBody? get _render =>
      switch (_leafKey.currentContext?.findRenderObject()) {
        final RenderChatEmojiBody box when box.attached && box.hasSize => box,
        _ => null,
      };

  @override
  Rect? get globalBounds {
    final render = _render;
    return render == null
        ? null
        : render.localToGlobal(Offset.zero) & render.size;
  }

  @override
  ChatInlineHit? inlineHitAt(Offset globalOffset) {
    final render = _render;
    if (render == null) return null;
    final index = render.itemAt(render.globalToLocal(globalOffset));
    if (index == null) return null;
    final key = widget.emojiOnly.items[index].key;
    if (_isSticker) {
      return ChatInlineHit.sticker(messageId: widget.messageId, content: key);
    }
    // A unicode glyph is text, not an embed: only a custom emoji is a hit.
    return switch (key) {
      ContentKey$Document() => ChatInlineHit.embed(
        messageId: widget.messageId,
        target: key.encoded,
        // `EmojiOnly` keeps no alternative text for a custom emoji.
        alt: '',
      ),
      _ => null,
    };
  }

  // --- Leaves ------------------------------------------------------------

  // The leaves depend on these and on nothing else; an equal plan keeps them
  // (and so every embed attached to the cache).
  void _syncLeaves() {
    final sticker = _isSticker;
    final plan = (
      widget.emojiOnly,
      widget.sticker,
      widget.embedFactory,
      sticker,
      sticker ? _extent : _font,
      _dpr,
      widget.autoplay || _replayed,
      _style,
      _replays,
    );
    if (plan == _plan) return;
    _plan = plan;
    _disposeLeaves();
    _leaves = [
      for (final item in widget.emojiOnly.items) _leafFor(item.key, sticker),
    ];
  }

  ChatEmojiLeaf _leafFor(ContentKey key, bool sticker) {
    if (sticker) {
      final extent = _extent;
      final preset = key is ContentKey$Unicode
          ? AssetPresets.emojiSticker(
              extent: extent,
              devicePixelRatio: _dpr,
              autoplay: widget.autoplay || _replayed,
            )
          : AssetPresets.square(
              extent: extent,
              devicePixelRatio: _dpr,
              profile: const AssetProfile(animate: true),
            );
      return _embedLeaf(widget.sticker!, preset);
    }
    return switch (key) {
      ContentKey$Unicode(:final sequence) => _glyphLeaf(sequence),
      ContentKey$Document() => _embedLeaf(
        key,
        AssetPresets.emojiOnly(step: _font, devicePixelRatio: _dpr),
      ),
      _ => const ChatEmojiEmptyLeaf(),
    };
  }

  ChatEmojiLeaf _embedLeaf(ContentKey key, AssetPreset preset) =>
      switch (widget.embedFactory(key, preset)) {
        final embed? => ChatEmojiEmbedLeaf(embed),
        null => const ChatEmojiEmptyLeaf(),
      };

  ChatEmojiLeaf _glyphLeaf(String sequence) => ChatEmojiGlyphLeaf(
    TextPainter(
      text: TextSpan(
        text: sequence,
        style: _style.copyWith(fontSize: _font, height: 1),
      ),
      textDirection: TextDirection.ltr,
      // Android's sizes ignore the reader's text scale.
      textScaler: TextScaler.noScaling,
    )..layout(),
  );

  void _disposeLeaves() {
    for (final leaf in _leaves) {
      leaf.dispose();
    }
    _leaves = const [];
  }

  // --- Taps --------------------------------------------------------------

  void _onInteraction(ChatSelectionInteraction interaction) {
    if (interaction case ChatStickerActivated(
      :final messageId,
      gesture: ChatInlineGesture.tap,
    ) when messageId == widget.messageId && _isSticker) {
      // A held sticker plays, and a playing one is attached again. The cache
      // keeps one playback per entry and loops it, so this cannot rewind a
      // sticker that is mid-way (see the report of ticket 14).
      setState(() {
        _replayed = true;
        _replays++;
        _syncLeaves();
      });
    }
  }

  bool _actionable(ChatInlineHit? hit) =>
      hit is ChatInlineHit$Sticker ||
      (hit is ChatInlineHit$Embed && widget.controller.handlesEmbedHits);

  void _onHover(PointerHoverEvent event) {
    final next = _actionable(inlineHitAt(event.position))
        ? SystemMouseCursors.click
        : MouseCursor.defer;
    if (next != _cursor) setState(() => _cursor = next);
  }

  // --- Build -------------------------------------------------------------

  String get _label =>
      widget.semanticsLabel ??
      [
        for (final item in widget.emojiOnly.items)
          if (item.key case ContentKey$Unicode(:final sequence))
            '${'\n' * item.lineBreaksBefore}$sequence',
      ].join();

  @override
  Widget build(BuildContext context) {
    final sticker = _isSticker;
    final sizes = widget.sizes;
    final items = widget.emojiOnly.items;
    return Semantics(
      label: _label,
      textDirection: Directionality.of(context),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: _cursor,
        onHover: _onHover,
        onExit: (_) {
          if (_cursor != MouseCursor.defer) {
            setState(() => _cursor = MouseCursor.defer);
          }
        },
        // Animated frames repaint this box, not the row around it.
        child: RepaintBoundary(
          child: _ChatEmojiLeafWidget(
            key: _leafKey,
            leaves: _leaves,
            lineBreaksBefore: [for (final item in items) item.lineBreaksBefore],
            box: sticker ? _extent : _font + sizes.boxPadding,
            inset: sticker ? sizes.stickerInset : 0,
            wrapFraction: !sticker && widget.hasHeader
                ? sizes.headerWrapFraction
                : 1,
            textDirection: Directionality.of(context),
            tint: _style.color,
          ),
        ),
      ),
    );
  }
}

class _ChatEmojiLeafWidget extends LeafRenderObjectWidget {
  const _ChatEmojiLeafWidget({
    required this.leaves,
    required this.lineBreaksBefore,
    required this.box,
    required this.inset,
    required this.wrapFraction,
    required this.textDirection,
    required this.tint,
    super.key,
  });

  final List<ChatEmojiLeaf> leaves;
  final List<int> lineBreaksBefore;
  final double box;
  final double inset;
  final double wrapFraction;
  final TextDirection textDirection;
  final Color? tint;

  @override
  RenderChatEmojiBody createRenderObject(BuildContext context) =>
      RenderChatEmojiBody(
        leaves: leaves,
        lineBreaksBefore: lineBreaksBefore,
        box: box,
        inset: inset,
        wrapFraction: wrapFraction,
        textDirection: textDirection,
        tint: tint,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatEmojiBody renderObject,
  ) {
    renderObject
      ..leaves = leaves
      ..lineBreaksBefore = lineBreaksBefore
      ..box = box
      ..inset = inset
      ..wrapFraction = wrapFraction
      ..textDirection = textDirection
      ..tint = tint;
  }
}
