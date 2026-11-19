import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A host that records what the sheet tells it.
final class RecordingHost extends AttachSheetHost {
  final List<String> calls = [];

  @override
  void opened(AttachSheetOpening opening) => calls.add('opened');

  @override
  void closed(AttachSheetOpening opening) => calls.add('closed');

  @override
  void restoreKeyboard() => calls.add('restoreKeyboard');
}

/// An app with one button that opens a sheet over a list of rows.
final class SheetRig {
  SheetRig._(this.tester, this.selection);

  final WidgetTester tester;
  final AttachSelection selection;
  AttachOutcome? outcome;
  bool get closed => outcome != null;

  static Future<SheetRig> open(
    WidgetTester tester, {
    required AttachSheetPolicy policy,
    Size size = const Size(400, 800),
    EdgeInsets padding = const EdgeInsets.only(top: 24),
    EdgeInsets viewInsets = EdgeInsets.zero,
    double devicePixelRatio = 3,
    AttachSheetHost host = const AttachSheetHost(),
    AttachSheetOpening opening = const AttachSheetOpening(),
    Widget? header,
    Widget? bottomBar,
    int rows = 60,
    bool settle = true,
    ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
  }) async {
    tester.view
      ..physicalSize = size * devicePixelRatio
      ..devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    final selection = AttachSelection(
      policy: const AttachPolicy.android(),
      limits: const AttachLimits(),
    );
    final rig = SheetRig._(tester, selection);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(padding: padding, viewInsets: viewInsets),
          child: ChromeMotionScope(
            speed: speed,
            child: ChromeThemeScope(
              palette: const ChromePalette.light(),
              child: ChromeStringsScope(
                strings: ChromeStringsPresets.english,
                child: child!,
              ),
            ),
          ),
        ),
        home: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              key: const ValueKey('open'),
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                rig.outcome = await AttachSheet.showContent(
                  context,
                  policy: policy,
                  selection: selection,
                  host: host,
                  opening: opening,
                  header: header,
                  bottomBar: bottomBar,
                  builder: (context, controller) => ListView.builder(
                    controller: controller,
                    itemCount: rows,
                    itemBuilder: (context, i) =>
                        SizedBox(key: ValueKey('row-$i'), height: 50),
                  ),
                );
              },
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
    return rig;
  }

  /// The sheet's top edge.
  double get top =>
      tester.getTopLeft(find.byKey(const ValueKey('attach-sheet'))).dy;

  /// The scrim's opacity.
  double get dim {
    final box = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byKey(const ValueKey('attach-sheet-scrim')),
        matching: find.byType(ColoredBox),
      ),
    );
    return box.color.a;
  }

  /// The controller of the open sheet.
  AttachSheetController get controller => AttachSheetController.of(
    tester.element(find.byKey(const ValueKey('attach-sheet'))),
  );

  /// Drags the list by [dy] from a row near the sheet's top.
  Future<void> drag(double dy) => tester.drag(
    find.byKey(const ValueKey('row-1')),
    Offset(0, dy),
    warnIfMissed: false,
  );

  /// Flings the list by [dy] at [speed] logical px/s.
  Future<void> fling(double dy, double speed) => tester.fling(
    find.byKey(const ValueKey('row-1')),
    Offset(0, dy),
    speed,
    warnIfMissed: false,
  );

  /// Taps the scrim above the sheet.
  Future<void> tapAbove() => tester.tapAt(const Offset(200, 60));

  /// The scroll offset of the page.
  double get scrolled =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
}
