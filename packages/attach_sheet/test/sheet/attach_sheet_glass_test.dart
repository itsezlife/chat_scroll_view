/// The sheet's glass samples the sheet: the sheet's background and page are
/// the glass source, the bars over it sample it, and no glass samples the
/// source it is in.
///
/// **Seams:** the paged sheet ([PagesRig]) on a backend that can capture,
/// read through the glass widgets and the composited layers.
library;

import 'dart:async';

import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../page/pages_rig.dart';

Widget _capturing(Widget app) =>
    GlassQualityScope(capabilities: GlassCapabilities.all, child: app);

/// A host that keeps the sheet's glass on the scene filter.
final class _FilterHost extends AttachSheetHost {
  const _FilterHost();

  @override
  bool get samplesGlass => false;
}

bool _samples(Finder glass) => find
    .descendant(
      of: glass,
      matching: find.byWidgetPredicate(
        (w) => '${w.runtimeType}' == 'SampledGlassBackdrop',
      ),
    )
    .evaluate()
    .isNotEmpty;

bool _filters(Finder glass) => find
    .descendant(of: glass, matching: find.byType(BackdropFilter))
    .evaluate()
    .isNotEmpty;

/// Every sampled glass inside the very source it samples.
List<Element> _selfSampling(WidgetTester tester) => [
  for (final element
      in find
          .byWidgetPredicate(
            (w) => '${w.runtimeType}' == 'SampledGlassBackdrop',
          )
          .evaluate())
    // The backdrop's link is not exported; its source is a render object.
    // ignore: avoid_dynamic_calls
    if ((element.widget as dynamic).link.source case final RenderObject source
        when _isAncestor(source, element.renderObject!))
      element,
];

bool _isAncestor(RenderObject ancestor, RenderObject node) {
  for (var r = node.parent; r != null; r = r.parent) {
    if (identical(r, ancestor)) return true;
  }
  return false;
}

/// The opacity layers above [layer] that are not opaque.
bool _fadedFilter(Layer layer) {
  for (Layer? l = layer.parent; l != null; l = l.parent) {
    if (l is OpacityLayer && (l.alpha ?? 255) < 255) return true;
  }
  return false;
}

void main() {
  const android = AttachSheetPolicy.android();
  final tabBar = find.byKey(const ValueKey('attach-tab-bar-glass'));

  testWidgets('the tab bar samples the sheet', (tester) async {
    await PagesRig.open(
      tester,
      policy: android,
      wrap: _capturing,
      pages: [rowsPage('gallery'), rowsPage('files')],
    );
    expect(_samples(tabBar), isTrue);
    expect(_filters(tabBar), isFalse);
    expect(_selfSampling(tester), isEmpty);
  });

  testWidgets('the caption island samples as the panel reveals, with no '
      'filter under a fade anywhere in the sheet', (tester) async {
    final rig = await PagesRig.open(
      tester,
      policy: android,
      wrap: _capturing,
      pages: [rowsPage('gallery'), rowsPage('files')],
    );
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final filter in tester.layers.whereType<BackdropFilterLayer>()) {
        expect(_fadedFilter(filter), isFalse, reason: 'frame $i');
      }
    }
    await tester.pumpAndSettle();
    expect(_samples(find.byKey(const ValueKey('attach-caption'))), isTrue);
    expect(_selfSampling(tester), isEmpty);
  });

  testWidgets('the sheet rises to its top and back with no error', (
    tester,
  ) async {
    late AttachPageScope gallery;
    await PagesRig.open(
      tester,
      policy: android,
      wrap: _capturing,
      pages: [
        rowsPage('gallery', onScope: (s) => gallery = s),
        rowsPage('files'),
      ],
    );
    gallery.requestExpansion();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    final sheet = AttachSheetController.of(
      tester.element(find.byKey(const ValueKey('gallery-row-0'))),
    );
    unawaited(sheet.collapse());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_samples(tabBar), isTrue);
  });

  testWidgets('a host can keep the scene filter', (tester) async {
    await PagesRig.open(
      tester,
      policy: android,
      wrap: _capturing,
      host: const _FilterHost(),
      pages: [rowsPage('gallery'), rowsPage('files')],
    );
    expect(_samples(tabBar), isFalse);
    expect(_filters(tabBar), isTrue);
  });
}
