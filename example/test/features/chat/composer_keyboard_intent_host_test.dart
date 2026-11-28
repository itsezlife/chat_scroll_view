/// The example carrying out the composer's keyboard intent through the
/// panel presentation: `hold` lowers the keyboard and holds its occupancy,
/// `keep` and `hide` end the hold.
///
/// **Seam:** `ComposerKeyboardIntentHost` over a `ComposerController` and a
/// `KeyboardReplacementStrategy` fed by a `FakeImeInput`, with a recorded
/// keyboard hide.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/composer_keyboard_intent_host.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';

const _shrink = MotionSpec(Duration(milliseconds: 200), Curves.linear);

void main() {
  late FakeImeInput ime;
  late listen.ValueNotifier<PanelWindow> window;
  late KeyboardReplacementStrategy keyboard;
  late ComposerController composer;
  late List<String> hides;
  late ComposerKeyboardIntentHost host;

  setUp(() async {
    ime = FakeImeInput();
    window = listen.ValueNotifier(const PanelWindow(width: 400, height: 800));
    keyboard = KeyboardReplacementStrategy(
      ime: ime,
      heights: await KeyboardHeightStore.open(FakeKeyValueStore()),
      window: window,
    );
    composer = ComposerController();
    hides = [];
    host = ComposerKeyboardIntentHost(
      composer: composer,
      keyboard: keyboard,
      hideKeyboard: (why) async => hides.add(why),
      shrink: _shrink,
    );
    addTearDown(() {
      host.dispose();
      composer.dispose();
      keyboard.dispose();
      window.dispose();
      ime.dispose();
    });
  });

  double occupancy() => keyboard.occupancy.value.bottom;

  testWidgets('hold lowers the keyboard and keeps its height occupied', (
    tester,
  ) async {
    ime.report(const ImeSample(height: 300));

    composer.setKeyboardIntent(ComposerKeyboardIntent.hold);
    ime.report(ImeSample.hidden);

    expect(hides, hasLength(1));
    expect(occupancy(), 300);
  });

  testWidgets('keep ends the hold: a reopened keyboard takes it over', (
    tester,
  ) async {
    ime.report(const ImeSample(height: 300));
    composer.setKeyboardIntent(ComposerKeyboardIntent.hold);
    ime.report(ImeSample.hidden);
    ime.report(const ImeSample(height: 300));

    composer.setKeyboardIntent(ComposerKeyboardIntent.keep);
    ime.report(ImeSample.hidden);

    expect(occupancy(), 0, reason: 'the slot follows the keyboard again');
    expect(hides, hasLength(1));
  });

  testWidgets('hide ends the hold with the keyboard down: the slot shrinks', (
    tester,
  ) async {
    ime.report(const ImeSample(height: 300));
    composer.setKeyboardIntent(ComposerKeyboardIntent.hold);
    ime.report(ImeSample.hidden);

    composer.setKeyboardIntent(ComposerKeyboardIntent.hide);
    expect(occupancy(), 300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(occupancy(), 0);
    expect(hides, hasLength(1));
  });

  testWidgets('dispose ends a hold under way', (tester) async {
    ime.report(const ImeSample(height: 300));
    composer.setKeyboardIntent(ComposerKeyboardIntent.hold);
    ime.report(ImeSample.hidden);

    host.dispose();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(occupancy(), 0);
  });
}
