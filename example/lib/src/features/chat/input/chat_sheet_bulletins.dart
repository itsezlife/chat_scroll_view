import 'package:bulletins/bulletins.dart';
import 'package:chat_scroll_view_example/src/common/utils/mapped_value_listenable.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_bulletins.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

/// The bulletins of one modal sheet: while the sheet is up, a bulletin it
/// raises shows over the sheet, above its bottom bar, not under it on the
/// screen; once the sheet starts closing, bulletins go to the screen again.
///
/// The sheet's layer ([layer], a `PackSheetLayerBuilder`) owns a controller
/// of its own, of the screen's policy. When the sheet starts to close, the
/// bulletin showing over it leaves with its exit (an Undo commits); the
/// controller is disposed with the layer.
final class ChatSheetBulletins {
  /// Bulletins for a sheet over the screen whose bulletins are [screen];
  /// null when the screen shows none, and then the sheet shows none either.
  ChatSheetBulletins(this.screen);

  /// The screen's controller, under the sheet.
  final BulletinController? screen;

  BulletinController? _sheet;

  /// Where a bulletin goes now: over the sheet while it is up, otherwise
  /// the screen's.
  BulletinController? get target => switch (screen) {
    null => null,
    final screen => _sheet ?? screen,
  };

  /// The layer over the sheet that shows its bulletins, keeping clear of
  /// [bottomBar] (the sheet's own bar from the bottom edge).
  Widget layer(
    BuildContext context,
    ValueListenable<double> bottomBar,
    Widget child,
  ) => switch (screen) {
    null => child,
    final screen => _SheetBulletinLayer(
      owner: this,
      policy: screen.policy,
      bottomBar: bottomBar,
      child: child,
    ),
  };
}

class _SheetBulletinLayer extends StatefulWidget {
  const _SheetBulletinLayer({
    required this.owner,
    required this.policy,
    required this.bottomBar,
    required this.child,
  });

  final ChatSheetBulletins owner;
  final BulletinPolicy policy;
  final ValueListenable<double> bottomBar;
  final Widget child;

  @override
  State<_SheetBulletinLayer> createState() => _SheetBulletinLayerState();
}

class _SheetBulletinLayerState extends State<_SheetBulletinLayer> {
  late final BulletinController _controller = BulletinController(
    policy: widget.policy,
  );
  late final BulletinBuilders _builders = ChatBulletins.buildersFor(
    widget.policy,
    overChat: false,
  );
  late final MappedValueListenable<double, EdgeInsets> _obstruction =
      MappedValueListenable(
        source: widget.bottomBar,
        map: (bottom) => EdgeInsets.only(bottom: bottom),
      );
  Animation<double>? _route;

  @override
  void initState() {
    super.initState();
    widget.owner._sheet = _controller;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context)?.animation;
    if (identical(route, _route)) return;
    _route?.removeStatusListener(_onRouteStatus);
    _route = route?..addStatusListener(_onRouteStatus);
  }

  // The sheet closes: what it raises from now on shows on the screen, and
  // the bulletin over it leaves with it.
  void _onRouteStatus(AnimationStatus status) {
    if (status.isForwardOrCompleted) return;
    _release();
    _controller.dismiss();
  }

  void _release() {
    if (identical(widget.owner._sheet, _controller)) widget.owner._sheet = null;
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onRouteStatus);
    _release();
    _obstruction.dispose();
    _controller.dispose();
    super.dispose();
  }

  // The chat's bulletins sit in the screen's `Material`, whose body style
  // their text inherits; a sheet's layer has none above it, so it gets the
  // same one here (without, the text takes the framework's debug style). The
  // card is the chat's: the reference shows the same notice over a sheet as
  // over the screen.
  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ChromeIconScope(
      icons: ChatBulletins.icons,
      child: BulletinHost(
        controller: _controller,
        obstruction: _obstruction,
        builders: _builders,
        child: widget.child,
      ),
    ),
  );
}
