import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chat_chrome/src/composer/chat_composer_controller.dart';
import 'package:chat_chrome/src/composer/chat_enter_icons.dart';
import 'package:chat_chrome/src/composer/chat_enter_top_view.dart';
import 'package:chat_chrome/src/composer/chat_input_metrics.dart';
import 'package:chat_chrome/src/glass/telegram_glass.dart';
import 'package:chat_chrome/src/glass/telegram_glass_style.dart';
import 'package:chat_chrome/src/motion/keyboard_panel_motion.dart';
import 'package:chat_chrome/src/theme/chat_chrome_colors.dart';
import 'package:chat_chrome/src/util/value_listenable_select.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Optional reply / edit banner model for [ChatEnterView].
@immutable
class ChatEnterTopBanner {
  /// Creates a reply or edit banner.
  const ChatEnterTopBanner({
    required this.title,
    required this.subtitle,
    this.isEdit = false,
  });

  /// Author name or "Edit message".
  final String title;

  /// Preview text.
  final String subtitle;

  /// Edit vs reply chrome.
  final bool isEdit;
}

/// Shell-owned field + IME handoff for a custom [ChatEnterView] input row.
///
/// [ChatEnterView] owns focus / soft-IME policy. A custom row must attach its
/// [TextField] (or equivalent) to [focusNode] / [controller] and call
/// [prepareKeyboardHandoff] on pointer-down before a panel→IME tap steals
/// focus.
@immutable
class ChatEnterFieldHandle {
  /// Creates a field handle.
  const ChatEnterFieldHandle({
    required this.controller,
    required this.focusNode,
    required this.prepareKeyboardHandoff,
  });

  /// Same controller owned by [ChatEnterView.composer].
  final TextEditingController controller;

  /// Same focus node the shell listens to for IME suppress / show.
  final FocusNode focusNode;

  /// Arms one focus gain so IME-suppress does not hide the soft keyboard.
  final VoidCallback prepareKeyboardHandoff;
}

/// Builds a custom input row under the glass island.
///
/// Receives the shell-owned [ChatEnterFieldHandle] so the row stays on the
/// same focus / IME policy as [ChatEnterViewState].
typedef ChatEnterInputBuilder =
    Widget Function(BuildContext context, ChatEnterFieldHandle field);

/// Builds a custom reply / edit strip above the composer row.
///
/// When set on [ChatEnterView], takes priority over [ChatEnterView.topBanner].
typedef ChatEnterTopBannerBuilder = Widget Function(BuildContext context);

/// Floating input island (glass bubble).
///
/// Transparent outer host — the painted shape is the 22dp-radius island with
/// 7dp horizontal margins (see [ChatInputMetrics]). Selection actions do not
/// live here; those live on the action / selection chrome.
///
/// **Motion:**
/// - Top banner: visibility factor `t∈[0,1]` — layout height `48 * t`, child
///   clip-revealed top-first (250ms list cubic).
/// - Field height: animate-to measured row height with bottom gravity so the
///   island grows upward from a fixed baseline.
/// - Input row is built outside the animation builder so ticks do not remount
///   the field (focus / IME stay put).
class ChatEnterView extends StatefulWidget {
  /// Creates the enter view.
  const ChatEnterView({
    required this.composer,
    required this.onSend,
    required this.onEmojiPressed,
    this.onAttachPressed,
    this.onMicPressed,
    this.hintText = 'Message',
    this.topBanner,
    this.topBannerBuilder,
    this.onTopBannerClose,
    this.maxWidth = 620,
    this.onFieldTapWhilePanelOpen,
    this.inputBuilder,
    this.glassKey,
    super.key,
  });

  /// Composer state of truth (text, focus, mode, emoji, busy, enabled).
  final ChatComposerController composer;

  /// Send / confirm.
  final VoidCallback? onSend;

  /// Emoji / keyboard toggle.
  final VoidCallback onEmojiPressed;

  /// Attach button (optional).
  final VoidCallback? onAttachPressed;

  /// Mic when field empty (optional).
  final VoidCallback? onMicPressed;

  /// Field hint.
  final String hintText;

  /// Reply / edit strip model for the stock [ChatEnterTopView].
  ///
  /// Ignored when [topBannerBuilder] is set. Typically derived from
  /// [ChatComposerController.mode] by the host (l10n / titles).
  final ChatEnterTopBanner? topBanner;

  /// Optional custom reply / edit strip above the input row.
  ///
  /// When set, replaces [topBanner] / [ChatEnterTopView]. Host owns close /
  /// cancel chrome inside the built widget.
  final ChatEnterTopBannerBuilder? topBannerBuilder;

