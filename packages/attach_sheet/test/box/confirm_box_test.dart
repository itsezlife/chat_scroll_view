import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' as content;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';

IntakeFile _photo(String name) => IntakeFile(
  source: IntakeSource.path('/p/$name'),
  name: name,
  size: 900,
  mimeType: 'image/jpeg',
);
IntakeFile _video(String name) => IntakeFile(
  source: IntakeSource.path('/v/$name'),
  name: name,
  size: 900,
  mimeType: 'video/mp4',
);
IntakeFile _doc(String name) => IntakeFile(
  source: IntakeSource.path('/d/$name'),
  name: name,
  size: 900,
  mimeType: 'application/pdf',
);

final class _Rig {
  _Rig(this.tester, this.box);

  final WidgetTester tester;
  final ConfirmBoxController box;
  AttachOutcome? outcome;

  String get title => tester
      .widget<Text>(find.byKey(const ValueKey('confirm-box-title')))
      .data!;

  static Future<_Rig> open(
    WidgetTester tester, {
    AttachSheetPolicy policy = const AttachSheetPolicy.desktop(),
    AttachPolicy attachPolicy = const AttachPolicy.desktop(),
    AttachLimits limits = const AttachLimits(),
    List<IntakeFile> files = const [],
    FileIntake? intake,
    SendOptionStore? store,
    content.RichText caption = content.RichText.empty,
    GroupPreviewBuilder? groupPreview,
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final box = ConfirmBoxController(
      policy: policy,
      selection: AttachSelection(policy: attachPolicy, limits: limits),
      intake: intake ?? FakeFileIntake(),
      store: store,
      initialCaption: caption,
    )..addFiles(files);
    addTearDown(box.dispose);
    final rig = _Rig(tester, box);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ChromeThemeScope(
          palette: const ChromePalette.light(),
          child: ChromeStringsScope(
            strings: ChromeStringsPresets.english,
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) => Center(
            child: GestureDetector(
              key: const ValueKey('open'),
              behavior: HitTestBehavior.opaque,
              onTap: () async => rig.outcome = await ConfirmBox.show(
                context,
                controller: box,
                groupPreview: groupPreview,
              ),
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    return rig;
  }
}

void main() {
  group('titles', () {
    testWidgets('desktop', (tester) async {
      final rig = await _Rig.open(tester, files: [_photo('a.jpg')]);
      expect(rig.title, 'Send photo');
      rig.box.addFiles([_photo('b.jpg'), _photo('c.jpg')]);
      await tester.pump();
      expect(rig.title, '3 photos selected');
      rig.box.addFiles([_doc('d.pdf')]);
      await tester.pump();
      expect(rig.title, '4 files selected');
    });

    testWidgets('web', (tester) async {
      final rig = await _Rig.open(
        tester,
        policy: const AttachSheetPolicy.web(),
        attachPolicy: const AttachPolicy.web(),
        files: [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')],
      );
      expect(rig.title, 'Send 3 Photos');
      rig.box.addFiles([_video('v.mp4')]);
      await tester.pump();
      expect(rig.title, 'Send 4 Files');
    });
  });

  group('blocks', () {
    testWidgets('a media group goes to the host layout, files to rows', (
      tester,
    ) async {
      final groups = <List<AttachItem>>[];
      await _Rig.open(
        tester,
        files: [_photo('a.jpg'), _video('b.mp4'), _doc('c.pdf')],
        groupPreview: (context, items, width) {
          groups.add(items);
          expect(width, 308);
          return const SizedBox(key: ValueKey('mosaic'), height: 100);
        },
      );
      expect(find.byKey(const ValueKey('mosaic')), findsOneWidget);
      expect(groups.last.map((i) => i.facts.name), ['a.jpg', 'b.mp4']);
      expect(
        find.byKey(const ValueKey('confirm-box-row-file:/d/c.pdf')),
        findsOneWidget,
      );
    });

    testWidgets('without a layout, a strip of thumbs', (tester) async {
      await _Rig.open(tester, files: [_photo('a.jpg'), _photo('b.jpg')]);
      expect(find.byKey(const ValueKey('confirm-box-strip')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('confirm-box'))).width,
        364,
      );
    });
  });

  group('desktop options', () {
    testWidgets('Group items needs two; Remember shows after a change', (
      tester,
    ) async {
      final rig = await _Rig.open(tester, files: [_photo('a.jpg')]);
      expect(find.byKey(const ValueKey('confirm-box-group')), findsNothing);
      expect(
        find.byKey(const ValueKey('confirm-box-as-documents')),
        findsOneWidget,
      );
      rig.box.addFiles([_photo('b.jpg')]);
      await tester.pump();
      expect(find.byKey(const ValueKey('confirm-box-group')), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm-box-remember')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('confirm-box-group')));
      await tester.pump();
      expect(rig.box.panel.options.value.grouped, isFalse);
      expect(
        find.byKey(const ValueKey('confirm-box-remember')),
        findsOneWidget,
      );
    });

    testWidgets('Remember keeps the choice app-wide; without it nothing', (
      tester,
    ) async {
      final storage = FakeKeyValueStore();
      final store = SendOptionStore(
        storage,
        policy: const AttachPolicy.desktop(),
      );
      final rig = await _Rig.open(
        tester,
        store: store,
        files: [_photo('a.jpg'), _photo('b.jpg')],
      );
      await tester.tap(find.byKey(const ValueKey('confirm-box-group')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-box-remember')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('attach-send')));
      await tester.pumpAndSettle();
      expect(rig.outcome, isA<AttachOutcome$Send>());
      expect(
        storage.entries['attach_model:grouped'],
        const content.StoredValue('false', version: 1),
      );
    });

    testWidgets('a choice the rights forbid reverts', (tester) async {
      final rig = await _Rig.open(
        tester,
        limits: const AttachLimits(sendAsFileAllowed: false),
        files: [_photo('a.jpg')],
      );
      rig.box.asFiles = true;
      expect(rig.box.panel.options.value.asFiles, isFalse);
    });
  });

  testWidgets('dragging a thumb reorders the selection', (tester) async {
    final rig = await _Rig.open(
      tester,
      files: [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')],
    );
    final first = find.byKey(const ValueKey('confirm-box-thumb-file:/p/a.jpg'));
    final width = tester.getSize(first).width;
    await tester.drag(first, Offset(width * 2 + 10, 0));
    await tester.pumpAndSettle();
    expect(rig.box.selection.items.map((i) => i.facts.name), [
      'b.jpg',
      'c.jpg',
      'a.jpg',
    ]);
  });

  testWidgets('delete removes an item; the last one closes with the caption', (
    tester,
  ) async {
    final rig = await _Rig.open(
      tester,
      caption: const content.RichText.plain('draft'),
      files: [_doc('a.pdf'), _doc('b.pdf')],
    );
    await tester.tap(
      find.byKey(const ValueKey('confirm-box-delete-file:/d/a.pdf')),
    );
    await tester.pumpAndSettle();
    expect(rig.box.selection.length, 1);
    await tester.tap(
      find.byKey(const ValueKey('confirm-box-delete-file:/d/b.pdf')),
    );
    await tester.pumpAndSettle();
    expect(
      rig.outcome,
      const AttachOutcome.cancelled(content.RichText.plain('draft')),
    );
  });

  group('keys', () {
    testWidgets('Enter sends', (tester) async {
      final rig = await _Rig.open(tester, files: [_photo('a.jpg')]);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(rig.outcome, isA<AttachOutcome$Send>());
    });

    testWidgets('Escape cancels and returns the caption', (tester) async {
      final rig = await _Rig.open(
        tester,
        caption: const content.RichText.plain('hi'),
        files: [_photo('a.jpg')],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        rig.outcome,
        const AttachOutcome.cancelled(content.RichText.plain('hi')),
      );
    });

    testWidgets('Enter does nothing while an input method composes', (
      tester,
    ) async {
      final rig = await _Rig.open(tester, files: [_photo('a.jpg')]);
      rig.box.panel.caption.text.value = const TextEditingValue(
        text: 'ni',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(rig.outcome, isNull);
    });

    testWidgets('Ctrl+O adds from the file dialog', (tester) async {
      final intake = FakeFileIntake()..enqueuePick([_doc('more.pdf')]);
      final rig = await _Rig.open(
        tester,
        intake: intake,
        files: [_photo('a.jpg')],
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(rig.box.selection.length, 2);
    });
  });

  group('adding', () {
    testWidgets('every route adds to the open box', (tester) async {
      final rig = await _Rig.open(tester, files: [_photo('a.jpg')]);
      await rig.box.paste(FakeClipboardReader([_photo('pasted.png')]));
      await tester.pump();
      expect(rig.box.selection.length, 2);
      expect(rig.box.isOpen, isTrue);
    });

    testWidgets('the web skips an item already in the box', (tester) async {
      final rig = await _Rig.open(
        tester,
        policy: const AttachSheetPolicy.web(),
        attachPolicy: const AttachPolicy.web(),
        files: [_photo('a.jpg')],
      );
      rig.box.addFiles([
        const IntakeFile(
          source: IntakeSource.blob('other handle'),
          name: 'a.jpg',
          size: 900,
          mimeType: 'image/jpeg',
        ),
      ]);
      expect(rig.box.selection.length, 1);
    });

    testWidgets('150 items are taken, and plan into 15 groups', (tester) async {
      final rig = await _Rig.open(
        tester,
        files: [for (var i = 0; i < 150; i++) _photo('$i.jpg')],
      );
      expect(rig.box.selection.length, 150);
      final plan = planSend(
        SendRequest(
          items: rig.box.selection.items,
          caption: content.RichText.empty,
        ),
        const AttachPolicy.desktop(),
        const AttachLimits(),
      );
      expect((plan as SendPlan$Ready).sends, hasLength(15));
    });
  });

  group('drop overlay', () {
    Future<(FakeDropSource, List<(List<IntakeFile>, bool?)>)> overlay(
      WidgetTester tester, {
      bool open = false,
    }) async {
      final source = FakeDropSource();
      addTearDown(source.close);
      final drops = <(List<IntakeFile>, bool?)>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ChromeThemeScope(
            palette: const ChromePalette.light(),
            child: ChromeStringsScope(
              strings: ChromeStringsPresets.english,
              child: AttachDropOverlay(
                source: source,
                policy: const AttachSheetPolicy.desktop(),
                boxOpen: ValueNotifier(open),
                onDrop: (files, {required asFiles}) =>
                    drops.add((files, asFiles)),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      return (source, drops);
    }

    testWidgets('two zones while files are over it; the one under the drop decides', (
      tester,
    ) async {
      final (source, drops) = await overlay(tester);
      expect(find.byKey(const ValueKey('attach-drop-files')), findsNothing);
      source.add(const DropEnter(DropOffer(types: ['Files'])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-drop-files')), findsOneWidget);
      expect(find.byKey(const ValueKey('attach-drop-media')), findsOneWidget);

      // The bottom zone: as media.
      source.drop([_photo('a.jpg')], at: const Offset(10, 500));
      await tester.pumpAndSettle();
      expect(drops.single.$2, isFalse);
      expect(find.byKey(const ValueKey('attach-drop-files')), findsNothing);

      // The top zone: as files, whatever the files are.
      source.drop([_photo('b.jpg')], at: const Offset(10, 50));
      await tester.pumpAndSettle();
      expect(drops.last.$2, isTrue);
    });

    testWidgets('over an open box, one Add items zone', (tester) async {
      final (source, drops) = await overlay(tester, open: true);
      source.add(const DropEnter(DropOffer(types: ['Files'])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-drop-add')), findsOneWidget);
      source.drop([_photo('a.jpg')]);
      await tester.pumpAndSettle();
      expect(drops.single.$2, isNull);
    });
  });

  test('desktop and web families', () {
    expect(
      AttachSheetPolicy.forPlatform(TargetPlatform.macOS, isWeb: false),
      isA<AttachSheetPolicy$Desktop>(),
    );
    expect(
      AttachSheetPolicy.forPlatform(TargetPlatform.android, isWeb: true),
      isA<AttachSheetPolicy$Web>(),
    );
    final web = const AttachSheetPolicy.web().confirmBox!;
    expect(
      (web.width, web.radius, web.previewWidth, web.dimOpacity),
      (420.0, 40.0, 384.0, 0.3),
    );
    final desktop = const AttachSheetPolicy.desktop().confirmBox!;
    expect(
      (desktop.width, desktop.previewWidth, desktop.maxHeight),
      (364.0, 308.0, 1280.0),
    );
    expect(desktop.dismissesOnOutsideTap, isFalse);
  });
}
