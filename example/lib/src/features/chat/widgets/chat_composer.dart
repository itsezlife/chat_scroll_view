import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/widgets/listen_value_builder.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
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

  ChatInputSet get _input => widget.input;

  @override
  void initState() {
    super.initState();
    _selectionMode = widget.selection.isSelectionMode;
    widget.selection.addListener(_onSelectionChanged);
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
    super.dispose();
  }

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
