import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

void main() {
  late FakePanelPage emoji;
  late FakePanelPage stickers;
  late PanelShellController shell;
  late List<FakePresentationStrategy> strategies;
  late PanelPresentationController controller;

  const mobile = PanelPresentationPolicy$Mobile();
  const desktop = PanelPresentationPolicy$Desktop();
  const wide = PanelWindow(width: 1200, height: 800);
  const narrow = PanelWindow(width: 500, height: 800);

  PanelPresentationController build({
    PanelPresentationPolicy policy = desktop,
    PanelWindow window = narrow,
    bool dockPreferred = false,
    List<FakePresentationStrategy>? with_,
  }) {
    shell = PanelShellController(
      pages: [emoji.page, stickers.page],
      preferences: FakePreferenceStore(),
    );
    addTearDown(shell.dispose);
    strategies =
        with_ ??
        [
          FakePresentationStrategy(const KeyboardReplacement()),
          FakePresentationStrategy(const AnchoredPopup()),
          FakePresentationStrategy(const Docked()),
        ];
    addTearDown(() {
      for (final strategy in strategies) {
        strategy.dispose();
      }
    });
    controller = PanelPresentationController(
      shell: shell,
      policy: policy,
      strategies: strategies,
      window: window,
      dockPreferred: dockPreferred,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  FakePresentationStrategy strategyOf(PanelPresentation kind) =>
      strategies.firstWhere((s) => s.kind == kind);

  setUp(() {
    emoji = FakePanelPage('emoji', search: true);
    stickers = FakePanelPage('stickers');
  });

  group('commands commit when unbound', () {
    test('starts hidden and not visible to the shell', () {
      build();
      expect(controller.state.value, PanelVisibility.hidden);
      expect(shell.visible.value, isFalse);
    });

    test('show lands in shown at once, as the policy default kind', () {
      build();
      controller.show();
      expect(
        controller.state.value,
        const PanelVisibility.shown(AnchoredPopup()),
      );
    });

    test('hide lands in hidden at once', () {
      build()
        ..show()
        ..hide();
      expect(controller.state.value, PanelVisibility.hidden);
    });

    test('toggle alternates', () {
      build().toggle();
      expect(controller.state.value.isVisible, isTrue);
      controller.toggle();
      expect(controller.state.value.isVisible, isFalse);
    });

    test('the mobile policy opens the keyboard replacement', () {
      build(policy: mobile).show();
      expect(controller.state.value.kind, const KeyboardReplacement());
    });

    test('a host override beats the policy for one call', () {
      build().show(kind: const KeyboardReplacement());
      expect(controller.state.value.kind, const KeyboardReplacement());
      controller
        ..hide()
        ..show();
      expect(controller.state.value.kind, const AnchoredPopup());
    });

    test('showing what is shown changes nothing and signals nothing', () {
      build().show();
      var signals = 0;
      controller.state.addListener(() => signals++);
      controller.show();
      controller.show(kind: const AnchoredPopup());
      expect(signals, 0);
    });

    test('hiding what is hidden signals nothing', () {
      build();
      var signals = 0;
      controller.state.addListener(() => signals++);
      controller.hide();
      expect(signals, 0);
    });

    test('show with another kind switches in place', () {
      build().show();
      controller.show(kind: const KeyboardReplacement());
      expect(
        controller.state.value,
        const PanelVisibility.shown(KeyboardReplacement()),
      );
    });
  });

  group('with a view attached', () {
    late PanelPresentationAttachment view;

    setUp(() {
      build();
      view = controller.attach();
    });

    test('show enters showing and reports the panel opening to the shell', () {
      controller.show();
      expect(
        controller.state.value,
        const PanelVisibility.showing(AnchoredPopup()),
      );
      expect(shell.visible.value, isTrue);
      expect(shell.opening.value, isTrue);
    });

    test('the view settles showing into shown at rest', () {
      controller.show();
      view.motionSettled(controller.state.value);
      expect(
        controller.state.value,
        const PanelVisibility.shown(AnchoredPopup()),
      );
      expect(shell.visible.value, isTrue);
      expect(shell.opening.value, isFalse);
    });

    test('hide enters hiding, still visible to the shell, then hidden', () {
      controller.show();
      view.motionSettled(controller.state.value);
      controller.hide();
      expect(
        controller.state.value,
        const PanelVisibility.hiding(AnchoredPopup()),
      );
      expect(shell.visible.value, isTrue);
      expect(shell.opening.value, isTrue);

      view.motionSettled(controller.state.value);

      expect(controller.state.value, PanelVisibility.hidden);
      expect(shell.visible.value, isFalse);
      expect(shell.opening.value, isFalse);
    });

    test('hide carries the IME hand-off request into the state', () {
      controller.show();
      view.motionSettled(controller.state.value);
      controller.hide(waitForIme: true);
      expect(
        controller.state.value,
        const PanelVisibility.hiding(AnchoredPopup(), waitForIme: true),
      );
    });

    test('a settle report for a replaced state is ignored', () {
      controller.show();
      final stale = controller.state.value;
      view.motionSettled(stale);
      controller.hide();
      view.motionSettled(stale);
      expect(controller.state.value.isMoving, isTrue);
      expect(controller.state.value, isA<PanelVisibility$Hiding>());
    });

    test('showing while hiding turns the panel back, keeping its kind', () {
      controller.show(kind: const Docked());
      view.motionSettled(controller.state.value);
      controller.hide();
      controller.show();
      expect(controller.state.value, const PanelVisibility.showing(Docked()));
    });

    test('showing while hiding with another kind switches to it', () {
      controller.show();
      view.motionSettled(controller.state.value);
      controller.hide();
      controller.show(kind: const Docked());
      expect(controller.state.value, const PanelVisibility.showing(Docked()));
    });

    test('toggle while showing hides', () {
      controller.show();
      controller.toggle();
      expect(controller.state.value, isA<PanelVisibility$Hiding>());
    });

    test('toggle while hiding shows again', () {
      controller.show();
      view.motionSettled(controller.state.value);
      controller.hide();
      controller.toggle();
      expect(controller.state.value, isA<PanelVisibility$Showing>());
    });

    test('detaching the last view settles a moving state at once', () {
      controller.show();
      view.detach();
      expect(
        controller.state.value,
        const PanelVisibility.shown(AnchoredPopup()),
      );
      expect(shell.opening.value, isFalse);
    });

    test('detaching one of two views keeps waiting for the other', () {
      final second = controller.attach();
      controller.show();
      view.detach();
      expect(controller.state.value.isMoving, isTrue);
      second.detach();
      expect(controller.state.value.isMoving, isFalse);
    });

    test('detach is idempotent', () {
      controller.show();
      view
        ..detach()
        ..detach();
      expect(controller.state.value, isA<PanelVisibility$Shown>());
    });
  });

  group('presence', () {
    test('the shell sees presence before state listeners run', () {
      build();
      final seen = <bool>[];
      controller.state.addListener(() => seen.add(shell.visible.value));
      controller
        ..show()
        ..hide();
      expect(seen, [true, false]);
    });

    test('a switch of kind keeps the panel visible', () {
      build().show();
      controller.show(kind: const Docked());
      expect(shell.visible.value, isTrue);
    });
  });

  group('handleBack', () {
    test('closes search before the panel, then the panel, then nothing', () {
      build().show();
      shell.openSearch();

      expect(controller.handleBack(), isTrue);
      expect(shell.search.value.isOpen, isFalse);
      expect(controller.state.value.isVisible, isTrue);

      expect(controller.handleBack(), isTrue);
      expect(controller.state.value, PanelVisibility.hidden);

      expect(controller.handleBack(), isFalse);
    });

    test('a hidden panel with search closed consumes nothing', () {
      build();
      expect(controller.handleBack(), isFalse);
    });

    test('a panel that is hiding still consumes the press', () {
      build();
      final view = controller.attach();
      addTearDown(view.detach);
      controller.show();
      view.motionSettled(controller.state.value);
      controller.hide();
      expect(controller.handleBack(), isTrue);
      expect(controller.state.value, isA<PanelVisibility$Hiding>());
    });
  });

  group('docking', () {
    test('dock moves a popup into the docked section in a wide window', () {
      build(window: wide)
        ..show(kind: const AnchoredPopup())
        ..dock();
      expect(controller.state.value, const PanelVisibility.shown(Docked()));
      expect(controller.dockPreferred.value, isTrue);
    });

    test('dock in a narrow window only records the preference', () {
      build()
        ..show()
        ..dock();
      expect(controller.state.value.kind, const AnchoredPopup());
      expect(controller.dockPreferred.value, isTrue);
    });

    test('dock while hidden, in a window with the room, shows the dock', () {
      build(window: wide).dock();
      expect(controller.state.value.kind, const Docked());
    });

    test('dock while hidden, in a window without the room, records the '
        'preference for when it has', () {
      build(window: narrow).dock();
      expect(controller.state.value, PanelVisibility.hidden);
      controller.show();
      expect(controller.state.value.kind, const AnchoredPopup());
      controller.updateWindow(wide);
      expect(controller.state.value.kind, const Docked());
    });

    test('undock closes a docked section and forgets the preference', () {
      build(window: wide, dockPreferred: true)
        ..show()
        ..undock();
      expect(controller.state.value, PanelVisibility.hidden);
      expect(controller.dockPreferred.value, isFalse);
      controller.show();
      expect(controller.state.value.kind, const AnchoredPopup());
    });

    test('undock leaves a popup up', () {
      build(window: wide)
        ..show()
        ..undock();
      expect(controller.state.value.kind, const AnchoredPopup());
    });

    test('a docked section goes when the window narrows, and comes back', () {
      build(window: wide, dockPreferred: true).show();
      controller.updateWindow(narrow);
      expect(controller.state.value, PanelVisibility.hidden);

      controller.updateWindow(wide);
      expect(controller.state.value.kind, const Docked());
    });

    test('a docked section stays when the window changes within wide', () {
      build(window: wide, dockPreferred: true).show();
      controller.updateWindow(const PanelWindow(width: 1600, height: 900));
      expect(controller.state.value.kind, const Docked());
    });

    test('the dock preference is not applied under the mobile policy', () {
      build(policy: mobile, window: wide, dockPreferred: true).show();
      expect(controller.state.value.kind, const KeyboardReplacement());
    });
  });

  group('occupancy', () {
    test('is zero without a strategy for the kind', () {
      build(with_: []).show();
      expect(controller.occupancy.value, PanelOccupancy.zero);
    });

    test('follows the strategy of the active kind', () {
      build().show(kind: const Docked());
      expect(controller.occupancy.value, PanelOccupancy.zero);
      strategyOf(const Docked()).published = const PanelOccupancy(
        inlineEnd: 320,
      );
      expect(controller.occupancy.value.inlineEnd, 320);
    });

    test('switches to the occupancy of the new kind', () {
      build().show(kind: const KeyboardReplacement());
      strategyOf(const KeyboardReplacement()).published = const PanelOccupancy(
        bottom: 300,
      );
      expect(controller.occupancy.value.bottom, 300);

      controller.show(kind: const AnchoredPopup());

      expect(controller.occupancy.value, PanelOccupancy.zero);
    });

    test('hidden, follows the kind the policy would open', () {
      build(policy: mobile);
      final keyboard = strategyOf(const KeyboardReplacement());
      keyboard.published = const PanelOccupancy(bottom: 291);
      expect(controller.state.value, PanelVisibility.hidden);
      expect(controller.occupancy.value.bottom, 291);
    });

    test('hidden, follows the docked kind after a wide dock preference', () {
      build(window: narrow);
      strategyOf(const Docked()).published = const PanelOccupancy(
        inlineEnd: 280,
      );
      expect(controller.occupancy.value, PanelOccupancy.zero);

      controller
        ..dock()
        ..updateWindow(wide);

      expect(controller.occupancy.value.inlineEnd, 280);
    });

    test('signals once per change of the followed strategy', () {
      build(policy: mobile);
      var signals = 0;
      controller.occupancy.addListener(() => signals++);
      final keyboard = strategyOf(const KeyboardReplacement());
      keyboard.published = const PanelOccupancy(bottom: 100);
      keyboard.published = const PanelOccupancy(bottom: 100);
      keyboard.published = const PanelOccupancy(bottom: 200);
      expect(signals, 2);
    });

    test('ignores a strategy of a kind that is not followed', () {
      build(policy: mobile);
      strategyOf(const Docked()).published = const PanelOccupancy(
        inlineEnd: 300,
      );
      expect(controller.occupancy.value, PanelOccupancy.zero);
    });
  });

  group('auto-hide guard', () {
    test('is false at rest', () {
      build();
      expect(controller.autoHideGuard.value, isFalse);
    });

    test('search focus is not a hold', () {
      build();
      shell.openSearch();
      expect(shell.search.value.wantsFocus, isTrue);
      expect(controller.autoHideGuard.value, isFalse);
    });

    test('is true while any hold is unreleased', () {
      build();
      final first = controller.holdAutoHide();
      final second = controller.holdAutoHide();
      expect(controller.autoHideGuard.value, isTrue);
      first.release();
      expect(controller.autoHideGuard.value, isTrue);
      second.release();
      expect(controller.autoHideGuard.value, isFalse);
    });

    test('holds release in any order', () {
      build();
      final first = controller.holdAutoHide();
      final second = controller.holdAutoHide();
      final third = controller.holdAutoHide();
      second.release();
      third.release();
      expect(controller.autoHideGuard.value, isTrue);
      first.release();
      expect(controller.autoHideGuard.value, isFalse);
    });

    test('releasing a hold twice counts once', () {
      build();
      final first = controller.holdAutoHide();
      final second = controller.holdAutoHide();
      first
        ..release()
        ..release();
      expect(controller.autoHideGuard.value, isTrue);
      second.release();
      expect(controller.autoHideGuard.value, isFalse);
    });

    test('notifies on the first hold and the last release only', () {
      build();
      var notifications = 0;
      controller.autoHideGuard.addListener(() => notifications++);

      final first = controller.holdAutoHide();
      final second = controller.holdAutoHide();
      expect(notifications, 1);
      first.release();
      expect(notifications, 1);
      second.release();
      expect(notifications, 2);
    });

    test('a hold taken again after a full release holds again', () {
      build();
      controller.holdAutoHide().release();
      final again = controller.holdAutoHide();
      expect(controller.autoHideGuard.value, isTrue);
      again.release();
      expect(controller.autoHideGuard.value, isFalse);
    });

    test('a hold outlives a hide and a show', () {
      build()
        ..show()
        ..hide();
      final hold = controller.holdAutoHide();
      controller.show();
      expect(controller.autoHideGuard.value, isTrue);
      hold.release();
      expect(controller.autoHideGuard.value, isFalse);
    });

    test('a hold taken after dispose holds nothing', () {
      build();
      controller.dispose();
      final hold = controller.holdAutoHide();
      hold.release();
    });

    test('a hold released after dispose is harmless', () {
      build();
      final hold = controller.holdAutoHide();
      controller.dispose();
      hold
        ..release()
        ..release();
    });
  });

  group('interactions', () {
    test('signal for page changes, search opening and closing, and picks', () {
      build();
      var signals = 0;
      controller.interactions.addListener(() => signals++);

      shell.selectPage('stickers');
      shell.selectPage('emoji');
      shell.openSearch();
      shell.closeSearch();
      shell
          .hostFor('emoji')
          .pick(
            const ContentKey.unicode('1F600'),
            kind: SemanticKind.unicodeEmoji,
          );

      expect(signals, 5);
    });

    test('do not signal for a change that did nothing', () {
      build();
      var signals = 0;
      controller.interactions.addListener(() => signals++);
      shell.closeSearch();
      shell.setQuery('x');
      expect(signals, 0);
    });
  });

  group('anchor and window', () {
    test('the anchor rectangle is null until reported', () {
      build();
      expect(controller.anchorRect.value, isNull);
      controller.anchor(const Rect.fromLTWH(10, 700, 300, 48));
      expect(
        controller.anchorRect.value,
        const Rect.fromLTWH(10, 700, 300, 48),
      );
    });

    test('the window is what the host reported', () {
      build().updateWindow(wide);
      expect(controller.window.value, wide);
    });
  });

  group('construction', () {
    test('rejects two strategies for one kind', () {
      shell = PanelShellController(
        pages: [emoji.page],
        preferences: FakePreferenceStore(),
      );
      addTearDown(shell.dispose);
      expect(
        () => PanelPresentationController(
          shell: shell,
          strategies: [
            FakePresentationStrategy(const Docked()),
            FakePresentationStrategy(const Docked()),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('defaults the policy from the OS family', () {
      shell = PanelShellController(
        pages: [emoji.page],
        preferences: FakePreferenceStore(),
      );
      addTearDown(shell.dispose);
      final created = PanelPresentationController(shell: shell);
      addTearDown(created.dispose);
      expect(
        created.policy,
        PanelPresentationPolicy.forFamily(PanelOsFamily.current),
      );
    });

    test('strategyFor answers the registered strategy or null', () {
      build(with_: [FakePresentationStrategy(const Docked())]);
      expect(controller.strategyFor(const Docked()), isNotNull);
      expect(controller.strategyFor(const AnchoredPopup()), isNull);
    });
  });

  group('dispose', () {
    test('every intent becomes a no-op and nothing signals', () {
      build().show();
      var signals = 0;
      controller.state.addListener(() => signals++);
      controller.dispose();

      controller
        ..show()
        ..hide()
        ..toggle()
        ..dock()
        ..undock()
        ..anchor(const Rect.fromLTWH(0, 0, 1, 1))
        ..updateWindow(wide);

      expect(controller.handleBack(), isFalse);
      expect(signals, 0);
      expect(controller.isDisposed, isTrue);
    });

    test('tells the shell the panel is gone but leaves the shell alive', () {
      build().show();
      expect(shell.visible.value, isTrue);
      controller.dispose();
      expect(shell.visible.value, isFalse);
      expect(shell.isDisposed, isFalse);
    });

    test('stops listening to the shell and to the strategies', () {
      build(policy: mobile);
      var signals = 0;
      controller.interactions.addListener(() => signals++);
      controller.dispose();
      shell.selectPage('stickers');
      strategyOf(const KeyboardReplacement()).published = const PanelOccupancy(
        bottom: 300,
      );
      expect(signals, 0);
      expect(controller.occupancy.value, PanelOccupancy.zero);
    });

    test('is idempotent', () {
      build();
      controller
        ..dispose()
        ..dispose();
    });

    test('a view attached or detached after dispose is harmless', () {
      build();
      controller.dispose();
      controller.attach()
        ..motionSettled(PanelVisibility.hidden)
        ..detach();
      controller.holdAutoHide().release();
    });

    test('disposing the shell first does not break the controller', () {
      build().show();
      shell.dispose();
      controller
        ..hide()
        ..dispose();
    });
  });
}
