import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' show ValueListenable;
import 'package:message_media/src/chrome/media_chrome_slots.dart';
import 'package:message_media/src/chrome/media_options_affordance.dart';
import 'package:message_media/src/chrome/media_viewer_fade.dart';
import 'package:message_media/src/diagnostics/media_build_guard.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:message_media/src/state/message_media_state.dart';
import 'package:mpx_core/mpx_core.dart' show AutoDownloadContext;

/// Gives the cell below it the opacity of its controls: 0 while a spoiler
/// hides the item, rising with the reveal, 1 otherwise.
///
/// A box cell fades its status control with it (and takes no taps on it
/// until it is fully shown); without a scope the controls are shown.
class MediaControlsScope extends InheritedWidget {
  /// Gives [child] the [controls] opacity.
  const MediaControlsScope({
    required this.controls,
    required super.child,
    super.key,
  });

  /// The controls' opacity, 0 to 1.
  final Animation<double> controls;

  /// The opacity of the nearest scope, or always 1 without one.
  static Animation<double> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<MediaControlsScope>()
          ?.controls ??
      kAlwaysCompleteAnimation;

  @override
  bool updateShouldNotify(MediaControlsScope oldWidget) =>
      controls != oldWidget.controls;
}

/// The chrome over one cell: the spoiler's cover and its reveal, the
/// options affordance, and the controls' opacity the cell reads.
///
/// The revealed fact lives in [state] (per chat, by item id), so a cell
/// built again, moved or laid out anew keeps it; only the reveal's motion
/// is this widget's. A reveal starts when the state turns the item
/// revealed: from the origin the gesture left (`MessageMediaState
/// .revealSpoiler(at:)`), else the cell's centre; under reduce motion it
/// jumps to revealed. Each start reports `media` / `spoilerRevealed`.
///
/// While the media viewer stands over the item ([MediaViewerFade], from the
/// state's `setViewerHidden` / `setViewerCovered`) the cell's picture is
/// hidden and its controls and options are gone; they fade back in once the
/// viewer lets the item go.
class MediaCellChrome extends StatefulWidget {
  /// The chrome of [cell] over [child].
  const MediaCellChrome({
    required this.cell,
    required this.item,
    required this.block,
    required this.family,
    required this.slots,
    required this.state,
    required this.child,
    this.context = MediaChromeContext.none,
    this.selectionProgress,
    this.downloadContext,
    this.correlation = ChatCorrelation.none,
    super.key,
  });

  /// The cell, in layout coordinates.
  final MediaCell cell;

  /// The cell's item.
  final MediaItem item;

  /// The block the cell sits in.
  final MediaBlock block;

  /// The policy's family.
  final MessageMediaPlatform family;

  /// The chrome slots.
  final MediaChromeSlots slots;

  /// The chat's media state.
  final MessageMediaState state;

  /// What the message is drawn in.
  final MediaChromeContext context;

  /// The selection checkbox's appearance, 0 to 1; the options affordance
  /// fades out as it rises. Null is no checkbox.
  final Animation<double>? selectionProgress;

  /// The class of conversation the media is shown in.
  final AutoDownloadContext? downloadContext;

  /// The ids the chrome's events name.
  final ChatCorrelation correlation;

  /// The cell itself.
  final Widget child;

  @override
  State<MediaCellChrome> createState() => _MediaCellChromeState();
}