  /// Clears stock [topBanner] (unused when [topBannerBuilder] is set).
  final VoidCallback? onTopBannerClose;

  /// Max content width.
  final double maxWidth;

  /// Key on the liquid-glass island (for fade cutout tracking).
  final GlobalKey? glassKey;

  /// Fired when the user taps the field while the keyboard panel is open
  /// (tap input → close panel, show IME).
  final VoidCallback? onFieldTapWhilePanelOpen;

  /// Optional custom input row under the glass island.
  ///
  /// When null, builds the stock emoji / field / attach / send row.
  /// When set, receives a [ChatEnterFieldHandle] bound to this view's
  /// composer field / focus and IME handoff.
  final ChatEnterInputBuilder? inputBuilder;

  /// Default composer height (island paint height).
  static const double rowHeight = ChatInputMetrics.islandHeight;

  @override
  State<ChatEnterView> createState() => ChatEnterViewState();
}

/// State for [ChatEnterView].
class ChatEnterViewState extends State<ChatEnterView>
    with TickerProviderStateMixin {
  late final ValueNotifier<bool> _hasText;

  /// `animatorTopViewVisibility` — 0 hidden, 1 shown.
  late final AnimationController _topViewVisibility;

  /// Progress of the current field-height tween (0→1).
  late final AnimationController _fieldHeightProgress;

  late final CurvedAnimation _topViewCurved;
  late final CurvedAnimation _fieldHeightCurved;

  double _fieldHeightFrom = ChatEnterView.rowHeight;
  double _fieldHeightTo = ChatEnterView.rowHeight;
  var _fieldHeightLaidOut = false;

  /// Keep painting the last banner while hide runs (`t→0`).
  ChatEnterTopBannerBuilder? _cachedBannerBuilder;
  ChatEnterTopBanner? _cachedBanner;

  TextEditingController get _text => widget.composer.text;
  FocusNode get _focus => widget.composer.focusNode;

  @override
  void initState() {
    super.initState();
    _hasText = ValueNotifier(_text.text.trim().isNotEmpty);
    _text.addListener(_onText);
    _focus.addListener(_onFocusChange);
    _bindComposer(widget.composer);

    final wantsTop = _wantsTopView;
    _cacheTopViewIfPresent();

    _topViewVisibility = AnimationController(
      vsync: this,
      duration: KeyboardPanelMotion.duration,
      value: wantsTop ? 1 : 0,
    );
    _topViewCurved = CurvedAnimation(
      parent: _topViewVisibility,
      curve: KeyboardPanelMotion.curve,
    );

    _fieldHeightProgress = AnimationController(
      vsync: this,
      duration: KeyboardPanelMotion.duration,
      value: 1,
    );
    _fieldHeightCurved = CurvedAnimation(
      parent: _fieldHeightProgress,
      curve: KeyboardPanelMotion.curve,
    );

    _topViewVisibility.addStatusListener(_onTopViewStatus);
  }

  @override
  void didUpdateWidget(ChatEnterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.composer, widget.composer)) {
      _unbindComposer(oldWidget.composer);
      oldWidget.composer.text.removeListener(_onText);
      oldWidget.composer.focusNode.removeListener(_onFocusChange);
      _text.addListener(_onText);
      _focus.addListener(_onFocusChange);
      _bindComposer(widget.composer);
      _hasText.value = _text.text.trim().isNotEmpty;
    }
    _syncTopViewVisibility();
  }

  @override
  void dispose() {
    _topViewVisibility.removeStatusListener(_onTopViewStatus);
    _unbindComposer(widget.composer);
    _text.removeListener(_onText);
    _focus.removeListener(_onFocusChange);
    _topViewCurved.dispose();
    _fieldHeightCurved.dispose();
    _topViewVisibility.dispose();
    _fieldHeightProgress.dispose();
    _hasText.dispose();
    super.dispose();
  }

  void _bindComposer(ChatComposerController composer) {
    composer.bindEnterProjection(
      onRequestKeyboard: requestKeyboard,
      onHideKeyboard: hideKeyboard,
      onHideKeyboardRetainingFocus: hideKeyboardRetainingFocus,
      onPrepareKeyboardHandoff: prepareKeyboardHandoff,
    );
    // IME suppress only — chrome rebuilds via [select] on the input row.
    _emojiImeListenable = composer.select((s) => s.data.emojiIcon);
    _emojiImeListenable!.addListener(_onEmojiIconForIme);
  }

  void _unbindComposer(ChatComposerController composer) {
    composer.bindEnterProjection();
    _emojiImeListenable?.removeListener(_onEmojiIconForIme);
    _emojiImeListenable = null;
  }

  ValueListenable<ChatEnterEmojiIconState>? _emojiImeListenable;

  void _onEmojiIconForIme() {
    if (!mounted) return;
    if (_suppressSoftKeyboard) _suppressIme();
  }

  bool get _wantsTopView =>
      widget.topBannerBuilder != null || widget.topBanner != null;

  double get _fieldHeight =>
      lerpDouble(_fieldHeightFrom, _fieldHeightTo, _fieldHeightCurved.value)!;

  void _cacheTopViewIfPresent() {
    if (widget.topBannerBuilder != null) {
      _cachedBannerBuilder = widget.topBannerBuilder;
      _cachedBanner = null;
    } else if (widget.topBanner != null) {
      _cachedBanner = widget.topBanner;
      _cachedBannerBuilder = null;
    }
  }

  void _syncTopViewVisibility() {
    final wants = _wantsTopView;
    if (wants) {
      _cacheTopViewIfPresent();
      if (_topViewVisibility.status != AnimationStatus.forward &&
          _topViewVisibility.value < 1) {
        _topViewVisibility.animateTo(1);
      } else if (_topViewVisibility.value == 1) {
        // Already shown — rebuild for subtitle / title changes.
      }
    } else if (_topViewVisibility.value > 0 || _topViewVisibility.isAnimating) {
      _topViewVisibility.animateTo(0);
    }
  }

  void _onTopViewStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed) return;
    if (_wantsTopView) return;
    if (_cachedBannerBuilder == null && _cachedBanner == null) return;
    setState(() {
      _cachedBannerBuilder = null;
      _cachedBanner = null;
    });
  }

  void _onFieldMeasured(Size size) {
    if (!mounted) return;
    final target = math.max(ChatEnterView.rowHeight, size.height);

    // First layout / cold start — set height immediately, no tween. Must run
    // before the no-change check: a cold start at the default height still
    // counts as laid out, otherwise the first real change would snap.
    if (!_fieldHeightLaidOut) {
      _fieldHeightLaidOut = true;
      if ((target - _fieldHeightTo).abs() < 0.5) return;
      setState(() {
        _fieldHeightFrom = target;
        _fieldHeightTo = target;
        _fieldHeightProgress.value = 1;
      });
      return;
    }

    if ((target - _fieldHeightTo).abs() < 0.5) return;

    _fieldHeightFrom = _fieldHeight;
    _fieldHeightTo = target;
    _fieldHeightProgress.forward(from: 0);
  }

  var _allowImeOnce = false;

  /// Keyboard panel open → keyboard icon; suppress OS IME while focused.
  bool get _suppressSoftKeyboard =>
      widget.composer.data.emojiIcon == ChatEnterEmojiIconState.keyboard;

  void _suppressIme() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  void _onFocusChange() {
    if (_allowImeOnce) {
      _allowImeOnce = false;
      // Search→composer tap transfers focus before [onTap]; keep soft IME up.
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      return;
    }
    if (!_suppressSoftKeyboard || !_focus.hasFocus) return;
    _suppressIme();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _suppressSoftKeyboard) _suppressIme();
    });
  }

  void _onText() {
    final next = _text.text.trim().isNotEmpty;
    if (next == _hasText.value) return;
    if (!mounted) return;
    _hasText.value = next;
  }

  /// Arms one focus gain so IME-suppress does not hide the soft keyboard.
  ///
  /// Call on pointer-down of the composer field while the keyboard panel is
  /// open — [TextField] steals focus before [onTap], ahead of [requestKeyboard].
  /// Prefer [ChatComposerController.prepareKeyboardHandoff] from hosts.
  void prepareKeyboardHandoff() {
    _allowImeOnce = true;
  }

  /// Programmatic focus + IME show.
  ///
  /// Bypasses keyboard-panel IME suppression once so focus handoff from the
  /// emoji search field does not hide-then-show the soft keyboard.
  /// Prefer [ChatComposerController.requestKeyboard] from hosts.
  void requestKeyboard() {
    final alreadyFocused = _focus.hasFocus;
    // If focus already landed via a prepared tap, do not leave the arm stuck.
    _allowImeOnce = !alreadyFocused;
    _focus.requestFocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  /// Hides IME. Prefer [ChatComposerController.hideKeyboard] from hosts.
  void hideKeyboard() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  /// Hides soft IME but keeps the field focused (keyboard panel open).
  ///
  /// Call only while [ChatEnterEmojiIconState.keyboard] suppresses IME show.
  /// Prefer [ChatComposerController.hideKeyboardRetainingFocus] from hosts.
  void hideKeyboardRetainingFocus() {
    _suppressIme();
    if (!_focus.hasFocus) {
      _focus.requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _suppressIme();
    });
  }

  Widget? _buildTopView(BuildContext context) {
    final t = _topViewCurved.value;
    if (t <= 0 && !_wantsTopView) return null;

    final child = switch ((_cachedBannerBuilder, _cachedBanner)) {
      (final builder?, _) => builder(context),
      (null, final banner?) => ChatEnterTopView(
        title: banner.title,
        subtitle: banner.subtitle,
        isEdit: banner.isEdit,
        onClose: widget.onTopBannerClose ?? () {},
      ),
      (null, null) => null,
    };
    if (child == null) return null;

    // Layout height = barH * t; child always barH; clip from the top so the
    // strip appears top-first as the slot grows.
    return _TopViewReveal(
      progress: t,
      extent: ChatEnterTopView.barHeight,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final composer = widget.composer;
    final colors = ChatChromeTheme.of(context);
    final brightness = Theme.of(context).brightness;
    final glassStyle = TelegramGlassStyle.composerIsland(
      panelBackground: colors.messagePanelBackground,
      brightness: brightness,
      cornerRadius: ChatInputMetrics.bubbleRadius,
    );

    final inputRow = switch (widget.inputBuilder) {
      final builder? => builder(
        context,
        ChatEnterFieldHandle(
          controller: composer.text,
          focusNode: composer.focusNode,
          prepareKeyboardHandoff: prepareKeyboardHandoff,
        ),
      ),
      null => ValueListenableBuilder(
        valueListenable: widget.composer.select(
          (s) => (
            emoji: s.data.emojiIcon,
            busy: s.data.busy,
            enabled: s.data.enabled,
            editing: s.data.mode.isEditing,
          ),
          (prev, next) => prev != next,
        ),
        builder: (context, data, child) => _InputRow(
          controller: composer.text,
          focusNode: composer.focusNode,
          colors: colors,
          hintText: widget.hintText,
          emojiIconState: data.emoji,
          onEmojiPressed: widget.onEmojiPressed,
          onAttachPressed: widget.onAttachPressed,
          onSend: widget.onSend,
          onMicPressed: widget.onMicPressed,
          hasText: _hasText,
          sending: data.busy,
          isEditing: data.editing,
          enabled: data.enabled,
          onFieldTapWhilePanelOpen: widget.onFieldTapWhilePanelOpen,
          onPrepareKeyboardHandoff: widget.onFieldTapWhilePanelOpen == null
              ? null
              : prepareKeyboardHandoff,
        ),
      ),
    };

    return Material(
      color: Colors.transparent,
      // Bottom-anchored — island grows upward from a fixed baseline.
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: TelegramGlass(
            key: widget.glassKey,
            style: glassStyle,
            child: AnimatedBuilder(
              animation: Listenable.merge([_topViewCurved, _fieldHeightCurved]),
              child: inputRow,
              builder: (context, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ?_buildTopView(context),
                    _AnimatedFieldHeight(
                      height: _fieldHeight,
                      onChildSize: _onFieldMeasured,
                      child: child!,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Clip-reveals a fixed-[extent] child as [progress] rises (top-aligned).
///
/// Layout height is `extent * progress`; the child always lays out at [extent]
/// and is clipped from the top so the upper part of the strip appears first.
class _TopViewReveal extends SingleChildRenderObjectWidget {
  const _TopViewReveal({
    required this.progress,
    required this.extent,
    required Widget super.child,
  });

  final double progress;
  final double extent;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderTopViewReveal(progress: progress, extent: extent);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderTopViewReveal renderObject,
  ) {
    renderObject
      ..progress = progress
      ..extent = extent;
  }
}

class _RenderTopViewReveal extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderTopViewReveal({required double progress, required double extent})
    : _progress = progress,
      _extent = extent;

  double _progress;
  double get progress => _progress;
  set progress(double value) {
    if (_progress == value) return;
    _progress = value;
    markNeedsLayout();
  }

  double _extent;
  double get extent => _extent;
  set extent(double value) {
    if (_extent == value) return;
    _extent = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : (child?.getMaxIntrinsicWidth(double.infinity) ?? 0);
    final hostH = _extent * _progress.clamp(0.0, 1.0);
    child?.layout(
      BoxConstraints.tightFor(width: width, height: _extent),
      parentUsesSize: true,
    );
    size = constraints.constrain(Size(width, hostH));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null || size.isEmpty) return;
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      offset,
    ) {
      // Top-aligned: as host grows, the top of the strip appears first.
      context.paintChild(c, offset);
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintOffset(
      offset: Offset.zero,
      position: position,
      hitTest: (result, transformed) {
        return transformed.dy <= size.height &&
            c.hitTest(result, position: transformed);
      },
    );
  }
}

/// Host height animates; child lays out intrinsically and paints bottom-aligned
/// so growth expands above a fixed baseline.
class _AnimatedFieldHeight extends SingleChildRenderObjectWidget {
  const _AnimatedFieldHeight({
    required this.height,
    required this.onChildSize,
    required Widget super.child,
  });

  final double height;
  final ValueChanged<Size> onChildSize;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderAnimatedFieldHeight(height: height, onChildSize: onChildSize);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderAnimatedFieldHeight renderObject,
  ) {
    renderObject
      ..height = height
      ..onChildSize = onChildSize;
  }
}

class _RenderAnimatedFieldHeight extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderAnimatedFieldHeight({
    required double height,
    required this.onChildSize,
  }) : _height = height;

  ValueChanged<Size> onChildSize;
  Size? _reported;

  double _height;
  double get height => _height;
  set height(double value) {
    if (_height == value) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : (child?.getMaxIntrinsicWidth(double.infinity) ?? 0);
    final c = child;
    if (c != null) {
      c.layout(
        BoxConstraints(
          minWidth: width,
          maxWidth: width,
          maxHeight: double.infinity,
        ),
        parentUsesSize: true,
      );
      final childSize = c.size;
      if (childSize != _reported) {
        _reported = childSize;
        final reported = childSize;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (attached) onChildSize(reported);
        });
      }
    }
    size = constraints.constrain(Size(width, _height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    // Bottom-aligned: grow/shrink expands above the baseline.
    final dy = size.height - c.size.height;
    context.paintChild(c, offset + Offset(0, dy));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    final dy = size.height - c.size.height;
    return result.addWithPaintOffset(
      offset: Offset(0, dy),
      position: position,
      hitTest: (result, transformed) {
        return c.hitTest(result, position: transformed);
      },
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.focusNode,
    required this.colors,
    required this.hintText,
    required this.emojiIconState,
    required this.onEmojiPressed,
    required this.onAttachPressed,
    required this.onSend,
    required this.onMicPressed,
    required this.hasText,
    required this.sending,
    required this.isEditing,
    required this.enabled,
    this.onFieldTapWhilePanelOpen,
    this.onPrepareKeyboardHandoff,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ChatChromeColors colors;
  final String hintText;
  final ChatEnterEmojiIconState emojiIconState;
  final VoidCallback onEmojiPressed;
  final VoidCallback? onAttachPressed;
  final VoidCallback? onSend;
  final VoidCallback? onMicPressed;
  final ValueNotifier<bool> hasText;
  final bool sending;
  final bool isEditing;
  final bool enabled;
  final VoidCallback? onFieldTapWhilePanelOpen;
  final VoidCallback? onPrepareKeyboardHandoff;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Horizontal only — vertical chrome is the 44 island.
      // Extra top/bottom pad made the glass taller than 44, so radius 22 no
      // longer read as a stadium (half-height pill).
      padding: const EdgeInsetsDirectional.only(start: 2, end: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          ChatEnterIconButton(
            icon: emojiIconFor(emojiIconState),
            morph: true,
            onPressed: enabled ? onEmojiPressed : null,
          ),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ChatEnterView.rowHeight,
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: 9,
                  bottom: 10,
                  end: 4,
                ),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: onPrepareKeyboardHandoff == null
                      ? null
                      : (_) => onPrepareKeyboardHandoff!(),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: enabled,
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onTap: onFieldTapWhilePanelOpen,
                    cursorColor: colors.messagePanelCursor,
                    style: TextStyle(
                      color: colors.messagePanelText,
                      fontSize: 18,
                      height: 1.25,
                    ),
                    decoration: InputDecoration.collapsed(
                      hintText: hintText,
                      hintStyle: TextStyle(
                        color: colors.messagePanelHint,
                        fontSize: 18,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          ChatEnterIconButton(
            icon: Icons.attach_file_rounded,
            onPressed: enabled ? onAttachPressed : null,
          ),
          ValueListenableBuilder(
            valueListenable: hasText,
            builder: (context, hasText, child) {
              return ChatEnterSendMicButton(
                hasText: hasText,
                onSend: onSend,
                onMic: onMicPressed,
                sending: sending,
                isEditing: isEditing,
              );
            },
          ),
        ],
      ),
    );
  }
}
