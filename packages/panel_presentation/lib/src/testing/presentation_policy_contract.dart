import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

/// Runs the behaviour every [PanelPresentationPolicy] must have, against the
/// policy [create] returns.
///
/// Call it inside a `group`. It checks the policy as a whole, not one
/// family's choices: an override always wins, docking is only ever chosen
/// where it is possible, every kind that can be dismissed at all can be by
/// back, a popup that opens on hover also closes when the pointer leaves,
/// popup and dock sizing are clamped and monotonic, and equal policies
/// compare equal.
void runPresentationPolicyContract(
  String description,
  PanelPresentationPolicy Function() create,
) {
  group('$description presentation policy contract', () {
    const kinds = <PanelPresentation>[
      KeyboardReplacement(),
      AnchoredPopup(),
      Docked(),
    ];
    const windows = <PanelWindow>[
      PanelWindow(width: 360, height: 800),
      PanelWindow(width: 671, height: 800),
      PanelWindow(width: 672, height: 800),
      PanelWindow(width: 900, height: 800),
      PanelWindow(width: 1600, height: 900),
    ];

    test('an override wins for every window class and dock preference', () {
      final policy = create();
      for (final window in windows) {
        for (final dockPreferred in [false, true]) {
          for (final kind in kinds) {
            expect(
              policy.resolve(
                window: window,
                dockPreferred: dockPreferred,
                override: kind,
              ),
              kind,
            );
          }
        }
      }
    });

    test('without an override the default kind is used', () {
      final policy = create();
      for (final window in windows) {
        for (final dockPreferred in [false, true]) {
          expect(
            policy.resolve(window: window, dockPreferred: dockPreferred),
            policy.defaultKind(window: window, dockPreferred: dockPreferred),
          );
        }
      }
    });

    test('the default is docked only where docking is possible', () {
      final policy = create();
      for (final window in windows) {
        final kind = policy.defaultKind(window: window, dockPreferred: true);
        if (kind is Docked) expect(policy.canDock(window), isTrue);
      }
    });

    test('without a dock preference the default is never docked', () {
      final policy = create();
      for (final window in windows) {
        expect(policy.defaultKind(window: window), isNot(isA<Docked>()));
      }
    });

    test('every kind that can be dismissed at all can be by back', () {
      final policy = create();
      for (final kind in kinds) {
        final dismissals = policy.dismissalsFor(kind);
        if (dismissals.isNotEmpty) {
          expect(dismissals, contains(PanelDismissal.back));
        }
      }
    });

    test('a dock is the width the policy gives for the window and a wish', () {
      final policy = create();
      for (final window in windows) {
        for (final wanted in <double?>[null, 0, 100, 292, 340, 392, 500]) {
          final width = policy.dockWidthIn(window, wanted: wanted);
          expect(width, greaterThanOrEqualTo(policy.dockMinWidth));
          expect(width, lessThanOrEqualTo(policy.dockMaxWidth));
          if (policy.canDock(window)) {
            expect(
              window.width - width,
              greaterThanOrEqualTo(policy.dockMinChatWidth),
              reason: 'the chat keeps its room in $window with $wanted',
            );
          }
        }
      }
    });

    test('the dock never narrows as the wish grows', () {
      final policy = create();
      for (final window in windows) {
        var previous = 0.0;
        for (var wanted = 0.0; wanted <= 600; wanted += 4) {
          final width = policy.dockWidthIn(window, wanted: wanted);
          expect(width, greaterThanOrEqualTo(previous));
          previous = width;
        }
      }
    });

    test('a popup that opens on hover also hides when the pointer leaves', () {
      final policy = create();
      if (policy.hoverOpens) {
        expect(
          policy.dismissalsFor(const AnchoredPopup()),
          contains(PanelDismissal.leave),
        );
      }
    });

    test('timers are positive', () {
      final policy = create();
      expect(policy.leaveDelay, greaterThan(Duration.zero));
      expect(policy.afterHoldDelay, greaterThan(Duration.zero));
    });

    test(
      'popup height stays clamped and never shrinks as the window grows',
      () {
        final policy = create();
        var previous = 0.0;
        for (var height = 0.0; height <= 3000; height += 10) {
          final popup = policy.popupHeight(windowHeight: height);
          expect(popup, inInclusiveRange(278, 640));
          expect(popup, greaterThanOrEqualTo(previous));
          previous = popup;
        }
      },
    );

    test('a popup shows and hides with the popup roles', () {
      final policy = create();
      expect(policy.showRole(const AnchoredPopup()), isNotNull);
      expect(policy.showRole(const AnchoredPopup()), isNot(policy.switchRole));
    });

    test('equal policies compare equal', () {
      expect(create(), create());
      expect(create().hashCode, create().hashCode);
    });
  });
}
