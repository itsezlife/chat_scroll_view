import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Hands a bottom pack sheet's drag owner to the sheet's body: the grid
/// passes [sink] to its viewport, and the header band drives the same sink.
///
/// The owner is the bottom sheet's ([ChromeSheetDrag]): a pull from the grid
/// past its top and a pull on the header band are one pull, closed by one
/// rule. Rising with the grid is not the owner's: that is the grid's own
/// scroll, which the card follows.
///
/// Absent in the box under a pointer, which no drag moves.
class PackSheetDragScope extends InheritedWidget {
  /// Puts [sink] above [child].
  const PackSheetDragScope({
    required this.sink,
    required super.child,
    super.key,
  });

  /// The owner's sink.
  final CatalogOverscrollSink sink;

  /// The nearest owner's sink, or null where no drag moves the sheet.
  static CatalogOverscrollSink? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PackSheetDragScope>()?.sink;

  @override
  bool updateShouldNotify(PackSheetDragScope oldWidget) =>
      !identical(sink, oldWidget.sink);
}

/// Feeds the nearest [ChromeSheetDrag]'s sink to the grid's overscroll as a
/// [PackSheetDragScope]; [child] alone where no drag moves the sheet.
class PackSheetDragBridge extends StatefulWidget {
  /// A bridge above [child].
  const PackSheetDragBridge({required this.child, super.key});

  /// The sheet's body.
  final Widget child;

  @override
  State<PackSheetDragBridge> createState() => _PackSheetDragBridgeState();
}

class _PackSheetDragBridgeState extends State<PackSheetDragBridge> {
  ChromeSheetDragSink? _owner;
  CatalogOverscrollSink? _sink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = ChromeSheetDrag.maybeOf(context);
    if (identical(owner, _owner)) return;
    _owner = owner;
    _sink = switch (owner) {
      final owner? => CatalogOverscrollSink(
        onStart: owner.start,
        onDelta: owner.take,
        onEnd: owner.release,
      ),
      null => null,
    };
  }

  @override
  Widget build(BuildContext context) => switch (_sink) {
    final sink? => PackSheetDragScope(sink: sink, child: widget.child),
    null => widget.child,
  };
}
