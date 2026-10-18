import 'dart:typed_data';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regenerate with `flutter test --update-goldens
// test/menu/pointer_menu_golden_test.dart`. The goldens are macOS-generated,
// drawn with the test font (every glyph a square), so they check geometry,
// the hover and disabled states and the reference colours; rounded edges and
// the blurred shadow are anti-aliased, hence the 1% pixel tolerance.
const _size = Size(640, 340);

class _Tolerant extends LocalFileComparator {
  _Tolerant(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= 0.01) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}

List<PointerMenuEntry> _entries() {
  PointerMenuItem item(
    String id,
    String label, {
    String? hint,
    bool enabled = true,
  }) => PointerMenuItem(
    id: id,
    label: label,
    hint: hint,
    enabled: enabled,
    onSelected: () {},
  );
  return [
    item('undo', '&Undo', hint: 'Ctrl+Z'),
    item('redo', '&Redo', hint: 'Ctrl+Y', enabled: false),
    const PointerMenuSeparator(),
    item('cut', 'Cu&t', hint: 'Ctrl+X'),
    item('copy', '&Copy', hint: 'Ctrl+C'),
    item('paste', '&Paste', hint: 'Ctrl+V'),
    item('delete', 'Delete'),
    const PointerMenuSeparator(),
    PointerMenuItem(
      id: 'format',
      label: 'Formatting',
      submenu: [
        item('bold', 'Bold', hint: 'Ctrl+B'),
        item('italic', 'Italic', hint: 'Ctrl+I'),
        item('quote', 'Quote', hint: 'Ctrl+Shift+.', enabled: false),
        const PointerMenuSeparator(),
        item('clear', 'Clear formatting', hint: 'Ctrl+Shift+N'),
      ],
    ),
    const PointerMenuSeparator(),
    item('all', 'Select All', hint: 'Ctrl+A'),
  ];
}

void main() {
  setUpAll(
    () => goldenFileComparator = _Tolerant(
      Uri.file('test/menu/pointer_menu_golden_test.dart'),
    ),
  );

  Future<void> shoot(
    WidgetTester tester, {
    required PointerMenuTokens tokens,
    required Color page,
    required String golden,
    String? hover,
    String? subhover,
    bool submenu = false,
    TextDirection direction = TextDirection.ltr,
  }) async {
    tester.view
      ..physicalSize = _size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: page, body: const SizedBox.expand()),
      ),
    );
    final at = direction == TextDirection.ltr
        ? const Offset(30, 20)
        : Offset(_size.width - 30, 20);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: at);
    PointerMenu.show(
      tester.element(find.byType(Scaffold)),
      globalPosition: at,
      entries: _entries(),
      tokens: tokens,
      motion: const ChromeMotionData(speed: ChromeMotionSpeed.instant),
      textDirection: direction,
    );
    await tester.pump();
    await tester.pump();
    Future<void> glide(String id) async {
      final to = tester.getCenter(find.byKey(PointerMenuRowKey(id)));
      final from = at;
      for (var i = 1; i <= 8; i++) {
        await mouse.moveTo(Offset.lerp(from, to, i / 8)!);
      }
      await tester.pump();
    }

    if (hover != null) await glide(hover);
    if (submenu) {
      await glide('format');
      if (subhover != null) await glide(subhover);
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../goldens/pointer_menu_$golden.png'),
    );
  }

  testWidgets('day: rest, a hovered row, a disabled row, hints', (
    tester,
  ) async {
    await shoot(
      tester,
      tokens: PointerMenuTokens.telegramDay,
      page: const Color(0xFFE6EBEE),
      golden: 'day',
      hover: 'cut',
    );
  });

  testWidgets('day: the Formatting submenu beside its row', (tester) async {
    await shoot(
      tester,
      tokens: PointerMenuTokens.telegramDay,
      page: const Color(0xFFE6EBEE),
      golden: 'day_submenu',
      submenu: true,
    );
  });

  testWidgets('night', (tester) async {
    await shoot(
      tester,
      tokens: PointerMenuTokens.telegramNight,
      page: const Color(0xFF0E1621),
      golden: 'night',
      hover: 'copy',
    );
  });

  testWidgets('right-to-left mirrors the menu and its arrow', (tester) async {
    await shoot(
      tester,
      tokens: PointerMenuTokens.telegramDay,
      page: const Color(0xFFE6EBEE),
      golden: 'rtl',
      direction: TextDirection.rtl,
    );
  });
}
