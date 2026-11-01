import 'package:catalog_assets/catalog_assets.dart' show InlineEmbedResolver;
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_body_selection_scope.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_code_block_painter.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_inline_embed_adapter.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_markdown_autoscroll.dart';
import 'package:content_model/content_model.dart' show EmojiRuns;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';

/// Controls whether a descendant markdown body may register with the chat
/// selection facade / mount a selection surface.
///
/// Edit-morph keeps an **outgoing** twin painted during the crossfade. That
/// twin shares the same [messageId] as the live body; if it also attaches a
/// surface or [ChatSelectionController.putBody]s, it overwrites the live
/// registry entry and can orphan hit-testing when the twin detaches. Wrap
/// outgoing content with `registers: false`.
class ChatMarkdownBodyRegistration extends InheritedWidget {
  /// Creates a registration scope for descendant [ChatMarkdownBody] mounts.
  const ChatMarkdownBodyRegistration({
    required this.registers,
    required super.child,
    super.key,
  });

  /// When false, descendants must not [ChatSelectionController.putBody] and
  /// must not mount a selection surface for this paint.
  final bool registers;

  /// Whether the nearest scope allows selection registration (default true).
  static bool allows(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<ChatMarkdownBodyRegistration>()
          ?.registers ??
      true;

  @override
  bool updateShouldNotify(covariant ChatMarkdownBodyRegistration oldWidget) =>
      registers != oldWidget.registers;
}

/// Paints a registered markdown body and attaches an engine-owned text selection
/// surface when [ChatSelectionController.exposesSelectionSurface] is true for [messageId].
///
/// Automatically integrates:
/// - [ChatCodeBlockPainter] via [ChatCodeBlockPainter.builder] to separate
///   interactive code header/bottom bars from selectable code body text under
///   the active [controller.selectionPolicy].
/// - [BlockPainter$ScrollableTable] so overflowing markdown tables pan
///   horizontally inside the bubble (catalog painter opt-in, not a theme
///   flag). [BlockPainter$ScrollableTable.enabled] is false while this
///   [messageId] is in **message selection** (nested blocks do not pan).
/// - Dynamic hover cursor resolution via [theme.cursorResolver], reflecting
///   interactive links, inline code spans, click-to-copy headers/bars, and text bodies.
/// - Press-lifecycle tactile feedback via [ChatSpanFeedbackPainter]: begin on
///   pointer down for pressable inline hits, hold while pressed, release fade
///   on up; abort on cancel, past touch-slop travel (list / table pan — scroll
///   rarely delivers [PointerCancel] to a [Listener]), or when the facade
///   signals selection/span yield.
///
/// ### Continuous text gestures (ADR 015)
///
/// The per-body [MarkdownSelectionScope] owns continuous text entry once the
/// viewport yields. Under mobile policy, message-selected bodies keep an armed
/// scope (including siblings while text is live) so long-press can enter or
/// **retarget** with drag-extend. Sibling `putDocument` may briefly re-expand
/// the shared registry; facade adopt / Select All prune to the subject.
/// Consecutive-tap entry stays off. The facade **adopts** the subject from the
/// first non-collapsed markdown range. Desktop keeps mouse recognizers for
/// direct entry when policy allows entry without membership.
///
/// ### Text selection chrome
///
/// Several bodies share one [ChatSelectionController.markdownSelection]
/// controller. [MarkdownSelectionScope.ownsSelectionChrome] is gated to this
/// [messageId] so only the **text selection subject** paints handles /
/// toolbar. Selected siblings may mount surfaces for continuous retarget but
/// do not paint chrome until adopted. Collapsed / disarmed text still clears
/// chrome.
///
/// Toolbar anchors are absolute; they stay live because [ChatScrollView]
/// dispatches [ScrollUpdateNotification] when subject geometry moves
/// (reposition / fan-out / reserved inset), which the scope already consumes
/// via [ScrollNotificationObserver]. Handle followers track via [LeaderLayer]
/// without that rebuild.
///
/// Inline taps (links / code) are arbitrated by the viewport selection pointer,
/// not a competing body [GestureDetector] — a local tap recognizer would win
/// the arena on selected body text and block toggle / text-dismiss.
///
/// ### Inline layer
///
/// - **Embeds.** [embedResolver] turns an image `![alt](scheme:id)` into an
///   embed painted in the text (a custom emoji, a sticker). Keep it stable
///   (one per host, not one per build): a different instance resolves every
///   embed of the body again. Null shows every image as its alt text.
/// - **Spoilers.** `||x||` stays hidden until revealed through
///   [ChatSelectionController.spoilers], keyed by [messageId]; that state is
///   the facade's, so it survives this widget leaving the tree and an
///   edit-morph twin shows the live body's state. A body whose selection
///   surface is not mounted still hides its spoilers (it registers with a
///   private selection controller that nothing reads, which also makes it a
///   repaint boundary, so the live embed and dust frames never repaint the
///   row around it).
/// - **Mentions, hashtags, embeds.** Their taps reach the host as their own
///   [ChatInlineHit] kinds through the facade, never as links.
///
/// ### Edge autoscroll
///
/// Defaults to [ChatMarkdownAutoscroll] (anchor viewport writer, host-union
/// gate off, policy velocity / edge band). Pass [autoscroll] only to disable
/// or override speed / edge depth via [ChatMarkdownAutoscrollOptions] — not
/// the raw markdown autoscroll config.
class ChatMarkdownBody extends StatefulWidget {
  /// Creates a selectable markdown body for [messageId] driven by [controller].
  const ChatMarkdownBody({
    required this.controller,
    required this.messageId,
    this.markdown,
    this.theme,
    this.autoscroll,
    this.embedResolver,
    super.key,
  });

