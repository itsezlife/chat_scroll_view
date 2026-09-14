import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_code_block_painter.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_secondary_message_tap_scope.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart'
    show
        AdaptiveTextSelectionToolbar,
        ContextMenuButtonItem,
        ContextMenuButtonType;
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
/// - [ChatCodeBlockPainter] via [chatCodeBlockBuilder] to separate interactive
///   code header/bottom bars from selectable code body text under the active
///   [controller.selectionPolicy].
/// - Dynamic hover cursor resolution via [theme.cursorResolver], reflecting
///   interactive links, inline code spans, click-to-copy headers/bars, and text bodies.
/// - Press-lifecycle tactile feedback via [ChatSpanFeedbackPainter]: begin on
///   pointer down for pressable inline hits, hold while pressed, release fade
///   on up; abort when the facade signals selection/span yield.
///
/// ### Continuous text gestures (ADR 015)
///
/// The per-body [MarkdownSelectionScope] owns continuous text entry once the
/// viewport yields. Under mobile policy, while **text selection** is inactive
/// the scope is enabled for message-selected bodies; while text is live only
/// the **text selection subject** mounts a surface (sibling `putDocument`
/// would re-expand the shared registry). Touch long-press is armed on the
/// subject; consecutive-tap entry stays off. The facade **adopts** the subject
/// from the first non-collapsed markdown range. Retarget onto another selected
/// body uses reported body paint bounds and facade
/// [ChatSelectionController.enterTextSelection]. Desktop keeps mouse
/// recognizers for direct entry when policy allows entry without membership.
///
/// ### Text selection chrome
///
/// Several bodies share one [ChatSelectionController.markdownSelection]
/// controller. [MarkdownSelectionScope.ownsSelectionChrome] is gated to this
/// [messageId] so only the **text selection subject** paints handles /
/// toolbar. While text is live, only the subject mounts a selection surface;
/// siblings report paint bounds for retarget / padding arbitration without
/// re-expanding the document registry. Collapsed / disarmed text still clears
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
class ChatMarkdownBody extends StatefulWidget {
  /// Creates a selectable markdown body for [messageId] driven by [controller].
  const ChatMarkdownBody({
    required this.controller,
    required this.messageId,
    this.markdown,
    this.theme,
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

  @override
  State<ChatMarkdownBody> createState() => _ChatMarkdownBodyState();
}

class _ChatMarkdownBodyState extends State<ChatMarkdownBody>
    with TickerProviderStateMixin {
  MarkdownThemeData? _cachedAmbient;
  MarkdownThemeData? _cachedUserTheme;
  ChatSelectionPolicy? _cachedPolicy;
  MarkdownThemeData? _resolvedTheme;

  AnimationController? _pressController;
  AnimationController? _releaseController;
  final _feedbackNotifier = ValueNotifier<ChatSpanFeedback?>(null);
  bool _armedInlinePress = false;
  int _feedbackGen = 0;

  @override
  void initState() {
    super.initState();
    _bindFeedbackListeners(widget.controller);
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
    _armedInlinePress = false;
    _clearFeedback();
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

  void _tryBeginInlinePress(Offset globalPosition) {
    if (!widget.controller.allowsInlineTapHighlight) {
      _armedInlinePress = false;
      return;
    }
    final hit = widget.controller.resolveInlineHit(
      widget.messageId,
      globalPosition,
    );
    if (hit?.contourPath case final contour? when hit!.touchOrigin != null) {
      widget.controller.beginSpanFeedback(
        messageId: widget.messageId,
        contourPath: contour,
        touchOrigin: hit.touchOrigin!,
      );
      _armedInlinePress = true;
    } else {
      _armedInlinePress = false;
    }
  }

  MarkdownThemeData _resolveTheme(BuildContext context) {
    final ambient =
        widget.theme ??
        MarkdownTheme.maybeOf(context) ??
        MarkdownThemeData(
          textStyle: DefaultTextStyle.of(context).style,
          textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
          textScaler:
              MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
        );

    final policy = widget.controller.selectionPolicy;
    if (_resolvedTheme case final resolved?
        when identical(ambient, _cachedAmbient) &&
            identical(widget.theme, _cachedUserTheme) &&
            policy == _cachedPolicy) {
      return resolved;
    }

    _cachedAmbient = ambient;
    _cachedUserTheme = widget.theme;
    _cachedPolicy = policy;

    final userBuilder = ambient.builder;
    final userCursorResolver = ambient.cursorResolver;

    return _resolvedTheme = ambient.copyWith(
      builder: (block, themeData) {
        if (userBuilder case final b?) {
          if (b(block, themeData) case final custom?) return custom;
        }
        return chatCodeBlockBuilder(block, themeData, policy: policy);
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
      if (inlineHit != null) {
        return SystemMouseCursors.click;
      }
    }

    return null;
  }

  bool _isScopeEnabled(bool mountSurface) {
    if (!mountSurface) return false;
    final isSubject =
        widget.controller.textSelectionSubject == widget.messageId;
    if (isSubject) return true;
    final policy = widget.controller.selectionPolicy;
    // Mobile message-then-text: while text is inactive, selected bodies stay
    // armed for continuous text entry (ADR 015). While text is live only the
    // subject mounts — siblings use reported paint bounds for retarget.
    if (policy.nestsTextSubjectInMessageSelection &&
        !widget.controller.isTextSelectionActive &&
        widget.controller.isSelected(widget.messageId)) {
      return true;
    }
    // Desktop/web: direct entry only while message membership is empty —
    // settled message selection and text selection are exclusive (tdesktop).
    // Surfaces may still mount for inline hit-testing; the scope stays off.
    if (policy.allowsTextEntryWithoutMessageSelection) {
      return !widget.controller.isSelectionMode &&
          !widget.controller.hasDragSelection;
    }
    return false;
  }

  /// Whether the scope should arm touch long-press for continuous text entry.
  ///
  /// Mobile: only when this body is message-selected or the text subject.
  /// Desktop: false — mouse recognizers cover direct entry; touch multi-tap
  /// must not steal viewport taps.
  bool _enableTouchGestures(bool scopeEnabled) {
    if (!scopeEnabled) return false;
    final policy = widget.controller.selectionPolicy;
    if (!policy.usesTimerBasedLongPress) return false;
    return widget.controller.isSelected(widget.messageId) ||
        widget.controller.textSelectionSubject == widget.messageId;
  }

  /// Whether the per-body scope may begin a character-range at [global].
  ///
  /// Plain body text always may. Fenced copy chrome never may (not text).
  /// Under mobile message-then-text (selected body / active subject), link and
  /// inline-code spans may — long-press enters text selection there. Idle and
  /// desktop keep the scope off those hits so tap activation / copy win.
  bool _canStartTextSelectionAt(Offset global) {
    final hit = widget.controller.resolveInlineHit(widget.messageId, global);
    if (hit == null) {
      // Painter reports fenced copy chrome even when resolveInlineHit missed
      // (e.g. position clamp edge). Never arm text over COPY CODE / header.
      final surface = widget.controller.surfaceFor(widget.messageId);
      if (surface != null && surface.isLinkAtGlobal(global)) return false;
      return true;
    }
    // Fenced copy chrome: no text-contour geometry — not a selection start.
    if (hit case ChatInlineHit$Code(
      :final contourPath,
      :final touchOrigin,
    ) when contourPath == null && touchOrigin == null) {
      return false;
    }
    final policy = widget.controller.selectionPolicy;
    if (policy.usesTimerBasedLongPress &&
        (widget.controller.isSelected(widget.messageId) ||
            widget.controller.textSelectionSubject == widget.messageId)) {
      return true;
    }
    return false;
  }

  Widget _buildContextMenu(
    BuildContext context,
    MarkdownSelectionScopeState state,
  ) {
    final items = <ContextMenuButtonItem>[];
    if (widget.controller.textSelection case final sel? when !sel.isCollapsed) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () async {
            await widget.controller.copyTextSelection();
            state.hideToolbar();
          },
        ),
      );
    }
    if (widget.controller.hasBody(widget.messageId)) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          onPressed: () {
            widget.controller.selectAllText();
            state.showToolbar();
          },
        ),
      );
    }
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      buttonItems: items,
      anchors: state.contextMenuAnchors,
    );
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
      final scopeEnabled = _isScopeEnabled(mountSurface);
      _reportPaintBounds();
      return switch (model) {
        null => const SizedBox.shrink(),
        final md => Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _tryBeginInlinePress(event.position);
            if (event.kind == PointerDeviceKind.mouse) {
              final policy = widget.controller.selectionPolicy;
              if (policy.allowsTextEntryWithoutMessageSelection &&
                  !widget.controller.isSelectionMode) {
                if (widget.controller.resolveInlineHit(
                      widget.messageId,
                      event.position,
                    ) !=
                    null) {
                  return;
                }
                widget.controller.armTextSelection(widget.messageId);
              }
            }
          },
          onPointerUp: (_) {
            if (_armedInlinePress) {
              _armedInlinePress = false;
              widget.controller.releaseSpanFeedback();
            }
          },
          onPointerCancel: (_) {
            // System / arena cancel must clear ink immediately — not fade
            // through release (and must not leave a held press highlight).
            if (_armedInlinePress) {
              _armedInlinePress = false;
              widget.controller.abortSpanFeedback();
            }
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
            child: Actions(
              actions: <Type, Action<Intent>>{
                CopySelectionTextIntent:
                    CallbackAction<CopySelectionTextIntent>(
                      onInvoke: (_) {
                        widget.controller.copyTextSelection();
                        return null;
                      },
                    ),
                SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
                  onInvoke: (_) {
                    widget.controller.selectAllText();
                    return null;
                  },
                ),
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    widget.controller.clearTextSelection();
                    return null;
                  },
                ),
              },
              child: MarkdownSelectionScope(
                controller: widget.controller.markdownSelection,
                enabled: scopeEnabled,
                // Continuous text: touch long-press → word → drag-extend
                // (ADR 015). Consecutive taps stay off so the viewport owns
                // toggle / dismiss taps; mouse multi-click remains desktop.
                enableTouchGestures: _enableTouchGestures(scopeEnabled),
                enableTouchConsecutiveTaps: false,
                canStartSelectionAt: _canStartTextSelectionAt,
                // Subject-only chrome: siblings share the controller under
                // mobile multi-select but must not paint this body's handles.
                ownsSelectionChrome: (documentId) =>
                    documentId == widget.messageId,
                // Host opted into secondary → yield right-click to the
                // viewport (full-slot message menu). Null builder also
                // omits the markdown secondary recognizer (flutter_md).
                contextMenuBuilder:
                    ChatSecondaryMessageTapScope.hostOwnsSecondaryOf(context)
                    ? null
                    : _buildContextMenu,
                child: MarkdownWidget(
                  markdown: md,
                  theme: _resolveTheme(context),
                  documentId: mountSurface ? widget.messageId : null,
                  controller: mountSurface
                      ? widget.controller.markdownSelection
                      : null,
                ),
              ),
            ),
          ),
        ),
      };
    },
  );
}
