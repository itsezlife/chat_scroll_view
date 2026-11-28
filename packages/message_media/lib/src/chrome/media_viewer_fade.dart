import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:listen/listen.dart' show ValueListenable;
import 'package:message_media/src/state/message_media_state.dart';

/// Builds the overlays of [items] at [overlays] (their opacity) and the
/// picture shown or not ([pictureHidden]).
typedef MediaViewerFadeBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> overlays, {
      required bool pictureHidden,
    });

/// What the media viewer does to the cells of [items] while it stands over
/// them, read from the chat's [state] (`MessageMediaState.setViewerHidden`
/// and `setViewerCovered`).
///
/// The overlays go at once when any item is hidden or covered (the viewer's
/// morph is over the cell by then) and fade back in over [fadeIn] on
/// [curve] once every item is let go; the picture is hidden while any item
/// is hidden and shows again at once.
///
/// The cells use it for their status control, badge and options; a host
/// wraps the overlays it draws over the media itself (the time pill) in
/// one, so they fade together:
///
/// ```dart
/// MediaViewerFade(state: state, items: ids, child: timePill)
/// ```
class MediaViewerFade extends StatefulWidget {
  /// Fades [child] (or what [builder] builds) as the viewer covers [items].
  const MediaViewerFade({
    required this.state,
    required this.items,
    this.child,
    this.builder,
    this.fadeIn = defaultFadeIn,
    this.curve = Curves.decelerate,
    super.key,
  }) : assert(
         (child == null) != (builder == null),
         'Give a child or a builder.',
       );

  /// How long the overlays take to come back.
  static const Duration defaultFadeIn = Duration(milliseconds: 200);

  /// The chat's media state.
  final MessageMediaState state;

  /// The items whose cells the overlays belong to.
  final List<MediaItemId> items;

  /// Drawn at the overlays' opacity; null with a [builder].
  final Widget? child;

  /// Builds from the overlays' opacity and the picture's state; null with a
  /// [child].
  final MediaViewerFadeBuilder? builder;

  /// How long the overlays take to fade back in.
  final Duration fadeIn;

  /// The fade-in's curve.
  final Curve curve;

  @override
  State<MediaViewerFade> createState() => _MediaViewerFadeState();
}

class _MediaViewerFadeState extends State<MediaViewerFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );
  late Animation<double> _overlays = _curved();
  List<ValueListenable<MediaItemState>> _listened = const [];
  bool _hidden = false;

  Animation<double> _curved() =>
      CurvedAnimation(parent: _controller, curve: widget.curve);

  @override
  void initState() {
    super.initState();
    _subscribe();
    _hidden = _anyHidden;
    _controller.value = _overlaysShown ? 1 : 0;
  }

  @override
  void didUpdateWidget(MediaViewerFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.curve != widget.curve) _overlays = _curved();
    if (oldWidget.state != widget.state ||
        !_sameIds(oldWidget.items, widget.items)) {
      _unsubscribe();
      _subscribe();
      _onState();
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    _controller.dispose();
    super.dispose();
  }

  static bool _sameIds(List<MediaItemId> a, List<MediaItemId> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _subscribe() {
    _listened = [
      for (final id in widget.items) widget.state.of(id)..addListener(_onState),
    ];
  }

  void _unsubscribe() {
    for (final listenable in _listened) {
      listenable.removeListener(_onState);
    }
    _listened = const [];
  }

  bool get _anyHidden => _listened.any((state) => state.value.viewerHidden);

  bool get _overlaysShown =>
      _listened.every((state) => state.value.overlaysShown);

  void _onState() {
    if (!mounted) return;
    final hidden = _anyHidden;
    if (hidden != _hidden) setState(() => _hidden = hidden);
    if (!_overlaysShown) {
      _controller.value = 0;
    } else if (_controller.value < 1 && !_controller.isAnimating) {
      _controller
        ..duration = widget.fadeIn
        ..forward();
    }
  }

  @override
  Widget build(BuildContext context) => switch (widget.builder) {
    final builder? => builder(context, _overlays, pictureHidden: _hidden),
    null => FadeTransition(opacity: _overlays, child: widget.child),
  };
}
