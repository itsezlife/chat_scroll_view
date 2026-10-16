import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

/// Runs the behaviour every [PanelPresentationPolicy] must have, against the
/// policy [create] returns.
///
/// Call it inside a `group`. It checks the policy as a whole, not one
/// family's choices: an override always wins, docking is only ever chosen
/// where it is possible, every kind can be dismissed by back, a popup that
/// opens on hover also closes when the pointer leaves, popup sizing is
/// clamped and monotonic, and equal policies compare equal.
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

    test('an override wins for every window class and dock preference', () {
      final policy = create();
      for (final windowClass in PanelWindowClass.values) {
        for (final dockPreferred in [false, true]) {
          for (final kind in kinds) {
            expect(
              policy.resolve(
                windowClass: windowClass,
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
      for (final windowClass in PanelWindowClass.values) {
        for (final dockPreferred in [false, true]) {
          expect(
            policy.resolve(
              windowClass: windowClass,
              dockPreferred: dockPreferred,
            ),
            policy.defaultKind(
              windowClass: windowClass,
              dockPreferred: dockPreferred,
            ),
          );
        }
      }
    });

    test('the default is docked only where docking is possible', () {
      final policy = create();
      for (final windowClass in PanelWindowClass.values) {
        final kind = policy.defaultKind(
          windowClass: windowClass,
          dockPreferred: true,
        );
        if (kind is Docked) expect(policy.canDock(windowClass), isTrue);
      }
    });

    test('without a dock preference the default is never docked', () {
      final policy = create();
      for (final windowClass in PanelWindowClass.values) {
        expect(
          policy.defaultKind(windowClass: windowClass),
          isNot(isA<Docked>()),
        );
      }
    });

    test('every kind can be dismissed by back', () {
      final policy = create();
      for (final kind in kinds) {
        expect(policy.dismissalsFor(kind), contains(PanelDismissal.back));
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
