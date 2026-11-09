import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/panel_playback_hold.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';

const _popup = PanelPresentation.anchoredPopup();
const _keyboard = PanelPresentation.keyboardReplacement();
const _dock = PanelPresentation.docked();

void main() {
  late listen.ValueNotifier<PanelVisibility> state;
  late PlaybackClock clock;
  late PanelPlaybackHold hold;

  setUp(() {
    state = listen.ValueNotifier<PanelVisibility>(PanelVisibility.hidden);
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    hold = PanelPlaybackHold(presentation: state, clock: clock);
    addTearDown(() {
      hold.dispose();
      clock.dispose();
      state.dispose();
    });
  });

  bool moving() => clock.pausedLayers.contains(PlaybackPauseLayer.routeMoving);

  for (final kind in [_popup, _keyboard, _dock]) {
    test('every animation stops while a ${kind.runtimeType} panel moves in '
        'or out, and plays once it settles', () {
      state.value = PanelVisibility.showing(kind);
      expect(moving(), isTrue);
      expect(clock.isPaused, isTrue);

      state.value = PanelVisibility.shown(kind);
      expect(moving(), isFalse);

      state.value = PanelVisibility.hiding(kind);
      expect(moving(), isTrue);

      state.value = PanelVisibility.hidden;
      expect(moving(), isFalse);
    });
  }

  test('the chat holds while a popup panel is on screen, and only then', () {
    expect(hold.chatHeld.value, isFalse);

    state.value = const PanelVisibility.showing(_popup);
    expect(hold.chatHeld.value, isTrue);
    state.value = const PanelVisibility.shown(_popup);
    expect(hold.chatHeld.value, isTrue);
    state.value = const PanelVisibility.hiding(_popup);
    expect(hold.chatHeld.value, isTrue);
    state.value = PanelVisibility.hidden;
    expect(hold.chatHeld.value, isFalse);
  });

  test('a docked or keyboard panel at rest holds nothing', () {
    for (final kind in [_dock, _keyboard]) {
      state.value = PanelVisibility.shown(kind);
      expect(hold.chatHeld.value, isFalse);
      expect(clock.isPaused, isFalse);
    }
  });

  test('a popup that turns into a dock where it stands lets the chat go', () {
    state.value = const PanelVisibility.shown(_popup);
    state.value = const PanelVisibility.shown(_dock);

    expect(hold.chatHeld.value, isFalse);
  });

  // A pack sheet over the chat: the reference pauses what is under it
  // while its own stickers play (ticket 128).
  test('a claim on the chat holds it until it is given back', () {
    final first = hold.holdChat();
    final second = hold.holdChat();
    expect(hold.chatHeld.value, isTrue);
    expect(clock.isPaused, isFalse);

    first.release();
    first.release();
    expect(hold.chatHeld.value, isTrue);

    second.release();
    expect(hold.chatHeld.value, isFalse);
  });

  test('a claim and a popup panel hold the chat together', () {
    final claim = hold.holdChat();
    state.value = const PanelVisibility.shown(_popup);
    state.value = PanelVisibility.hidden;
    expect(hold.chatHeld.value, isTrue);

    claim.release();
    expect(hold.chatHeld.value, isFalse);
  });

  test('a claim given back after dispose is harmless', () {
    final claim = hold.holdChat();
    hold.dispose();

    expect(hold.chatHeld.value, isFalse);
    claim.release();
  });

  test('dispose clears the layer it set and no other', () {
    clock.setPaused(PlaybackPauseLayer.fastScroll, paused: true);
    state.value = const PanelVisibility.showing(_popup);

    hold.dispose();

    expect(moving(), isFalse);
    expect(clock.pausedLayers, {PlaybackPauseLayer.fastScroll});
    expect(hold.chatHeld.value, isFalse);
    state.value = PanelVisibility.hidden;
  });

  test('a layer the host raised itself is not cleared by a settle', () {
    clock.setPaused(PlaybackPauseLayer.routeMoving, paused: true);

    state.value = const PanelVisibility.shown(_dock);

    expect(moving(), isTrue);
  });
}
