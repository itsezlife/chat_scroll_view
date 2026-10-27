import 'package:catalog_assets/catalog_assets.dart'
    show
        AssetPlayback,
        AssetPreset,
        AssetPresets,
        AssetProfile,
        InlineEmbed,
        PlayableEmbed;
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_sticker_tap_policy.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_body_selection_scope.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_geometry.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_policy.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_emoji_text.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_markdown_autoscroll.dart'
    show ChatMarkdownAutoscrollOptions;
import 'package:chat_scroll_view/src/chat_widgets/chat_markdown_body.dart'
    show ChatMarkdownBodyRegistration;
import 'package:chat_scroll_view/src/chat_widgets/chat_sticker_playback.dart';
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

/// A bubble-less message of nothing but emoji, laid out the way the
/// reference client does.
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
///   sticker is a square of [ChatEmojiPolicy.stickerExtentFor] of the screen in
///   the policy's [ChatEmojiPolicy.stickerInset] margin.
/// - **Text**: otherwise. The items are squares of the font step the policy
///   gives the message, in lines that wrap and honour the message's line
///   breaks; the text scale plays no part.
///
/// The numbers are the platform's: [policy] is one of the three
/// [ChatEmojiPolicy] strategies, chosen by the host from the platform it runs
/// as (`ChatEmojiPolicy.forPlatform`).
///
/// A custom emoji is drawn through [embedFactory] and animates and loops. A
/// unicode emoji in the text layout is a glyph at the step's font size (some
/// clients do this; the reference client draws the first frame of the
/// animated sticker).
///
/// ## Sticker playback
///
/// How the sticker plays is the host's policy ([playback]), not the body's:
/// loop, play once and rest on the first or the last frame, or stay still.
/// The reference default plays the single unicode emoji once and loops a
/// custom emoji ([ChatStickerPlayback.defaultFor]). A sticker that plays once
/// does so the first time the open chat shows it, which the host's
/// [playLedger] remembers per message (so a recycled row does not play it
/// again). The body records the play when the animation is playing, not when
/// it ends, as the reference clients do. A replay (a tap, under
/// [tapPolicy]) plays one more pass and never rewinds one that is running.
/// [isActive] is the host's one visibility input: an inactive row costs no
/// animation ticks and shows no sticker to the facade.
///
/// The embed must be a `PlayableEmbed` (`ContentEmbed` is) to replay; any
/// other draws its picture and cannot be replayed.
///
/// ## Selection and taps
///
/// **Text layout.** The body is selectable text, as a markdown body is. It
/// registers its text with the facade (`ChatSelectionController.putBody`, one
/// markdown paragraph made by `ChatEmojiText`) and its render object is the
/// selection surface (`MarkdownSelectionSurface`) of that model, so the
/// facade's range, the per-body scope's mouse and touch gestures, handles,
/// toolbar, select-all and Copy (plain, and structured through
/// `ChatTextCopy.content`) are the markdown body's own, under the same
/// selection policy (ADR 012, ADR 013, ADR 015). An emoji is one atomic item:
/// a press lands on an item edge, a double click or a long press selects the
/// one emoji under it (as a long press on an emoji span does on Android), and
/// the highlight is a box per line under the items
/// ([RenderChatEmojiBody.selectedItemBoxes] are the per-item boxes, for a
/// host that styles them apart). [selectableText] turns it off for a host
/// that keeps the reference clients' rule: only Android selects text here,
/// Desktop and iOS draw the large emoji as media (ADR 036).
///
/// **Sticker layout.** One emoji drawn as a sticker is not text: it registers
/// no text, so nothing starts a range on it, a long press is message
/// selection and Copy is the message's own.
///
/// Both layouts register as a non-text body
/// (`ChatSelectionController.putNonTextBody`) for the activatable parts. The
/// viewport arbitrates taps: a custom emoji of the text layout reports
/// `ChatInlineHit.embed` (when `handlesEmbedHits`), and the sticker reports
/// `ChatInlineHit.sticker`, always, when the tap lands on the drawn sticker
/// (grown by [tapPolicy]'s replay tap slop, none by default): the body then
/// replays the sticker under that policy, and the host gets the tap as
/// `ChatStickerActivated` to build an interaction effect on. The sticker
/// layout also registers as a `ChatStickerBody`, so the host finds the
/// sticker's rectangle and replays it by message id.
///
/// ## Chrome
///
/// The time pill, reactions, reply and forward headers are the host's, and
/// their placement is the platform's ([ChatEmojiPolicy.headerPlacementFor];
/// the pill's metrics are the host's chrome). What the host needs to place them
/// is [geometryFor]: the box (the text layout shrinks to its widest line, the
/// sticker layout is the art plus the policy's inset), the text's rectangle and
/// trailing edge, the last line, and the strip of [bottomReserve] the body
/// keeps free under the items. [hasHeader] tells the text layout to wrap
/// narrower for a header, by the policy's rule.
class ChatEmojiBody extends StatefulWidget {
  /// Creates the body of [messageId] for [emojiOnly].
  const ChatEmojiBody({
    required this.controller,
    required this.messageId,
    required this.emojiOnly,
    required this.embedFactory,
    this.sticker,
    this.playback,
    this.playLedger,
    this.tapPolicy,
    this.isActive = true,
    this.hasHeader = false,
    this.policy = const ChatEmojiPolicy.android(),
    this.parentWidth,
    this.bottomReserve = 0,
    this.semanticsLabel,
    this.selectableText = true,
    this.autoscroll,
    super.key,
  });

