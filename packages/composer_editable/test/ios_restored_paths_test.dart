import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'gesture_harness.dart';

/// The iOS behaviours the touch gesture matrix would otherwise drop: the Paste
/// menu on a caret tap, the floating cursor on a focused long-press, and the
/// platform's own context menu.
void main() {
  Future<void> withIos(
    WidgetTester tester,
    Future<void> Function(GestureFieldHarness harness) body, {
    TransitionBuilder? builder,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final harness = GestureFieldHarness();
    addTearDown(harness.dispose);
    try {
      await harness.pump(tester, builder: builder);
      await body(harness);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  bool toolbarShown(GestureFieldHarness harness) =>
      harness.editableState.selectionOverlay?.toolbarIsVisible ?? false;

  group('caret tap', () {
    testWidgets('on the caret of a focused field toggles the Paste menu', (
      tester,
    ) async {
      await withIos(tester, (harness) async {
        const midBeta = 8;
        await harness.tapAtOffset(midBeta);
        expect(harness.selection, const TextSelection.collapsed(offset: 8));
        expect(toolbarShown(harness), isFalse);

        await tester.pump(kDoubleTapTimeout);
        await harness.tapAtOffset(midBeta);
        expect(harness.selection, const TextSelection.collapsed(offset: 8));
        expect(toolbarShown(harness), isTrue);

        await tester.pump(kDoubleTapTimeout);
        await harness.tapAtOffset(midBeta);
        expect(toolbarShown(harness), isFalse);
      });
    });

    testWidgets('elsewhere moves the caret and puts the menu away', (
      tester,
    ) async {
      await withIos(tester, (harness) async {
        await harness.tapAtOffset(8);
        await tester.pump(kDoubleTapTimeout);
        await harness.tapAtOffset(8);
        expect(toolbarShown(harness), isTrue);

        await tester.pump(kDoubleTapTimeout);
        await harness.tapAtOffset(2);
        expect(harness.selection, const TextSelection.collapsed(offset: 2));
        expect(toolbarShown(harness), isFalse);
      });
    });

    testWidgets('on a non-collapsed selection collapses it (tap dismiss)', (
      tester,
    ) async {
      await withIos(tester, (harness) async {
        harness.controller.selection = const TextSelection(
          baseOffset: 6,
          extentOffset: 10,
        );
        await tester.pump();

        await harness.tapAtOffset(8);
        expect(harness.selection.isCollapsed, isTrue);
        expect(toolbarShown(harness), isFalse);
      });
    });

    testWidgets('on Android never toggles the menu', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final harness = GestureFieldHarness();
      addTearDown(harness.dispose);
      try {
        await harness.pump(tester);
        await harness.tapAtOffset(8);
        await tester.pump(kDoubleTapTimeout);
        await harness.tapAtOffset(8);
        expect(toolbarShown(harness), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('long-press', () {
    testWidgets('on a focused field drives the floating cursor', (
      tester,
    ) async {
      await withIos(tester, (harness) async {
        await harness.tapAtOffset(2);
        final render = harness.editableState.renderEditable;
        expect(render.floatingCursorOn, isFalse);

        final gesture = await tester.startGesture(harness.globalCaretFor(8));
        await tester.pump(kLongPressTimeout + kPressTimeout);

        expect(render.floatingCursorOn, isTrue);
        expect(
          harness.selection.isCollapsed,
          isTrue,
          reason: 'the caret moves; no word is selected',
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(render.floatingCursorOn, isFalse);
        expect(harness.selection.isCollapsed, isTrue);
      });
    });

    testWidgets('on an unfocused field selects the word and starts one-touch', (
      tester,
    ) async {
      await withIos(tester, (harness) async {
        harness.focusNode.unfocus();
        await tester.pumpAndSettle();
        expect(harness.focusNode.hasFocus, isFalse);

        await harness.longPressAtOffset(8);

        expect(harness.selection.start, 6);
        expect(harness.selection.end, 10);
        expect(harness.editableState.renderEditable.floatingCursorOn, isFalse);
      });
    });

    testWidgets('on Android still selects the word on a focused field', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final harness = GestureFieldHarness();
      addTearDown(harness.dispose);
      try {
        await harness.pump(tester);
        await harness.tapAtOffset(2);
        await harness.longPressAtOffset(8);

        expect(harness.selection.start, 6);
        expect(harness.selection.end, 10);
        expect(harness.editableState.renderEditable.floatingCursorOn, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('system context menu', () {
    late List<MethodCall> platformCalls;

    setUp(() {
      platformCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            platformCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    List<MethodCall> systemMenuCalls() => platformCalls
        .where((call) => call.method == 'ContextMenu.showSystemContextMenu')
        .toList();

    // The platform reports whether it can show its menu through MediaQuery.
    Widget platformMenuSupported(BuildContext context, Widget? child) =>
        MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(supportsShowingSystemContextMenu: true),
          child: child!,
        );

    testWidgets('is shown by the default menu builder where supported', (
      tester,
    ) async {
      await withIos(tester, builder: platformMenuSupported, (harness) async {
        harness.controller.selection = const TextSelection(
          baseOffset: 6,
          extentOffset: 10,
        );
        await tester.pump();

        harness.editableState.showToolbar();
        await tester.pumpAndSettle();

        final calls = systemMenuCalls();
        expect(calls, isNotEmpty);
        final items =
            (calls.last.arguments as Map<Object?, Object?>)['items']!
                as List<Object?>;
        expect(
          items.map((item) => (item! as Map<Object?, Object?>)['type']),
          contains('copy'),
        );
        expect(
          find.byType(AdaptiveTextSelectionToolbar),
          findsNothing,
          reason: 'the platform draws the menu, not Flutter',
        );
      });
    });

    testWidgets('is not used where the platform cannot show it', (
      tester,
    ) async {
      await withIos(tester, (harness) async {
        harness.controller.selection = const TextSelection(
          baseOffset: 6,
          extentOffset: 10,
        );
        await tester.pump();

        harness.editableState.showToolbar();
        await tester.pumpAndSettle();

        expect(systemMenuCalls(), isEmpty);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      });
    });

    testWidgets('is not used by a read-only field', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final controller = TextEditingController(text: 'alpha beta gamma');
      addTearDown(controller.dispose);
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: platformMenuSupported,
            home: Scaffold(
              body: ExtendedTextField(controller: controller, readOnly: true),
            ),
          ),
        );
        final state = tester.state<ExtendedEditableTextState>(
          find.byType(ExtendedEditableText),
        );

        expect(SystemContextMenu.isSupported(state.context), isTrue);
        expect(ExtendedSystemContextMenu.isSupportedByField(state), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
