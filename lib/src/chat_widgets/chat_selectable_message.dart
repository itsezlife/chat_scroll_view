import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_chrome.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Headless selection host: mode/select animations and freeze-on-exit.
///
/// The viewport owns the selection pointer (long-press / tap). This widget
/// only paints chrome — [chromeBuilder] must not attach a competing
/// detector. Chrome is built by [chromeBuilder] (defaults to
/// [DefaultSelectionChrome.wrap]). Restyle the bundled chrome with
/// [ChatSelectionThemeData]; replace layout entirely with
/// `ChatScrollView.selectionChromeBuilder`.
///
/// ### Freeze on exit
///
/// When selection mode turns off — [ChatSelectionController.clear] or toggling
/// the last selected id — [ChatSelectionChromeState.selectProgress] stays at
/// its last value. Only [ChatSelectionChromeState.modeProgress] animates to 0,
/// so the check does not play an unselect animation. Re-entering snaps
/// select progress to the live set before the mode animation runs.
class SelectableMessage extends StatefulWidget {
  /// Wraps [child] with animated selection chrome for [id].
  const SelectableMessage({
    required this.id,
    required this.controller,
    required this.child,
    this.scrollController,
    this.chromeBuilder = DefaultSelectionChrome.wrap,
    super.key,
  });

  /// Message id this row represents.
  final int id;

  /// Shared selection state.
  final ChatSelectionController controller;

  /// Suppresses chrome-driven tap / long-press while a fling-cancel is in
  /// progress. The viewport applies the same guard to its own pointer.
  final ChatScrollController? scrollController;

  /// Builds chrome around [child]. Must be a stable tear-off.
  final ChatSelectionChromeBuilder chromeBuilder;

  /// Message body. Built once per host rebuild; chrome animates around it.
  final Widget child;

  @override
  State<SelectableMessage> createState() => _SelectableMessageState();
}

class _SelectableMessageState extends State<SelectableMessage>
    with TickerProviderStateMixin {
  late final AnimationController _mode;
  late final AnimationController _select;
  late final Listenable _animation;
  late bool _liveMode;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    _liveMode = c.isSelectionMode;
    _mode = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: _liveMode ? 1.0 : 0.0,
    );
    _select = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: c.isSelected(widget.id) ? 1.0 : 0.0,
    );
    _animation = Listenable.merge(<Listenable>[_mode, _select]);
    c.addListener(_onSelectionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = ChatScrollTheme.resolve(context).selection!;
    _mode.duration = theme.modeDuration;
    _select.duration = theme.selectDuration;
  }

  @override
  void didUpdateWidget(SelectableMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerSwapped = !identical(
      oldWidget.controller,
      widget.controller,
    );
    final idSwapped = oldWidget.id != widget.id;
    if (controllerSwapped) {
      oldWidget.controller.removeListener(_onSelectionChanged);
      widget.controller.addListener(_onSelectionChanged);
    }
    // Only re-sync when something the animation depends on actually changed.
    // Parent rebuilds with the same id+controller would otherwise enqueue
    // animation work for every visible message every frame.
    if (controllerSwapped || idSwapped) {
      _onSelectionChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSelectionChanged);
    _mode.dispose();
    _select.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final c = widget.controller;
    final mode = c.isSelectionMode;
    final selected = c.isSelected(widget.id);
    if (mode && !_liveMode) {
      _select.value = selected ? 1.0 : 0.0;
      _mode.animateTo(1);
    } else if (!mode && _liveMode) {
      _mode.animateTo(0);
    } else if (mode) {
      _select.animateTo(selected ? 1.0 : 0.0);
    }
    _liveMode = mode;
  }

  bool get _flingCancelSuppressesGestures =>
      widget.scrollController?.flingCancelSuppressesLongPress ?? false;

  void _handleLongPress() {
    if (_flingCancelSuppressesGestures) return;
    final c = widget.controller;
    // Already selected: long-press on an already-selected message is a no-op
    // for the controller, so don't buzz either.
    if (c.isSelected(widget.id)) return;
    HapticFeedback.vibrate();
    c.startSelection(widget.id);
  }

  void _handleTap() {
    if (_flingCancelSuppressesGestures) return;
    final c = widget.controller;
    // Outside selection mode a tap on a message does nothing (there is no
    // in-message interaction in this demo); inside it toggles the message.
    if (!c.isSelectionMode) return;
    c.toggle(widget.id);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, child) => widget.chromeBuilder(
      context,
      ChatSelectionChromeState(
        id: widget.id,
        modeProgress: _mode.value.clamp(0.0, 1.0),
        selectProgress: _select.value.clamp(0.0, 1.0),
        isSelectionMode: widget.controller.isSelectionMode,
        isSelected: widget.controller.isSelected(widget.id),
        onTap: _handleTap,
        onLongPress: _handleLongPress,
      ),
      child!,
    ),
    child: widget.child,
  );
}
