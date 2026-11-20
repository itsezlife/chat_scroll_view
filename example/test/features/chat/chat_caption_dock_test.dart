/// The attach caption's dock: the chat's keyboard-replacement stack under
/// the caption, frame by frame.
///
/// **Seam:** [ChatCaptionDock] over the app's test services and a fake
/// soft keyboard, in a host laid out as the sheet lays its bar: the caption
/// island padded by [ChatCaptionDock.fieldBottomPad] on the dock's place,
/// at the screen's bottom.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_caption_dock.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/emoji_panel_page.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

import '../../support/fake_soft_keyboard.dart';
import '../../support/test_services.dart';

const double _safe = 34;
const double _keyboardHeight = 300;

final class _Rig {
  _Rig(this.tester, this.services, this.keyboard, this.caption, this.dock);

  final WidgetTester tester;
  final AppServices services;
  final FakeSoftKeyboard keyboard;
  final ComposerController caption;
  final ChatCaptionDock dock;

  static Future<_Rig> pump(WidgetTester tester) async {
    // The device's plugins answer nothing here.
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final name in ['dev.mpx.device_signals']) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
    final services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    tester.view
      ..physicalSize = const Size(400, 800) * 3
      ..devicePixelRatio = 3
      ..padding = const FakeViewPadding(bottom: _safe * 3)
      ..viewPadding = const FakeViewPadding(bottom: _safe * 3);
    addTearDown(tester.view.reset);
    final keyboard = FakeSoftKeyboard();
    addTearDown(keyboard.dispose);
    final caption = ComposerController();
    addTearDown(caption.dispose);
    final dock = ChatCaptionDock(
      services: services,
      view: tester.view,
      caption: caption,
      keyboard: keyboard,
    );
    addTearDown(dock.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: Builder(
          builder: (context) => Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: dock.fieldBottomPad,
                      builder: (context, pad, _) => Padding(
                        padding: EdgeInsets.only(bottom: pad),
                        child: Focus(
                          focusNode: caption.focusNode,
                          child: const SizedBox(
                            key: ValueKey('island'),
                            height: 48,
                          ),
                        ),
                      ),
                    ),
                    dock.buildPlace(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    return _Rig(tester, services, keyboard, caption, dock);
  }

  double get screen => tester.view.physicalSize.height / 3;

  /// How far the island's bottom stands over the screen's bottom.
  double get lift =>
      screen - tester.getRect(find.byKey(const ValueKey('island'))).bottom;

  /// Unmounts the host and lets the panel's glyph pages expire (a minute
  /// after their catalogue goes).
  Future<void> finish() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  Future<void> frames(int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// The keyboard up for the caption, at rest.
  Future<void> keyboardUp() async {
    caption.requestFocus();
    await tester.pump();
    keyboard.rest(_keyboardHeight);
    await tester.pumpAndSettle();
  }

  /// The keyboard moving from [from] to [to] over [steps] frames, each
  /// frame checked by [check].
  Future<void> keyboardMoves(
    double from,
    double to, {
    required int steps,
    required void Function(double height) check,
  }) async {
    for (var i = 1; i <= steps; i++) {
      final height = from + (to - from) * i / steps;
      keyboard.move(height, animating: i < steps);
      await tester.pump(const Duration(milliseconds: 16));
      check(height);
    }
    keyboard.stopMoving();
  }
}

void main() {
  testWidgets("the caption's panel is the chat's emoji page alone, on the "
      "chat's panel surface: rounded top corners and the glass", (
    tester,
  ) async {
    final rig = await _Rig.pump(tester);
    await rig.keyboardUp();
    rig.dock.togglePanel();
    await tester.pumpAndSettle();

    expect(rig.dock.panelUp, isTrue);
    final shell = tester.widget<PanelShell>(find.byType(PanelShell));
    expect(shell.controller.pages.map((page) => page.id), [EmojiPanelPage.id]);
    final surface = find.ancestor(
      of: find.byType(PanelShell),
      matching: find.byType(GlassSurface),
    );
    expect(surface, findsOneWidget);
    final glass = tester.widget<GlassSurface>(surface);
    expect(
      glass.material,
      GlassMaterial.panel,
      reason: "the chat's panel role",
    );
    final radius = glass.borderRadius!;
    expect(radius.topLeft.x, greaterThan(0));
    expect(radius.bottomLeft.x, 0);
  });

  testWidgets('keyboard to panel: the panel takes the keyboard place at its '
      'height and the keyboard goes down under it; the island never moves', (
    tester,
  ) async {
    final rig = await _Rig.pump(tester);
    await rig.keyboardUp();
    final up = rig.lift;
    expect(up, closeTo(_keyboardHeight, 0.5));

    rig.dock.togglePanel();
    await tester.pump();
    await tester.pump();
    expect(rig.caption.softKeyboard.value, SoftKeyboardMode.suppressed);
    expect(rig.keyboard.hideCount, 1, reason: 'the keyboard is lowered');
    await rig.keyboardMoves(
      _keyboardHeight,
      0,
      steps: 12,
      check: (_) => expect(rig.lift, closeTo(up, 0.5)),
    );
    await tester.pumpAndSettle();
    expect(rig.lift, closeTo(up, 0.5));
    expect(rig.caption.focusNode.hasFocus, isTrue);
  });

  testWidgets('panel to keyboard: the place is held (emptied, as the chat '
      'holds it) until the keyboard has risen; the island never moves', (
    tester,
  ) async {
    final rig = await _Rig.pump(tester);
    await rig.keyboardUp();
    rig.dock.togglePanel();
    await tester.pump();
    await rig.keyboardMoves(_keyboardHeight, 0, steps: 4, check: (_) {});
    await tester.pumpAndSettle();
    final up = rig.lift;

    rig.dock.togglePanel();
    await tester.pump();
    expect(rig.caption.softKeyboard.value, SoftKeyboardMode.auto);
    await rig.keyboardMoves(
      0,
      _keyboardHeight,
      steps: 12,
      check: (height) {
        expect(rig.lift, closeTo(up, 0.5), reason: 'keyboard at $height');
      },
    );
    await tester.pumpAndSettle();
    expect(rig.lift, closeTo(up, 0.5));
    expect(rig.dock.panelUp, isFalse);
    await rig.finish();
  });

  testWidgets('back closes the panel: it slides fully down, past the safe '
      'area, while the island comes down to the safe area and no lower', (
    tester,
  ) async {
    final rig = await _Rig.pump(tester);
    rig.dock.togglePanel();
    await tester.pumpAndSettle();
    expect(rig.dock.panelUp, isTrue);
    final up = rig.lift;
    expect(up, greaterThan(_safe));

    expect(rig.dock.handleBack(), isTrue);
    var last = up;
    final places = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final now = rig.lift;
      expect(now, lessThanOrEqualTo(last + 0.01), reason: 'down, frame $i');
      expect(now, greaterThanOrEqualTo(_safe - 0.5), reason: 'frame $i');
      places.add(rig.dock.presentation.occupancy.value.bottom);
      last = now;
    }
    expect(rig.lift, closeTo(_safe, 0.5));
    expect(rig.dock.panelUp, isFalse);
    expect(
      places.where((place) => place > 0 && place < _safe),
      isNotEmpty,
      reason: 'the panel goes on below the safe area, off the screen',
    );
    expect(rig.dock.handleBack(), isFalse, reason: 'the sheet is next');
    await rig.finish();
  });

  testWidgets('the keyboard closing: the island comes down with it to the '
      'safe area and never dips under it', (tester) async {
    final rig = await _Rig.pump(tester);
    await rig.keyboardUp();
    await rig.keyboardMoves(
      _keyboardHeight,
      0,
      steps: 20,
      check: (height) => expect(
        rig.lift,
        greaterThanOrEqualTo(_safe - 0.5),
        reason: 'keyboard at $height',
      ),
    );
    await tester.pumpAndSettle();
    expect(rig.lift, closeTo(_safe, 0.5));
  });

  testWidgets('a pick types into the caption', (tester) async {
    final rig = await _Rig.pump(tester);
    rig.dock.togglePanel();
    await tester.pumpAndSettle();
    rig.dock.shell
        .hostFor(EmojiPanelPage.id)
        .pick(const ContentKey.unicode('😀'), kind: SemanticKind.unicodeEmoji);
    await tester.pump();
    expect(rig.caption.richText.plain, '😀');
  });
}
