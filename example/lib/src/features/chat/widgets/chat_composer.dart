import 'dart:async';
import 'dart:math' as math;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/widgets/listen_value_builder.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_suggestion_bar.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart'
    show
        InkWell,
        ScaffoldFeatureController,
        ScaffoldMessenger,
        ScaffoldMessengerState,
        SnackBar,
        SnackBarBehavior,
        SnackBarClosedReason;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// The chat's composer island: a [ComposerView] over the chat's
/// [ChatInputSet].
///
/// Hidden while a selection is active (the actions live on the selection app
/// bar, not on a morph of this island); starting a selection leaves edit mode
/// and takes focus away. Builds the [ComposerSpec] of the moment from the
/// input set and the strings of the chrome, and on platforms with an anchored
/// popup reports where the island is so the popup can sit on it.
class ChatComposer extends StatefulWidget {
  /// The composer of [input].
  const ChatComposer({
    required this.input,
    required this.selection,
    required this.islandKey,
    this.anchorSpace,
    this.onAttachPressed,
    this.onVoicePressed,
    super.key,
  });

  /// The chat's input set.
  final ChatInputSet input;

  /// When a selection is active the island is hidden.
  final ChatSelectionController selection;

  /// Key of the glass island, for the bottom fade's cutout.
  final GlobalKey islandKey;

  /// The box whose coordinates the popup's anchor is reported in, when the
  /// presentation is an anchored popup. Null reports nothing.
  final GlobalKey? anchorSpace;

  /// Attach button.
  final VoidCallback? onAttachPressed;

  /// The voice button while the composer is empty.
  final VoidCallback? onVoicePressed;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  var _selectionMode = false;
  var _anchorWatched = false;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _toast;
  ScaffoldMessengerState? _messenger;

  ChatInputSet get _input => widget.input;

  @override
  void initState() {
    super.initState();
    _selectionMode = widget.selection.isSelectionMode;
    widget.selection.addListener(_onSelectionChanged);
    widget.input.formatOffer.addListener(_onFormatOffer);
    _watchAnchor();
  }

