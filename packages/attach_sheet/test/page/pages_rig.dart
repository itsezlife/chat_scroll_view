import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' as content;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page of rows whose builds and scopes the test can see.
AttachPage rowsPage(
  String id, {
  String? label,
  AttachPageKind kind = AttachPageKind.selection,
  AttachPagePermission? permission,
  void Function(AttachPageScope scope)? onScope,
  List<String>? builds,
  ValueListenable<bool>? locked,
}) => AttachPage(
  id: AttachPageId(id),
  label: label ?? id,
  icon: const SizedBox(width: 24, height: 24),
  kind: kind,
  permission: permission,
  builder: (context, scope) {
    builds?.add(id);
    onScope?.call(scope);
    Widget list({required bool locked}) => ListView.builder(
      controller: scope.scrollController,
      // Locked, the page's own gesture holds the scroll (a swipe
      // selection), as the grid's does.
      physics: locked ? const NeverScrollableScrollPhysics() : null,
      itemCount: 60,
      itemBuilder: (context, i) =>
          SizedBox(key: ValueKey('$id-row-$i'), height: 50),
    );
    return switch (locked) {
      final locked? => ValueListenableBuilder<bool>(
        valueListenable: locked,
        builder: (context, value, _) => list(locked: value),
      ),
      null => list(locked: false),
    };
  },
);

/// An app with one button that opens the paged sheet.
final class PagesRig {
  PagesRig._(this.tester, this.selection);

  final WidgetTester tester;
  final AttachSelection selection;
  AttachOutcome? outcome;

  static Future<PagesRig> open(
    WidgetTester tester, {
    required AttachSheetPolicy policy,
    required List<AttachPage> pages,
    AttachPageId? initial,
    Size size = const Size(400, 800),
    bool settle = true,
    AttachSheetHost host = const AttachSheetHost(),
    AttachPolicy attachPolicy = const AttachPolicy.android(),
    AttachLimits limits = const AttachLimits(),
    content.RichText initialCaption = content.RichText.empty,
    SendOptionStore? optionStore,
    Widget Function(Widget app)? wrap,
    bool viewBottomPadding = false,
    AttachCapabilities? capabilities,
  }) async {
    tester.view
      ..physicalSize = size * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final selection = AttachSelection(policy: attachPolicy, limits: limits);
    final rig = PagesRig._(tester, selection);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            // With [viewBottomPadding] the view's bottom padding stays, as
            // on a device with a gesture bar.
            padding: EdgeInsets.only(
              top: 24,
              bottom: viewBottomPadding
                  ? MediaQuery.paddingOf(context).bottom
                  : 0,
            ),
          ),
          child: ChromeThemeScope(
            palette: const ChromePalette.light(),
            child: ChromeStringsScope(
              strings: ChromeStringsPresets.english,
              child: wrap == null ? child! : wrap(child!),
            ),
          ),
        ),
        home: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              key: const ValueKey('open'),
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                rig.outcome = await AttachSheet.show(
                  context,
                  policy: policy,
                  selection: selection,
                  pages: AttachPageRegistry(pages, initial: initial),
                  host: host,
                  initialCaption: initialCaption,
                  optionStore: optionStore,
                  capabilities: capabilities,
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

  Finder tab(String id) => find.byKey(ValueKey('attach-tab-$id'));

  Future<void> tapTab(String id) async {
    await tester.tap(tab(id));
    await tester.pumpAndSettle();
  }

  double get top =>
      tester.getTopLeft(find.byKey(const ValueKey('attach-sheet'))).dy;

  bool shows(String id) => find
      .byKey(ValueKey('$id-row-0'), skipOffstage: true)
      .evaluate()
      .isNotEmpty;
}
