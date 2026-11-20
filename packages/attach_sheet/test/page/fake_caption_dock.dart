import 'package:attach_sheet/attach_sheet.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A dock that stands in for the host's composer stack: a place of a fixed
/// height under the bar, a panel it says is up or not, and the calls it got.
final class FakeCaptionDock implements AttachCaptionDock {
  final _changes = ChangeNotifier();
  final pad = ValueNotifier<double>(0);
  double place = 0;
  bool up = false;
  bool takesBack = false;
  final calls = <String>[];
  bool disposed = false;

  void show({required bool panel}) {
    up = panel;
    _changes.notifyListeners();
  }

  @override
  Listenable get changes => _changes;

  @override
  bool get panelUp => up;

  @override
  void togglePanel() {
    calls.add('toggle');
    show(panel: !up);
  }

  @override
  void onFieldTap() => calls.add('tap');

  @override
  void onFieldPointerDown() => calls.add('down');

  @override
  void onFieldPointerEnd() => calls.add('end');

  @override
  ValueListenable<double> get fieldBottomPad => pad;

  @override
  Widget buildPlace(BuildContext context) => ListenableBuilder(
    listenable: _changes,
    builder: (context, _) =>
        SizedBox(key: const ValueKey('fake-dock-place'), height: place),
  );

  @override
  bool handleBack() {
    calls.add('back');
    if (!takesBack) return false;
    takesBack = false;
    show(panel: false);
    return true;
  }

  @override
  void closePanel() {
    calls.add('close');
    show(panel: false);
  }

  @override
  void dispose() {
    disposed = true;
    _changes.dispose();
    pad.dispose();
  }
}

/// A host whose caption has a dock.
final class DockHost extends AttachSheetHost {
  /// Every dock asked for, in order (the sheet's, then a viewer's).
  final docks = <FakeCaptionDock>[];

  /// The sheet's dock.
  FakeCaptionDock get sheetDock => docks.first;

  FakeCaptionDock get dock => docks.single;

  @override
  AttachCaptionDock? createCaptionDock(ComposerController caption) {
    final dock = FakeCaptionDock();
    docks.add(dock);
    return dock;
  }
}