  @override
  void didUpdateWidget(ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.selection, widget.selection)) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
      _onSelectionChanged();
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    widget.input.formatOffer.removeListener(_onFormatOffer);
    _closeToastAfterTeardown();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  // --- Apply-formatting toast -------------------------------------------------

  // The input set owns the offer (its lifetime and its end on any edit); this
  // only draws it. The toast has no timeout of its own, so that the set's is
  // the one that ends it.
  void _onFormatOffer() {
    if (widget.input.formatOffer.value == null) {
      _closeToast();
      return;
    }
    final messenger = _messenger;
    if (messenger == null) return;
    _closeToast();
    final bottom = widget.input.insets.bottomPadding.value;
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max<double>(16, (width - _toastMaxWidth) / 2);
    final toast = messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        persist: true,
        margin: EdgeInsets.fromLTRB(side, 0, side, bottom + _toastGap),
        content: InkWell(
          onTap: widget.input.applyFormatOffer,
          child: const Text('Apply formatting'),
        ),
      ),
    );
    _toast = toast;
    unawaited(
      toast.closed.then((_) {
        // Closed by the user (swiped away), not by the set ending the offer.
        if (!identical(_toast, toast)) return;
        _toast = null;
        widget.input.dismissFormatOffer();
      }),
    );
  }

  void _closeToast() {
    final toast = _toast;
    _toast = null;
    toast?.close();
  }

  // The messenger and the tree below it are being torn down when the screen
  // goes: a close then looks up a deactivated ancestor. A frame later the
  // messenger either lives on (the toast is closed) or is gone with the toast.
  void _closeToastAfterTeardown() {
    final toast = _toast;
    final messenger = _messenger;
    _toast = null;
    if (toast == null || messenger == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (messenger.mounted) toast.close();
    });
  }

  static const double _toastMaxWidth = 400;
  static const double _toastGap = 8;

  void _onSelectionChanged() {
    final mode = widget.selection.isSelectionMode;
    if (mode == _selectionMode) return;
    if (mode) {
      _input
        ..cancelEdit()
        ..composer.unfocus();
    }
    setState(() => _selectionMode = mode);
  }

  // --- Popup anchor ---------------------------------------------------------

  // The island moves without this widget rebuilding: a dock that comes or
  // goes pads the chat region around it, the window resizes, the composer
  // grows. So its place is read after every frame and reported when it
  // changed (the controller ignores an equal one). A post-frame callback
  // schedules no frame, so an idle screen costs nothing.
  void _watchAnchor() {
    if (_anchorWatched) return;
    _anchorWatched = true;
    SchedulerBinding.instance.addPostFrameCallback(_onAnchorFrame);
  }

  void _onAnchorFrame(Duration _) {
    if (!mounted) {
      _anchorWatched = false;
      return;
    }
    if (widget.anchorSpace != null && !_selectionMode) _reportAnchor();
    SchedulerBinding.instance.addPostFrameCallback(_onAnchorFrame);
  }

  void _reportAnchor() {
    final island = widget.islandKey.currentContext?.findRenderObject();
    final space = widget.anchorSpace?.currentContext?.findRenderObject();
    if (island is! RenderBox ||
        space is! RenderBox ||
        !island.attached ||
        !space.attached) {
      return;
    }
    final origin = island.localToGlobal(Offset.zero, ancestor: space);
    _input.anchorTo(origin & island.size);
  }

  // --- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_selectionMode) return const SizedBox.shrink();
    final strings = ChromeStringsScope.of(context);
    final composer = _input.composer;
    final inset = _input.composerSafeInset;
    return ListenableBuilder(
      listenable: Listenable.merge([
        composer.text,
        _input.editing,
        _input.busy,
        _input.leavingForKeyboard,
        ListenableBridge(_input.presentation.state),
        ListenableBridge(_input.shell.selectedPageId),
        ListenableBridge(composer.query),
        ListenableBridge(_input.linkPreview.card),
      ]),
      builder: (context, _) {
        final spec = buildChatComposerSpec(
          strings: strings,
          editing: _input.editing.value,
          hasText: composer.text.text.trim().isNotEmpty,
          busy: _input.busy.value,
          messageLengthLimit: _input.messageLengthLimit,
          panelReplacesKeyboard: _input.panelReplacesKeyboard,
          panelDocked: _input.isPanelDocked,
          panelPlacement: _input.panelPlacement,
          wrapPanelToggle: _input.wrapPanelToggle,
          pageIcon: _input.pageIcon,
          onTogglePanel: _input.togglePanel,
          onSubmit: () => unawaited(_input.submit()),
          onAttach: widget.onAttachPressed ?? () {},
          onVoice: widget.onVoicePressed ?? () {},
          onCancelEdit: _input.cancelEdit,
          suggestions: ChatSuggestions.header(
            composer.query.value,
            onPick: composer.replaceQuery,
          ),
          linkPreview: switch (_input.linkPreview.card.value) {
            final card? => ComposerHeader.linkPreview(
              title: card.title,
              preview: card.url,
              onDismiss: _input.linkPreview.dismiss,
            ),
            null => null,
          },
          linkPrompt: _input.linkPrompt,
          backPriority: ChatInputSet.claimBack,
        );
        Widget view(double? safeAreaBottom) => _input.keepPopupOpenOver(
          ComposerView(
            controller: composer,
            spec: spec,
            islandKey: widget.islandKey,
            onFieldTap: _input.onFieldTap,
            onFieldPointerDown: _input.onFieldPointerDown,
            onFieldPointerEnd: _input.onFieldPointerEnd,
            safeAreaBottom: safeAreaBottom,
          ),
        );
        // The keyboard presentation owns the bottom band while it is up; the
        // composer pads itself with what the occupancy has not covered yet.
        // Without one the composer keeps its default pad.
        return switch (inset) {
          final safeInset? => ListenValueBuilder<double>(
            listenable: safeInset,
            builder: (context, safe) => view(safe),
          ),
          null => view(null),
        };
      },
    );
  }
}
