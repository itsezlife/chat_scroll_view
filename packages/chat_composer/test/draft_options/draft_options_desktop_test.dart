/// The desktop presentation of the draft options: a modal box editing a copy
/// until Save, driven by mouse and keyboard.
///
/// **Seams:** the pure-Dart `DraftOptionsPolicy$Desktop.box` and
/// `DraftLinkPagePolicy.desktop` values; `DraftOptionsController` opened on
/// a desktop policy under the composer's scopes, with a
/// `RecordingDraftOptionsHost`, a `FakeDraftBubbleBuilder` and
/// `RecordingDiagnostics` installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _other = Uri.parse('https://docs.example/guide');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));
final _loaded = LinkPreviewState.loaded(
  LinkPreview(url: _url, siteName: 'Example News', title: 'A story'),
);

void main() {
  late RecordingDiagnostics diagnostics;
  late RecordingDraftOptionsHost host;
  late FakeDraftBubbleBuilder bubble;
  late ManualComposerClock clock;
  final strings = ChromeStringsPresets.english.composer.draftOptions;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    host = RecordingDraftOptionsHost();
    bubble = FakeDraftBubbleBuilder();
    clock = ManualComposerClock(DateTime(2026, 11, 28));
  });

  /// Opens a desktop overlay over a stand-in composer field that holds
  /// focus; returns the controller and the field's composer.
  Future<(DraftOptionsController, ComposerController)> openBox(
    WidgetTester tester, {
    DraftOptionsPolicy policy = const DraftOptionsPolicy.desktop(),
    List<Uri>? links,
    ChromeMotionSpeed? motionSpeed,
    bool settle = true,
  }) async {
    final composer = ComposerController();
    addTearDown(composer.dispose);
    final controller = DraftOptionsController(
      policy: policy,
      host: host,
      bubbleBuilder: bubble.call,
      composer: composer,
      clock: clock,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
    );
    addTearDown(controller.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      composerHarness(
        Builder(
          builder: (c) {
            context = c;
            return Focus(
              focusNode: composer.focusNode,
              child: const SizedBox(height: 40),
            );
          },
        ),
        motionSpeed: motionSpeed,
      ),
    );
    composer.requestFocus();
    await tester.pump();
    controller.open(
      context,
      value: _initial,
      page: _loaded,
      text: const model.RichText.plain('Read this'),
      links: links ?? [_url],
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    clock.advance(DraftOptionsController.openGuard);
    return (controller, composer);
  }

  Finder button(String label) => find.descendant(
    of: find.byKey(DraftOptionsBox.buttonsKey),
    matching: find.text(label),
  );

  double boxOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find
            .ancestor(
              of: find.byKey(DraftOptionsBox.boxKey),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;

  /// The label of the focused row or button.
  String? focused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    if (context.findAncestorWidgetOfExactType<DraftLinkRowView>()
        case final row?) {
      return row.label;
    }
    return context
        .findAncestorWidgetOfExactType<DraftOptionsBoxButton>()
        ?.label;
  }

  group('policy', () {
    test('the box: 364 wide, radius 8, a 16 semibold title 48 tall at 24 / '
        '13, Save and Cancel 34 tall, 14 semibold, radius 4, 15 inside, in '
        'a 6 / 10 band; fades in and out over 200 ms ease-out-circ; an '
        'option change is instant; links take the click cursor', () {
      final box = const DraftOptionsPolicy$Desktop().box;

      expect(box.width, 364);
      expect(box.radius, 8);
      expect(box.titleHeight, 48);
      expect(box.titleStart, 24);
      expect(box.titleTop, 13);
      expect(box.titleFontSize, 16);
      expect(box.titleWeight, FontWeight.w600);
      expect(box.buttonHeight, 34);
      expect(box.buttonFontSize, 14);
      expect(box.buttonWeight, FontWeight.w600);
      expect(box.buttonRadius, 4);
      expect(box.buttonPadding, 15);
      expect(box.buttonGap, 6);
      expect(box.buttonBandPadding, 10);
      expect(box.windowInset, 16);
      expect(box.fadeIn.duration, const Duration(milliseconds: 200));
      expect(box.fadeIn.curve, isA<EaseOutCirc>());
      expect(box.fadeOut.duration, const Duration(milliseconds: 200));
      expect(box.fadeOut.curve, isA<EaseOutCirc>());
      expect(box.optionChange.duration, Duration.zero);
      expect(box.linkCursor, SystemMouseCursors.click);
    });

    test('a host may override the box', () {
      final policy = DraftOptionsPolicy.desktop(
        box: DraftOptionsDesktopBox.standard.copyWith(width: 420),
      );

      expect((policy as DraftOptionsPolicy$Desktop).box.width, 420);
      expect(policy.box.radius, 8);
    });

    test('the rows: 40 tall, icon 24 at 20, label at 60, 14 text, 82 '
        'beyond the widest label; the 4 skip in the box colour; the hint '
        'under a skip, 22 / 8 / 22 / 16, at the start; rows take keyboard '
        'focus', () {
      final page = const DraftOptionsPolicy$Desktop().linkPage;

      expect(
        page.rowMetrics,
        const DraftLinkRowMetrics(
          height: 40,
          iconSize: 24,
          iconStart: 20,
          labelStart: 60,
          fontSize: 14,
          minWidthBeyondLabel: 82,
        ),
      );
      expect(page.separatorExtent, 4);
      expect(page.separatorOpacity, 0);
      expect(
        page.linkHintPadding,
        const EdgeInsetsDirectional.fromSTEB(22, 8, 22, 16),
      );
      expect(page.linkHintAlign, TextAlign.start);
      expect(page.keyboardFocus, isTrue);
      expect(page.iconMorph, isFalse);
    });

    test('mobile rows take no keyboard focus and keep the centred hint', () {
      expect(DraftLinkPagePolicy.android.keyboardFocus, isFalse);
      expect(DraftLinkPagePolicy.ios.keyboardFocus, isFalse);
      expect(DraftLinkPagePolicy.android.linkHintPadding, isNull);
      expect(DraftLinkPagePolicy.android.linkHintAlign, TextAlign.center);
      expect(DraftLinkPagePolicy.android.iconMorph, isTrue);
      expect(DraftLinkPagePolicy.ios.iconMorph, isTrue);
    });
  });

  group('the box', () {
    testWidgets('a box 364 wide with radius 8: the title, the preview, the '
        'rows pinned under it and Save after Cancel', (tester) async {
      await openBox(tester);

      final box = find.byKey(DraftOptionsBox.boxKey);
      expect(tester.getSize(box).width, 364);
      final decoration =
          tester.widget<DecoratedBox>(box).decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(8));

      final title = tester.getRect(find.text(strings.linkTitle));
      final preview = tester.getRect(
        find.byKey(FakeDraftBubbleBuilder.bubbleKey),
      );
      final rows = tester.getRect(find.byType(DraftLinkRows));
      final save = tester.getRect(
        find.ancestor(
          of: button(strings.save),
          matching: find.byType(DraftOptionsBoxButton),
        ),
      );
      final cancel = tester.getRect(button(strings.cancel));
      final boxRect = tester.getRect(box);
      expect(title.left - boxRect.left, 24);
      expect(title.top - boxRect.top, 13);
      expect(title.bottom, lessThanOrEqualTo(preview.top));
      expect(preview.bottom, lessThanOrEqualTo(rows.top));
      expect(rows.bottom, lessThanOrEqualTo(save.top));
      expect(cancel.right, lessThan(save.left));
      expect(boxRect.right - save.right, 10);
      expect(boxRect.bottom - save.bottom, 10);
      expect(save.height, 34);
      expectChromeText(tester, within: find.byType(DraftOptionsOverlay));
    });

    testWidgets('Save reports the copy once and closes', (tester) async {
      final (controller, _) = await openBox(tester);
      final above = _initial.copyWith(invertMedia: true);
      controller.session!.edit(above, field: DraftOptionsField.position);
      expect(host.edits, isEmpty);

      await tester.tap(button(strings.save));
      await tester.pump();
      await tester.tap(button(strings.save), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(controller.isOpen, isFalse);
      expect(host.edits, [above]);
      expect(diagnostics.whereOp(OverlayOp.closed).single.fields, {
        'trigger': 'save',
        'openMs': 400,
        'edits': 1,
        'committed': true,
      });
      expect(diagnostics.whereOp(OverlayOp.editsDiscarded), isEmpty);
    });

    testWidgets('Cancel reports nothing and closes', (tester) async {
      final (controller, _) = await openBox(tester);
      controller.session!.edit(
        _initial.copyWith(invertMedia: true),
        field: DraftOptionsField.position,
      );

      await tester.tap(button(strings.cancel));
      await tester.pumpAndSettle();

      expect(controller.isOpen, isFalse);
      expect(host.edits, isEmpty);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'cancel',
      );
      expect(diagnostics.whereOp(OverlayOp.editsDiscarded).single.fields, {
        'edits': 1,
      });
    });

    testWidgets('Escape reports nothing and closes', (tester) async {
      final (controller, _) = await openBox(tester);
      controller.session!.edit(
        _initial.copyWith(invertMedia: true),
        field: DraftOptionsField.position,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(controller.isOpen, isFalse);
      expect(host.edits, isEmpty);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'escape',
      );
      expect(diagnostics.whereOp(OverlayOp.editsDiscarded), hasLength(1));
    });

    testWidgets('Enter saves', (tester) async {
      final (controller, _) = await openBox(tester);
      final above = _initial.copyWith(invertMedia: true);
      controller.session!.edit(above, field: DraftOptionsField.position);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(controller.isOpen, isFalse);
      expect(host.edits, [above]);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'save',
      );
    });

    testWidgets('a click outside closes on release, not on press', (
      tester,
    ) async {
      final (controller, _) = await openBox(tester);

      final gesture = await tester.startGesture(
        const Offset(4, 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(controller.session?.isClosing, isFalse);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'outside',
      );
      expect(host.edits, isEmpty);
    });

    testWidgets('the link hint shows under the rows with more than one link', (
      tester,
    ) async {
      await openBox(tester, links: [_url, _other]);

      final hint = tester.getRect(find.text(strings.chooseLinkHint));
      final rows = tester.getRect(find.byType(DraftLinkRowView).last);
      final box = tester.getRect(find.byKey(DraftOptionsBox.boxKey));
      expect(hint.top, greaterThanOrEqualTo(rows.bottom + 8));
      expect(hint.left - box.left, 22);
    });

    testWidgets('the preview asks the builder for the click cursor over '
        'links and the instant change', (tester) async {
      await openBox(tester);

      expect(bubble.previews.last.linkCursor, SystemMouseCursors.click);
      expect(bubble.previews.last.change.duration, Duration.zero);
    });
  });

  group('focus', () {
    testWidgets('moves into the box on open, through the rows and the '
        'buttons by Tab, and back to the field on close', (tester) async {
      final (controller, composer) = await openBox(tester);

      expect(composer.hasFocus, isFalse);
      final primary = FocusManager.instance.primaryFocus?.context;
      expect(primary, isNotNull);
      expect(
        primary!.findAncestorWidgetOfExactType<DraftOptionsOverlay>(),
        isNotNull,
      );

      final order = <String?>[];
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add(focused());
      }
      expect(order, [
        strings.moveUp,
        strings.removePreview,
        strings.save,
        strings.cancel,
      ]);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      expect(composer.hasFocus, isTrue);
    });

    testWidgets('a focused row presses on Space and Enter; Enter on a '
        'focused Cancel cancels', (tester) async {
      final (controller, _) = await openBox(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.session!.value.value.invertMedia, isTrue);

      clock.advance(DraftLinkPagePolicy.desktop.rowGuard);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.session!.value.value.invertMedia, isFalse);
      expect(controller.session!.isClosing, isFalse);

      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      expect(focused(), strings.cancel);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'cancel',
      );
    });

    testWidgets('a mobile overlay leaves focus with the field', (tester) async {
      final (_, composer) = await openBox(
        tester,
        policy: const DraftOptionsPolicy.ios(),
      );

      expect(composer.hasFocus, isTrue);
      expect(find.byType(DraftOptionsBox), findsNothing);
    });
  });

  group('motion', () {
    testWidgets('the box fades in over 200 ms and out over 200 ms', (
      tester,
    ) async {
      final (controller, _) = await openBox(tester, settle: false);

      expect(boxOpacity(tester), lessThan(0.5));
      await tester.pump(const Duration(milliseconds: 100));
      final half = boxOpacity(tester);
      expect(half, greaterThan(0));
      expect(half, lessThan(1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(boxOpacity(tester), 1);

      controller.session!.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final out = boxOpacity(tester);
      expect(out, greaterThan(0));
      expect(out, lessThan(1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(boxOpacity(tester), 0);
      await tester.pumpAndSettle();
      expect(find.byType(DraftOptionsOverlay), findsNothing);
    });

    testWidgets('an option change re-lays the box out at once', (tester) async {
      final (controller, _) = await openBox(tester);

      controller.session!.edit(
        _initial.copyWith(invertMedia: true),
        field: DraftOptionsField.position,
      );
      await tester.pump();

      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(bubble.previews.last.part.invertMedia, isTrue);
      expect(find.text(strings.moveDown), findsOneWidget);
    });

    testWidgets('reports open, change and close as motion events', (
      tester,
    ) async {
      final (controller, _) = await openBox(tester);
      controller.session!.edit(
        _initial.copyWith(invertMedia: true),
        field: DraftOptionsField.position,
      );
      await tester.pump();
      controller.session!.cancel();
      await tester.pumpAndSettle();

      final motion = diagnostics.whereOp(OverlayOp.motion);
      expect(motion.map((e) => e.fields).toList(), [
        {
          'presentation': 'desktop',
          'phase': 'open',
          'durationMs': 200,
          'reduceMotion': false,
        },
        {
          'presentation': 'desktop',
          'phase': 'change',
          'durationMs': 0,
          'reduceMotion': false,
        },
        {
          'presentation': 'desktop',
          'phase': 'close',
          'durationMs': 200,
          'reduceMotion': false,
        },
      ]);
      expect(
        motion.first,
        isChatEvent(
          level: ChatEventLevel.trace,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
        ),
      );
    });

    testWidgets('under reduce motion the box shows at once', (tester) async {
      await openBox(
        tester,
        motionSpeed: ChromeMotionSpeed.instant,
        settle: false,
      );
      await tester.pump();

      expect(boxOpacity(tester), 1);
      expect(diagnostics.whereOp(OverlayOp.motion).single.fields, {
        'presentation': 'desktop',
        'phase': 'open',
        'durationMs': 0,
        'reduceMotion': true,
      });
    });
  });
}
