import 'package:attach_model/attach_model.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The thumbnails an open draws, by item, read for their **send origins**
/// when the user sends: the global rect of each item's thumbnail still on
/// screen.
///
/// A surface that draws a thumbnail puts an [AttachSendOrigin] over it,
/// which registers here while it is built. Read at send time, not kept
/// up to date: a thumbnail moves with every scroll, and only its place at
/// the moment of the send matters.
@internal
final class AttachSendOrigins {
  /// No thumbnails.
  AttachSendOrigins();

  final Map<AttachItemId, List<_AttachSendOriginState>> _$thumbnails = {};

  /// The send origins of [items] now: each one's thumbnail rect, for the
  /// items with a thumbnail on screen.
  Map<AttachItemId, Rect> originsOf(Iterable<AttachItem> items) => {
    for (final item in items) item.id: ?_onScreen(item.id),
  };

  Rect? _onScreen(AttachItemId id) {
    for (final thumbnail
        in _$thumbnails[id] ?? const <_AttachSendOriginState>[]) {
      if (thumbnail.onScreenRect() case final rect?) return rect;
    }
    return null;
  }

  void _add(AttachItemId id, _AttachSendOriginState thumbnail) =>
      (_$thumbnails[id] ??= []).add(thumbnail);

  void _remove(AttachItemId id, _AttachSendOriginState thumbnail) {
    final list = _$thumbnails[id];
    if (list == null) return;
    list.remove(thumbnail);
    if (list.isEmpty) _$thumbnails.remove(id);
  }
}

/// Marks [child], laid out over item [id]'s thumbnail, as that thumbnail
/// for [origins].
///
/// The thumbnail's picture is drawn at [scale] of the mark's box, centred,
/// while [scaled] says so (a picked cell's smaller picture). The rect is
/// on screen when it overlaps the scrollable it sits in, or the view when
/// it sits in none: a cell the grid keeps built past its edge has none.
@internal
class AttachSendOrigin extends StatefulWidget {
  /// The mark of item [id]'s thumbnail.
  const AttachSendOrigin({
    required this.id,
    required this.origins,
    required this.child,
    this.scale = 1,
    this.scaled,
    super.key,
  });

  /// The item the thumbnail shows.
  final AttachItemId id;

  /// Where the mark registers.
  final AttachSendOrigins origins;

  /// The scale the picture is drawn at while [scaled] answers true.
  final double scale;

  /// Whether the picture is drawn at [scale] now; null for never.
  final bool Function()? scaled;

  /// What is drawn over the thumbnail.
  final Widget child;

  @override
  State<AttachSendOrigin> createState() => _AttachSendOriginState();
}

class _AttachSendOriginState extends State<AttachSendOrigin> {
  @override
  void initState() {
    super.initState();
    widget.origins._add(widget.id, this);
  }

  @override
  void didUpdateWidget(AttachSendOrigin oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id == widget.id &&
        identical(oldWidget.origins, widget.origins)) {
      return;
    }
    oldWidget.origins._remove(oldWidget.id, this);
    widget.origins._add(widget.id, this);
  }

  @override
  void dispose() {
    widget.origins._remove(widget.id, this);
    super.dispose();
  }

  /// The thumbnail's global rect, or null when it is not laid out or not
  /// on screen.
  Rect? onScreenRect() {
    if (!mounted) return null;
    var rect = switch (context.findRenderObject()) {
      final RenderBox box when box.attached && box.hasSize =>
        box.localToGlobal(Offset.zero) & box.size,
      _ => null,
    };
    if (rect == null) return null;
    if (widget.scaled?.call() ?? false) {
      rect = Rect.fromCenter(
        center: rect.center,
        width: rect.width * widget.scale,
        height: rect.height * widget.scale,
      );
    }
    final area = switch (Scrollable.maybeOf(
      context,
    )?.context.findRenderObject()) {
      final RenderBox viewport when viewport.attached && viewport.hasSize =>
        viewport.localToGlobal(Offset.zero) & viewport.size,
      _ => Offset.zero & MediaQuery.sizeOf(context),
    };
    return rect.overlaps(area) ? rect : null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