  /// Which layout [emojiOnly] gets when the host resolved [sticker].
  static ChatEmojiLayoutKind layoutKindFor(
    EmojiOnly emojiOnly, {
    ContentKey? sticker,
  }) => sticker != null && emojiOnly.items.length == 1
      ? ChatEmojiLayoutKind.sticker
      : ChatEmojiLayoutKind.text;

  /// The geometry of the body [emojiOnly] gets in a row [maxWidth] wide, for a
  /// host that places chrome around it before the body is laid out.
  ///
  /// It is the geometry the widget lays out to (the same code), given the
  /// same inputs: [viewport] is the screen's size (`MediaQuery.sizeOf`),
  /// [direction] the ambient reading direction, [parentWidth] the width a
  /// header's wrap share is of (the viewport's width when null).
  static ChatEmojiGeometry geometryFor({
    required EmojiOnly emojiOnly,
    required ChatEmojiPolicy policy,
    required Size viewport,
    required double maxWidth,
    required TextDirection direction,
    ContentKey? sticker,
    bool hasHeader = false,
    double? parentWidth,
    double bottomReserve = 0,
  }) => ChatEmojiGeometry.of(
    _specFor(
      emojiOnly: emojiOnly,
      policy: policy,
      sticker: sticker,
      viewport: viewport,
      parentWidth: parentWidth,
      direction: direction,
      hasHeader: hasHeader,
      bottomReserve: bottomReserve,
    ),
    maxWidth: maxWidth,
  );

  static ChatEmojiLayoutSpec _specFor({
    required EmojiOnly emojiOnly,
    required ChatEmojiPolicy policy,
    required ContentKey? sticker,
    required Size viewport,
    required double? parentWidth,
    required TextDirection direction,
    required bool hasHeader,
    required double bottomReserve,
  }) {
    final kind = layoutKindFor(emojiOnly, sticker: sticker);
    final isSticker = kind == ChatEmojiLayoutKind.sticker;
    return ChatEmojiLayoutSpec(
      kind: kind,
      lineBreaksBefore: [
        for (final item in emojiOnly.items) item.lineBreaksBefore,
      ],
      box: isSticker
          ? policy.stickerExtentFor(viewport)
          : policy.itemBoxFor(emojiOnly),
      skip: isSticker ? 0 : policy.itemSkipFor(emojiOnly),
      inset: isSticker ? policy.stickerInset : 0,
      wrap: !isSticker && hasHeader
          ? policy.wrapLimitUnderHeader(parentWidth ?? viewport.width)
          : ChatEmojiWrapLimit.none,
      reserve: bottomReserve,
      direction: policy.textDirectionFor(direction),
    );
  }

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