class _MediaCellChromeState extends State<MediaCellChrome>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);
  late Animation<double> _reveal = _controller;
  late ValueListenable<MediaItemState> _itemState;
  Offset? _origin;

  bool get _covers => MediaChromeSlots.coversSpoiler(widget.item, widget.cell);

  @override
  void initState() {
    super.initState();
    _subscribe();
    _controller.value = _hidden ? 0 : 1;
  }

  bool get _hidden =>
      _covers && !widget.state.isSpoilerRevealed(widget.item.id);

  void _subscribe() {
    _itemState = widget.state.of(widget.item.id)..addListener(_onState);
  }

  @override
  void didUpdateWidget(MediaCellChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.item.id != widget.item.id) {
      _itemState.removeListener(_onState);
      _subscribe();
    }
    if (_controller.isAnimating) return;
    final value = _hidden ? 0.0 : 1.0;
    if (_controller.value != value) {
      _reveal = _controller;
      _controller.value = value;
    }
  }

  @override
  void dispose() {
    _itemState.removeListener(_onState);
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    // The cover goes once the reveal completes.
    if (status.isCompleted && mounted) setState(() {});
  }

  void _onState() {
    if (!_covers || _controller.value >= 1 || _controller.isAnimating) return;
    if (!widget.state.isSpoilerRevealed(widget.item.id)) return;
    _startReveal();
  }

  void _startReveal() {
    final size = widget.cell.rect.size;
    final origin =
        widget.state.takeRevealOrigin(widget.item.id) ??
        size.center(Offset.zero);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final form = widget.slots.reveal;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.media,
      MediaOp.spoilerRevealed,
      correlation: ChatCorrelation(
        chatId: widget.correlation.chatId,
        scrollId: widget.correlation.scrollId,
        clientMessageId: widget.correlation.clientMessageId,
        mediaItemId: widget.item.id.toString(),
      ),
      fields: () => {
        'platform': widget.family,
        'form': form.name,
        'reduceMotion': reduceMotion,
      },
    );
    setState(() {
      _origin = origin;
      if (reduceMotion) {
        _reveal = _controller;
        _controller.value = 1;
        return;
      }
      final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
      final delay = form.delay;
      final total = form.totalOf(size, origin, devicePixelRatio: ratio);
      final start = total == Duration.zero
          ? 0.0
          : delay.inMicroseconds / total.inMicroseconds;
      _reveal = CurvedAnimation(
        parent: _controller,
        curve: Interval(start, 1, curve: form.curve),
      );
      _controller
        ..duration = total
        ..forward(from: 0);
    });
  }

  MediaChromeData get _data => MediaChromeData(
    cell: widget.cell,
    item: widget.item,
    family: widget.family,
    downloadContext: widget.downloadContext,
  );

  Widget _guarded(
    MediaBuilder builder,
    Widget Function() build,
    Widget fallback,
  ) => MediaBuildGuard.run(
    builder,
    item: widget.item,
    correlation: widget.correlation,
    build: build,
    fallback: fallback,
  );

  @override
  Widget build(BuildContext context) {
    final size = widget.cell.rect.size;
    final covered = _covers && _controller.value < 1;
    final affordance = widget.slots.options.affordanceOf(
      widget.cell,
      widget.block,
      context: widget.context,
      spoilerHidden: _hidden,
      smallImage: switch (widget.block) {
        final MediaBlock$LinkPreview card => card.smallMedia,
        _ => false,
      },
    );
    final reveal = _covers ? _reveal : kAlwaysCompleteAnimation;
    return MediaViewerFade(
      state: widget.state,
      items: [widget.item.id],
      builder: (context, overlays, {required pictureHidden}) {
        final controls = AnimationMin<double>(reveal, overlays);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            KeyedSubtree(
              key: const ValueKey('cell'),
              // Hidden in place, not removed: the cell keeps its element
              // and binding while the viewer's copy stands over it.
              child: Opacity(
                key: const ValueKey('viewer-source'),
                opacity: pictureHidden ? 0 : 1,
                child: MediaControlsScope(
                  controls: controls,
                  child: widget.child,
                ),
              ),
            ),
            if (covered)
              Positioned.fill(
                key: const ValueKey('spoiler'),
                // A spoiler slot that fails must not show what it hides: the
                // fallback is an opaque cover.
                child: _guarded(
                  MediaBuilder.spoiler,
                  () => widget.slots.spoiler(
                    context,
                    MediaSpoilerData(
                      chrome: _data,
                      reveal: _reveal,
                      origin: _origin ?? size.center(Offset.zero),
                      form: widget.slots.reveal,
                    ),
                  ),
                  const ColoredBox(color: Color(0xFF000000)),
                ),
              ),
            if (affordance?.shift(-widget.cell.rect.topLeft) case final local?)
              Positioned.fromRect(
                key: const ValueKey('options'),
                rect: local.iconRect,
                child: _OptionsFade(
                  controls: controls,
                  selection: widget.selectionProgress,
                  child: _guarded(
                    MediaBuilder.options,
                    () => widget.slots.optionsAffordance(
                      context,
                      MediaOptionsData(chrome: _data, affordance: local),
                    ),
                    const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// The affordance's opacity: the controls' (it fades in with a reveal) times
// `1 − selection` (it fades out while the selection checkbox comes in).
class _OptionsFade extends StatelessWidget {
  const _OptionsFade({
    required this.controls,
    required this.selection,
    required this.child,
  });

  final Animation<double> controls;
  final Animation<double>? selection;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controls, ?selection]),
    builder: (context, child) => Opacity(
      opacity: (controls.value * (1 - (selection?.value ?? 0))).clamp(0, 1),
      child: child,
    ),
    child: child,
  );
}
