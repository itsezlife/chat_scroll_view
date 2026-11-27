import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/diagnostics/media_op.dart';
import 'package:message_media/src/outgoing/media_send_flight_policy.dart';
import 'package:message_media/src/policy/message_media_policy.dart';
import 'package:message_media/src/state/message_media_state.dart';
import 'package:meta/meta.dart';

/// A cell that, built for the first time, flies in from its item's send
/// origin as [policy] says.
///
/// Where the policy flies it asks [state] for the origin once, before its
/// first frame, so the cell never shows in place first. With an origin it
/// hides [child] and draws [flying] in the overlay at a rect moving from
/// the origin to the cell's current rect, read again every frame: the row
/// may move under the flight (a tail rebase, the list following the
/// bottom) and the flight lands where the cell is. Under reduce motion, or
/// without an overlay, the cell shows in place. Each origin handed out
/// reports `media` / `sendOriginFlight`.
@internal
class MediaSendFlight extends StatefulWidget {
  /// The cell of [itemId], [size] large, over [child].
  const MediaSendFlight({
    required this.itemId,
    required this.size,
    required this.state,
    required this.policy,
    required this.family,
    required this.flying,
    required this.child,
    this.correlation = ChatCorrelation.none,
    super.key,
  });

  /// The item the cell draws.
  final MediaItemId itemId;

  /// The cell's size, which [flying] is built at and scaled from.
  final Size size;

  /// The chat's media state, which hands out the origin.
  final MessageMediaState state;

  /// The flight's timing.
  final MediaSendFlightPolicy policy;

  /// The policy's family, named in diagnostics.
  final MessageMediaPlatform family;

  /// Builds the picture that flies.
  final WidgetBuilder flying;

  /// The cell in place.
  final Widget child;

  /// The ids the flight's event names.
  final ChatCorrelation correlation;

  @override
  State<MediaSendFlight> createState() => _MediaSendFlightState();
}

class _MediaSendFlightState extends State<MediaSendFlight>
    with SingleTickerProviderStateMixin {
  final OverlayPortalController _portal = OverlayPortalController();
  AnimationController? _controller;
  Rect? _origin;
  Rect? _lastTarget;
  bool _asked = false;

  // Whether this element carries the overlay portal. Decided once, before
  // the first build: adding or removing the wrapper later would build the
  // cell anew and lose its binding.
  bool _portalled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    _ask();
  }

  void _ask() {
    if (!widget.policy.flies) return;
    final origin = widget.state.takeSendOrigin(widget.itemId);
    if (origin == null) return;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final overlay = Overlay.maybeOf(context) != null;
    final flies = !reduceMotion && overlay;
    ChatDiagnostics.current.emit(
      ChatEventLevel.debug,
      ChatEventCategory.media,
      MediaOp.sendOriginFlight,
      correlation: ChatCorrelation(
        chatId: widget.correlation.chatId,
        scrollId: widget.correlation.scrollId,
        clientMessageId: widget.correlation.clientMessageId,
        mediaItemId: widget.itemId.toString(),
      ),
      fields: () => {
        'platform': widget.family,
        'originPresent': true,
        'outcome': flies ? 'flown' : 'skipped',
        'reduceMotion': reduceMotion,
        if (!overlay) 'reason': 'noOverlay',
      },
    );
    if (!flies) return;
    _portalled = true;
    _origin = origin;
    _controller =
        AnimationController(vsync: this, duration: widget.policy.duration)
          ..addStatusListener(_onStatus)
          ..forward();
    _portal.show();
  }

  void _onStatus(AnimationStatus status) {
    if (!status.isCompleted || !mounted) return;
    _portal.hide();
    setState(() => _origin = null);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // The cell's rect now, global; the last one read while the cell is not
  // laid out (its first frame).
  Rect? _target() {
    if (context.findRenderObject() case final RenderBox box
        when box.hasSize && box.attached) {
      _lastTarget = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
    }
    return _lastTarget;
  }

  Widget _overlayChild(BuildContext overlayContext) {
    final controller = _controller;
    final origin = _origin;
    if (controller == null || origin == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: controller,
      builder: (overlayContext, _) {
        final overlay = switch (Overlay.maybeOf(
          context,
        )?.context.findRenderObject()) {
          final RenderBox box when box.hasSize => box,
          _ => null,
        };
        final to = _target() ?? origin;
        final global = widget.policy.rectAt(origin, to, controller.value);
        // The rects are global; the overlay need not sit at the origin.
        return Positioned.fromRect(
          rect: switch (overlay) {
            final box? => global.shift(box.globalToLocal(Offset.zero)),
            null => global,
          },
          child: IgnorePointer(
            child: ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox.fromSize(
                  size: widget.size,
                  child: widget.flying(overlayContext),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_portalled) return widget.child;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _overlayChild,
      // Hidden in place while it flies, kept mounted so its binding holds.
      child: Opacity(opacity: _origin == null ? 1 : 0, child: widget.child),
    );
  }
}