  /// How the sticker plays, or null for the reference default for the emoji
  /// ([ChatStickerPlayback.defaultFor]). Ignored by the text layout.
  final ChatStickerPlayback? playback;

  /// What the open chat already played, to decide whether a sticker that
  /// plays once plays now, and to record it. Null remembers nothing: such a
  /// sticker plays whenever it is mounted.
  final ChatStickerPlayLedger? playLedger;

  /// Where a tap on the sticker counts and which gestures replay it, or null
  /// for the strategy that goes with the controller's selection policy.
  final ChatStickerTapPolicy? tapPolicy;

  /// Whether the row is shown to the user: the host combines row visibility,
  /// app lifecycle, route focus and its power policy. An inactive row's
  /// embeds are hidden (they cost no ticks), it exposes no sticker rectangle
  /// and cannot replay.
  final bool isActive;

  /// Whether a reply or forward header narrows the text layout's wrap, by the
  /// policy's rule ([ChatEmojiPolicy.wrapLimitUnderHeader]). A header the
  /// policy puts beside the body does not.
  final bool hasHeader;

  /// The platform's sizes, inset, wrap and direction rules. Android's by
  /// default.
  final ChatEmojiPolicy policy;

  /// The width the policy's header wrap is a share of: the screen's, or the
  /// chat column's when the chat is not the whole window. The viewport's
  /// width when null.
  final double? parentWidth;

  /// The height of the strip the body keeps free under its items, for the
  /// host's time and ticks. Zero by default.
  final double bottomReserve;

  /// What a screen reader says, the plain text of the message. The default is
  /// made from the unicode emoji and the text of each custom emoji
  /// (`EmojiOnlyItem.alt`, empty when the host did not keep it).
  final String? semanticsLabel;

  /// Whether the text layout is selectable text. On by default; off, the body
  /// registers as a non-text body only, as it did before text selection: a
  /// long press is message selection and Copy is the message's own. The
  /// sticker layout is never text.
  final bool selectableText;

  /// Edge autoscroll knobs while dragging a text selection; null is enabled
  /// with the policy's defaults. See `ChatMarkdownBody.autoscroll`.
  final ChatMarkdownAutoscrollOptions? autoscroll;

  @override
  State<ChatEmojiBody> createState() => _ChatEmojiBodyState();
}