  /// The engine selection controller.
  final ChatSelectionController controller;

  /// Message ID whose registered markdown model to paint.
  final int messageId;

  /// Optional paint model for this mount. When null, uses [controller.bodyOf].
  final Markdown? markdown;

  /// Optional custom markdown theme. When null, resolves from ambient [MarkdownTheme.maybeOf].
  final MarkdownThemeData? theme;

  /// Edge autoscroll knobs while dragging a text selection.
  ///
  /// Null → enabled with policy defaults. Prefer a long-lived instance when
  /// overriding so mid-drag rebuilds keep a stable scope config.
  final ChatMarkdownAutoscrollOptions? autoscroll;

  /// Where the inline embeds of the body come from (the host's resolver over
  /// its asset cache, for instance `ContentEmbedResolver`).
  ///
  /// Keep it stable: a different instance disposes every embed and resolves
  /// them again. Null shows every image as its alt text.
  final InlineEmbedResolver? embedResolver;

  @override
  State<ChatMarkdownBody> createState() => _ChatMarkdownBodyState();
}

class _ChatMarkdownBodyState extends State<ChatMarkdownBody>
    with TickerProviderStateMixin {
  MarkdownThemeData? _cachedAmbient;
  MarkdownThemeData? _cachedUserTheme;
  ChatSelectionPolicy? _cachedPolicy;
  ChatCodeBlockLabels? _cachedCodeBlockLabels;

  /// Cached with theme so [BlockPainter$ScrollableTable.enabled] rebuilds when
  /// membership flips (`enabled` is construct-time, not a live callback).
  bool? _cachedTablePanEnabled;
  MarkdownThemeData? _resolvedTheme;

  AnimationController? _pressController;
  AnimationController? _releaseController;
  final _feedbackNotifier = ValueNotifier<ChatSpanFeedback?>(null);
  ChatInlineEmbedAdapter? _embedAdapter;
  MarkdownThemeData? _fallback;

  /// What a body without a mounted selection surface registers with: the
  /// engine keys spoilers and the repaint boundary on a selection controller
  /// and a document id, and the facade's controller must not see a body it
  /// has not exposed. Lazy: most bodies never need it.
  MarkdownSelectionController? _inertSelection;
  bool _mountsSurface = false;
  bool _armedInlinePress = false;
  int? _inlinePressPointer;
  Offset? _inlinePressDownGlobal;

  /// Cached in [didChangeDependencies] — do not read [context] on move after
  /// unmount (disposed [Listener] can still see moves).
  double _touchSlop = kTouchSlop;
  int _feedbackGen = 0;

  @override
  void initState() {
    super.initState();
    _bindFeedbackListeners(widget.controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _touchSlop =
        MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;
  }

  @override
  void didUpdateWidget(ChatMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _unbindFeedbackListeners(oldWidget.controller);
      _bindFeedbackListeners(widget.controller);
    }
  }

  @override
  void dispose() {
    _unbindFeedbackListeners(widget.controller);
    widget.controller.reportBodyPaintBounds(widget.messageId, null);
    _clearFeedback();
    _feedbackNotifier.dispose();
    _inertSelection?.dispose();
    super.dispose();
  }

  void _reportPaintBounds() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (context.findRenderObject()) {
        case final RenderBox box when box.hasSize:
          widget.controller.reportBodyPaintBounds(widget.messageId, box);
        case _:
          widget.controller.reportBodyPaintBounds(widget.messageId, null);
      }
    });
  }

  void _bindFeedbackListeners(ChatSelectionController controller) {
    controller.addSpanFeedbackTriggerListener(_onSpanFeedbackBegin);
    controller.addSpanFeedbackReleaseListener(_onSpanFeedbackRelease);
    controller.addSpanFeedbackAbortListener(_onSpanFeedbackAbort);
  }

  void _unbindFeedbackListeners(ChatSelectionController controller) {
    controller.removeSpanFeedbackTriggerListener(_onSpanFeedbackBegin);
    controller.removeSpanFeedbackReleaseListener(_onSpanFeedbackRelease);
    controller.removeSpanFeedbackAbortListener(_onSpanFeedbackAbort);
  }

  void _onSpanFeedbackBegin(
    int messageId,
    Path contourPath,
    Offset touchOrigin,
  ) {
    if (messageId != widget.messageId || !mounted) return;
    _clearFeedback();

    final press = AnimationController(
      vsync: this,
      duration: ChatSpanFeedback.pressDuration,
    );
    final release = AnimationController(
      vsync: this,
      duration: ChatSpanFeedback.releaseDuration,
    );
    _pressController = press;
    _releaseController = release;
    final theme = _resolveTheme(context);
    final feedback = ChatSpanFeedback(
      messageId: messageId,
      contourPath: contourPath,
      touchOrigin: touchOrigin,
      pressController: press,
      releaseController: release,
      color: theme.linkColor,
    );
    _feedbackNotifier.value = feedback;
    widget.controller.setSpanFeedback(feedback);
    press.forward();
  }

  void _onSpanFeedbackRelease() {
    final press = _pressController;
    final release = _releaseController;
    if (press == null || release == null || !mounted) return;
    if (release.isAnimating || release.value > 0.0) return;

    final gen = ++_feedbackGen;
    () async {
      if (press.value < 1.0) {
        await press.forward();
      }
      if (!mounted || gen != _feedbackGen || _releaseController != release) {
        return;
      }
      await release.forward();
      if (mounted && gen == _feedbackGen && _releaseController == release) {
        _clearFeedback();
      }
    }();
  }

  void _onSpanFeedbackAbort() {
    _feedbackGen++;
    _disarmInlinePress();
    _clearFeedback();
  }

  void _disarmInlinePress() {
    _armedInlinePress = false;
    _inlinePressPointer = null;
    _inlinePressDownGlobal = null;
  }

  void _clearFeedback() {
    if (_pressController case final press?) {
      _pressController = null;
      press.dispose();
    }
    if (_releaseController case final release?) {
      _releaseController = null;
      release.dispose();
    }
    if (_feedbackNotifier.value != null) {
      _feedbackNotifier.value = null;
      widget.controller.setSpanFeedback(null);
    }
  }

  /// Whether a hit is something a tap does here: every kind, except an embed
  /// the host does not act on (it is part of the text, with no highlight and
  /// no click cursor).
  bool _isActionable(ChatInlineHit? hit) =>
      hit != null &&
      (hit is! ChatInlineHit$Embed || widget.controller.handlesEmbedHits);

  void _tryBeginInlinePress(PointerDownEvent event) {
    if (!widget.controller.allowsInlineTapHighlight) {
      _disarmInlinePress();
      return;
    }
    final hit = widget.controller.resolveInlineHit(
      widget.messageId,
      event.position,
    );
    final contour = _isActionable(hit) ? hit?.contourPath : null;
    if (contour != null && hit!.touchOrigin != null) {
      widget.controller.beginSpanFeedback(
        messageId: widget.messageId,
        contourPath: contour,
        touchOrigin: hit.touchOrigin!,
      );
      _armedInlinePress = true;
      _inlinePressPointer = event.pointer;
      _inlinePressDownGlobal = event.position;
    } else {
      _disarmInlinePress();
    }
  }

  void _onInlinePressMove(PointerMoveEvent event) {
    if (!_armedInlinePress || event.pointer != _inlinePressPointer) return;
    final origin = _inlinePressDownGlobal;
    if (origin == null) return;
    // Scrollables / horizontal table pan rarely deliver [PointerCancel] to a
    // [Listener]; past-slop travel is the reliable cancel (same as
    // [ChatTapHighlight]).
    if ((event.position - origin).distance > _touchSlop) {
      _disarmInlinePress();
      widget.controller.abortSpanFeedback();
    }
  }

  // One adapter per resolver: the engine disposes every embed and resolves
  // them again when it sees another instance.
  MarkdownInlineEmbedResolver? _adaptedEmbedResolver() {
    final resolver = widget.embedResolver;
    if (resolver == null) return _embedAdapter = null;
    if (_embedAdapter case final adapter?
        when identical(adapter.resolver, resolver)) {
      return adapter;
    }
    return _embedAdapter = ChatInlineEmbedAdapter(resolver);
  }

  // The theme of a body with no [MarkdownTheme] above it, kept while its
  // inputs hold: the engine rebuilds its painter (and resolves every embed
  // again) whenever the theme is another instance, and a new one per build
  // would do that on every selection change.
  MarkdownThemeData _fallbackTheme(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    if (_fallback case final cached?
        when cached.textStyle == style &&
            cached.textDirection == direction &&
            cached.textScaler == scaler) {
      return cached;
    }
    return _fallback = MarkdownThemeData(
      textStyle: style,
      textDirection: direction,
      textScaler: scaler,
    );
  }

  /// The emoji of a text the platform draws in colour, for
  /// [MarkdownThemeData.emojiRuns]: they are set at the font's height, as the
  /// reference clients do, instead of at its size. A theme with its own
  /// `emojiRuns` (`(_) => const []` turns it off) is left as it is.
  static Iterable<TextRange> _colourEmojiRuns(String text) => [
    for (final (:start, :end) in EmojiRuns.of(text))
      TextRange(start: start, end: end),
  ];

  MarkdownThemeData _resolveTheme(BuildContext context) {
    final ambient =
        widget.theme ??
        MarkdownTheme.maybeOf(context) ??
        _fallbackTheme(context);

    final policy = widget.controller.selectionPolicy;
    final codeBlockLabels = ChatCodeBlockLabelsScope.of(context);
    // ADR 015 keeps selected bodies hittable — IgnorePointer is not the gate.
    final tablePanEnabled = !widget.controller.isSelected(widget.messageId);
    if (_resolvedTheme case final resolved?
        when identical(ambient, _cachedAmbient) &&
            identical(widget.theme, _cachedUserTheme) &&
            policy == _cachedPolicy &&
            codeBlockLabels == _cachedCodeBlockLabels &&
            tablePanEnabled == _cachedTablePanEnabled) {
      return resolved;
    }

    _cachedAmbient = ambient;
    _cachedUserTheme = widget.theme;
    _cachedPolicy = policy;
    _cachedCodeBlockLabels = codeBlockLabels;
    _cachedTablePanEnabled = tablePanEnabled;

    final userBuilder = ambient.builder;
    final userCursorResolver = ambient.cursorResolver;

    return _resolvedTheme = ambient.copyWith(
      emojiRuns: ambient.emojiRuns ?? _colourEmojiRuns,
      // Every call below makes a new painter, so the body may dispose the ones
      // an update replaces.
      disposeBuiltPainters: true,
      builder: (block, themeData) {
        if (userBuilder case final b?) {
          if (b(block, themeData) case final custom?) return custom;
        }
        // Catalog painters: scrollable tables, then fenced code chrome.
        if (block case MD$Table(
          :final header,
          :final rows,
          :final alignments,
        )) {
          return BlockPainter$ScrollableTable(
            header: header,
            rows: rows,
            alignments: alignments,
            theme: themeData,
            enabled: tablePanEnabled,
          );
        }
        return ChatCodeBlockPainter.builder(
          block,
          themeData,
          policy: policy,
          labels: codeBlockLabels,
        );
      },
      cursorResolver: (localOffset, blockIndex, block) {
        if (userCursorResolver?.call(localOffset, blockIndex, block)
            case final custom?) {
          return custom;
        }
        return _resolveCursor(localOffset, blockIndex, block, policy);
      },
    );
  }

  MouseCursor? _resolveCursor(
    Offset localOffset,
    int? blockIndex,
    MD$Block? block,
    ChatSelectionPolicy policy,
  ) {
    if (block case MD$Code(:final text)) {
      final surface = widget.controller.surfaceFor(widget.messageId);
      if (surface != null && blockIndex != null) {
        final boxes = surface.localBoxesForRange(blockIndex, 0, text.length);
        if (boxes.isNotEmpty) {
          final codeTop = boxes.first.top;
          final codeBottom = boxes.last.bottom;
          if (localOffset.dy < (codeTop - ChatCodeBlockPainter.padding)) {
            return policy.hasInteractiveCodeHeader
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic;
          }
          final hasBottomBar = policy.hasBottomCodeCopyBarForLength(
            text.length,
          );
          if (hasBottomBar &&
              localOffset.dy >= (codeBottom + ChatCodeBlockPainter.padding)) {
            return SystemMouseCursors.click;
          }
          // Code body: defer to glyph-tight library I-beam (not full fence width).
          return null;
        }
      }
      if (policy.hasInteractiveCodeHeader) {
        return SystemMouseCursors.click;
      }
      return SystemMouseCursors.basic;
    }

    // Non-code blocks (paragraphs, headers, quotes, lists, tables):
    // Interactive spans (links / inline code) → click. Otherwise defer so the
    // library's glyph-tight [isSelectableAtLocal] owns the I-beam — empty
    // max-width gutter must not look or act like text.
    final surface = widget.controller.surfaceFor(widget.messageId);
    if (surface case final RenderBox box) {
      final globalPoint = box.localToGlobal(localOffset);
      final inlineHit = widget.controller.resolveInlineHit(
        widget.messageId,
        globalPoint,
      );
      if (_isActionable(inlineHit)) {
        return SystemMouseCursors.click;
      }
    }

    // A body without a mounted surface is not selectable: the engine's text
    // cursor, for a document that has a (private) selection controller, would
    // promise what the facade does not offer.
    return _mountsSurface ? null : MouseCursor.defer;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final model =
          widget.markdown ?? widget.controller.bodyOf(widget.messageId);
      final register = ChatMarkdownBodyRegistration.allows(context);
      final mountSurface =
          register &&
          widget.controller.exposesSelectionSurface(widget.messageId);
      _mountsSurface = mountSurface;
      _reportPaintBounds();
      return switch (model) {
        null => const SizedBox.shrink(),
        final md => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _tryBeginInlinePress,
          onPointerMove: _onInlinePressMove,
          onPointerUp: (event) {
            if (!_armedInlinePress || event.pointer != _inlinePressPointer) {
              return;
            }
            _disarmInlinePress();
            widget.controller.releaseSpanFeedback();
          },
          onPointerCancel: (event) {
            // System / arena cancel must clear ink immediately — not fade
            // through release (and must not leave a held press highlight).
            if (!_armedInlinePress) return;
            if (event.pointer != _inlinePressPointer &&
                _inlinePressPointer != null) {
              return;
            }
            _disarmInlinePress();
            widget.controller.abortSpanFeedback();
          },
          child: ValueListenableBuilder<ChatSpanFeedback?>(
            valueListenable: _feedbackNotifier,
            builder: (context, feedback, child) => CustomPaint(
              foregroundPainter: feedback != null
                  ? ChatSpanFeedbackPainter(
                      feedback: feedback,
                      repaint: feedback.listenable,
                    )
                  : null,
              child: child,
            ),
            child: ChatBodySelectionScope(
              controller: widget.controller,
              messageId: widget.messageId,
              mountSurface: mountSurface,
              autoscroll: widget.autoscroll,
              child: MarkdownWidget(
                markdown: md,
                theme: _resolveTheme(context),
                // The message id keys the spoiler state whether or not the
                // selection surface is mounted (a spoiler must not show its
                // text because another message is selected).
                documentId: widget.messageId,
                controller: mountSurface
                    ? widget.controller.markdownSelection
                    : _inertSelection ??= MarkdownSelectionController(),
                spoilerController: widget.controller.spoilers,
                embedResolver: _adaptedEmbedResolver(),
              ),
            ),
          ),
        ),
      };
    },
  );
}