class _ChatEmojiBodyState extends State<ChatEmojiBody>
    implements ChatStickerBody {
  // The render object the leaf widget made. A GlobalKey would find it, but
  // the layout changing between text and sticker moves the leaf in the tree,
  // and a reparented render object reattaches with leaves this state has
  // already given back; made again in place, it takes the new ones.
  RenderChatEmojiBody? _renderBox;

  List<ChatEmojiLeaf> _leaves = const [];
  Object? _plan;

  // Whether the sticker plays now, asked of the ledger once for what this
  // state shows: asking on each build would hold a sticker that is playing,
  // once the first frame recorded it. Null until the first dependencies.
  bool? _autoplay;
  Object? _autoplayFor;
  PlayableEmbed? _watched;

  late double _dpr;
  late Size _viewport;
  late TextStyle _style;

  ChatSelectionController? _registeredWith;
  int? _registeredId;
  Object? _token;
  // The text model the facade holds for this message (the text layout of a
  // selectable body only), and the ownership token it gave back.
  ChatEmojiText? _text;
  EmojiOnly? _textFor;
  Object? _textToken;
  MouseCursor _cursor = MouseCursor.defer;
  bool _mountsSurface = false;

  /// Whether this body is selectable text now: the text layout, with the
  /// host's say-so.
  bool get _isText => widget.selectableText && !_isSticker;

  bool get _isSticker =>
      ChatEmojiBody.layoutKindFor(widget.emojiOnly, sticker: widget.sticker) ==
      ChatEmojiLayoutKind.sticker;

  double get _font => widget.policy.fontSizeFor(widget.emojiOnly);

  double get _extent => widget.policy.stickerExtentFor(_viewport);

  ChatStickerPlayback get _playback =>
      widget.playback ??
      ChatStickerPlayback.defaultFor(widget.emojiOnly.items.first.key);

  ChatStickerTapPolicy get _tapPolicy =>
      widget.tapPolicy ??
      ChatStickerTapPolicy.of(widget.controller.selectionPolicy);

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
    final same =
        wants &&
        _token != null &&
        identical(_registeredWith, widget.controller) &&
        _registeredId == widget.messageId;
    if (!same) {
      _unregister();
      if (!wants) return;
      _registeredWith = widget.controller;
      _registeredId = widget.messageId;
      _token = widget.controller.putNonTextBody(widget.messageId, this);
    }
    _syncText();
  }

  // The text the facade selects from: put while this body is selectable text,
  // updated when the emoji change, removed when it stops being (a sticker, or
  // the host turned it off).
  void _syncText() {
    final controller = _registeredWith;
    final id = _registeredId;
    if (controller == null || id == null || !_isText) {
      _removeText();
      return;
    }
    if (_textToken != null && _textFor == widget.emojiOnly) return;
    final text = _text = ChatEmojiText.of(widget.emojiOnly);
    _textFor = widget.emojiOnly;
    _textToken = controller.putBody(
      id,
      text.markdown,
      order: id,
      token: _textToken,
    );
  }

  void _removeText() {
    if (_textToken case final token?) {
      _registeredWith?.removeBody(_registeredId!, token: token);
    }
    _textToken = null;
    _text = null;
    _textFor = null;
  }

  void _unregister() {
    _removeText();
    if (_token case final token?) {
      _registeredWith?.removeNonTextBody(_registeredId!, token: token);
    }
    if (_registeredId case final id?) {
      _registeredWith?.reportBodyPaintBounds(id, null);
    }
    _token = null;
    _registeredWith = null;
    _registeredId = null;
  }

  // Where the body is, for the facade's gesture routing while its surface is
  // not mounted (the markdown body reports the same).
  void _reportPaintBounds() {
    if (!_isText) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _registeredId == null) return;
      switch (_render) {
        case final RenderBox box:
          _registeredWith?.reportBodyPaintBounds(_registeredId!, box);
        case _:
          _registeredWith?.reportBodyPaintBounds(_registeredId!, null);
      }
    });
  }

  RenderChatEmojiBody? get _render => switch (_renderBox) {
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
  Rect? get stickerGlobalRect {
    final render = _render;
    final rect = _isSticker && widget.isActive ? render?.itemRect(0) : null;
    return rect == null
        ? null
        : render!.localToGlobal(rect.topLeft) & rect.size;
  }

  @override
  bool replay() =>
      _isSticker &&
      widget.isActive &&
      switch (_playable) {
        final embed? => embed.replay(),
        null => false,
      };

  // The sticker's embed when it can play, or null.
  PlayableEmbed? get _playable => switch (_leaves) {
    [ChatEmojiEmbedLeaf(:final PlayableEmbed embed)] when _isSticker => embed,
    _ => null,
  };

  @override
  ChatInlineHit? inlineHitAt(Offset globalOffset) {
    final render = _render;
    if (render == null) return null;
    final local = render.globalToLocal(globalOffset);
    if (_isSticker) {
      // The drawn sticker, not the box around it, grown by the policy's slop.
      final rect = render.itemRect(0);
      if (rect == null || !_tapPolicy.hits(rect, local)) return null;
      return ChatInlineHit.sticker(
        messageId: widget.messageId,
        content: widget.emojiOnly.items.single.key,
        stickerRect: render.localToGlobal(rect.topLeft) & rect.size,
      );
    }
    final index = render.itemAt(local);
    if (index == null) return null;
    final key = widget.emojiOnly.items[index].key;
    // A unicode glyph is text, not an embed: only a custom emoji is a hit.
    return switch (key) {
      ContentKey$Document() => ChatInlineHit.embed(
        messageId: widget.messageId,
        target: key.encoded,
        alt: widget.emojiOnly.items[index].alt,
      ),
      _ => null,
    };
  }

  // --- Leaves ------------------------------------------------------------

  // The leaves depend on these and on nothing else; an equal plan keeps them
  // (and so every embed attached to the cache).
  void _syncLeaves() {
    final sticker = _isSticker;
    _decideAutoplay();
    final plan = (
      widget.emojiOnly,
      widget.sticker,
      widget.embedFactory,
      sticker,
      sticker ? _extent : _font,
      _dpr,
      sticker ? (_playback, _autoplay) : null,
      _style,
    );
    if (plan == _plan) {
      _applyActive();
      return;
    }
    _plan = plan;
    _disposeLeaves();
    _leaves = [
      for (final item in widget.emojiOnly.items) _leafFor(item.key, sticker),
    ];
    _applyActive();
    _watchSticker();
  }

  // Asks the ledger once for what this state shows. A twin that must not
  // register (an edit morph's outgoing copy) shares the message id of the live
  // body and must neither start the play nor use it up.
  void _decideAutoplay() {
    final source = (
      widget.messageId,
      widget.emojiOnly,
      widget.sticker,
      widget.playback,
      widget.playLedger,
    );
    if (_autoplay != null && source == _autoplayFor) return;
    _autoplayFor = source;
    _autoplay =
        _isSticker &&
        switch (_playback) {
          ChatStickerPlayback.loop => true,
          ChatStickerPlayback.still => false,
          ChatStickerPlayback.onceThenFirstFrame ||
          ChatStickerPlayback.onceThenLastFrame =>
            ChatMarkdownBodyRegistration.allows(context) &&
                !(widget.playLedger?.hasPlayed(widget.messageId) ?? false),
        };
  }

  ChatEmojiLeaf _leafFor(ContentKey key, bool sticker) {
    if (sticker) {
      final extent = _extent;
      final playback = _playback;
      final preset = playback.loops
          ? AssetPresets.square(
              extent: extent,
              devicePixelRatio: _dpr,
              profile: const AssetProfile(animate: true),
            )
          : AssetPresets.emojiSticker(
              extent: extent,
              devicePixelRatio: _dpr,
              autoplay: _autoplay!,
              restFrame: playback.restFrame,
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

  // The host's visibility input reaches every embed; a flag is no reason to
  // make them again.
  void _applyActive() {
    for (final leaf in _leaves) {
      if (leaf case ChatEmojiEmbedLeaf(:final embed)) {
        embed.visible = widget.isActive;
      }
    }
  }

  // --- Play once, recorded -------------------------------------------------

  // A sticker that plays once is recorded as played when its animation is
  // playing (the reference marks at the first drawn frame), watched on the
  // embed's own signal until then.
  void _watchSticker() {
    _unwatchSticker();
    if (!_isSticker ||
        _autoplay != true ||
        !_playback.playsOnFirstShow ||
        widget.playLedger == null) {
      return;
    }
    final embed = _playable;
    if (embed == null) return;
    _watched = embed..addListener(_onStickerSignal);
    _onStickerSignal();
  }

  void _unwatchSticker() {
    _watched?.removeListener(_onStickerSignal);
    _watched = null;
  }

  void _onStickerSignal() {
    final embed = _watched;
    if (embed == null || embed.playback != AssetPlayback.playing) return;
    _unwatchSticker();
    widget.playLedger?.markPlayed(widget.messageId);
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
      // The reference sizes ignore the reader's text scale.
      textScaler: TextScaler.noScaling,
    )..layout(),
  );

  void _disposeLeaves() {
    _unwatchSticker();
    for (final leaf in _leaves) {
      leaf.dispose();
    }
    _leaves = const [];
  }

  // --- Taps --------------------------------------------------------------

  void _onInteraction(ChatSelectionInteraction interaction) {
    if (interaction case ChatStickerActivated(
      :final messageId,
      :final gesture,
    ) when messageId == widget.messageId && _isSticker) {
      // A pass that is running is not rewound: the embed refuses, and the
      // tap is still the host's interaction.
      if (_tapPolicy.replaysOn(gesture)) replay();
    }
  }

  bool _actionable(ChatInlineHit? hit) =>
      hit is ChatInlineHit$Sticker ||
      (hit is ChatInlineHit$Embed && widget.controller.handlesEmbedHits);

  void _onHover(PointerHoverEvent event) {
    final MouseCursor next;
    if (_actionable(inlineHitAt(event.position))) {
      next = SystemMouseCursors.click;
    } else if (_mountsSurface &&
        (_render?.hitsSelectableGlyphs(event.position) ?? false)) {
      // The I-beam over an emoji, as over the glyphs of a markdown body.
      next = SystemMouseCursors.text;
    } else {
      next = MouseCursor.defer;
    }
    if (next != _cursor) setState(() => _cursor = next);
  }

  // --- Build -------------------------------------------------------------

  String get _label =>
      widget.semanticsLabel ??
      [
        for (final item in widget.emojiOnly.items)
          '${'\n' * item.lineBreaksBefore}${switch (item.key) {
            ContentKey$Unicode(:final sequence) => sequence,
            _ => item.alt,
          }}',
      ].join();

  Widget _leafBox(ChatEmojiSelectionBinding? selection) => _ChatEmojiLeafWidget(
    onCreated: (box) => _renderBox = box,
    leaves: _leaves,
    spec: ChatEmojiBody._specFor(
      emojiOnly: widget.emojiOnly,
      policy: widget.policy,
      sticker: widget.sticker,
      viewport: _viewport,
      parentWidth: widget.parentWidth,
      direction: Directionality.of(context),
      hasHeader: widget.hasHeader,
      bottomReserve: widget.bottomReserve,
    ),
    tint: _style.color,
    selection: selection,
  );

  // The text layout is under the per-body selection scope and rebuilds with
  // the facade, whose membership and subject the scope's gates read.
  Widget _selectableBox() => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final mounts =
          _text != null &&
          ChatMarkdownBodyRegistration.allows(context) &&
          widget.controller.exposesSelectionSurface(widget.messageId);
      _mountsSurface = mounts;
      _reportPaintBounds();
      return ChatBodySelectionScope(
        controller: widget.controller,
        messageId: widget.messageId,
        mountSurface: mounts,
        autoscroll: widget.autoscroll,
        child: _leafBox(
          mounts
              ? ChatEmojiSelectionBinding(
                  controller: widget.controller.markdownSelection,
                  documentId: widget.messageId,
                  text: _text!,
                )
              : null,
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (!_isText) _mountsSurface = false;
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
          child: _isText ? _selectableBox() : _leafBox(null),
        ),
      ),
    );
  }
}

class _ChatEmojiLeafWidget extends LeafRenderObjectWidget {
  const _ChatEmojiLeafWidget({
    required this.leaves,
    required this.spec,
    required this.tint,
    required this.selection,
    required this.onCreated,
  });

  final ValueChanged<RenderChatEmojiBody> onCreated;

  final List<ChatEmojiLeaf> leaves;
  final ChatEmojiLayoutSpec spec;
  final Color? tint;
  final ChatEmojiSelectionBinding? selection;

  @override
  RenderChatEmojiBody createRenderObject(BuildContext context) {
    final box = RenderChatEmojiBody(
      leaves: leaves,
      spec: spec,
      tint: tint,
      selection: selection,
    );
    onCreated(box);
    return box;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderChatEmojiBody renderObject,
  ) {
    renderObject
      ..leaves = leaves
      ..spec = spec
      ..tint = tint
      ..selection = selection;
  }
}
