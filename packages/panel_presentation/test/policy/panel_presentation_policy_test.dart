import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';

void main() {
  group('PanelWindowClass', () {
    test('classifies a width by the 600 and 840 breakpoints', () {
      expect(PanelWindowClass.fromWidth(0), PanelWindowClass.compact);
      expect(PanelWindowClass.fromWidth(599.9), PanelWindowClass.compact);
      expect(PanelWindowClass.fromWidth(600), PanelWindowClass.medium);
      expect(PanelWindowClass.fromWidth(839.9), PanelWindowClass.medium);
      expect(PanelWindowClass.fromWidth(840), PanelWindowClass.expanded);
      expect(PanelWindowClass.fromWidth(4000), PanelWindowClass.expanded);
    });

    test('only expanded is wide', () {
      expect(PanelWindowClass.values.where((c) => c.isWide), [
        PanelWindowClass.expanded,
      ]);
    });
  });

  group('PanelWindow', () {
    test('derives its class from the width', () {
      expect(
        const PanelWindow(width: 900, height: 700).windowClass,
        PanelWindowClass.expanded,
      );
      expect(
        const PanelWindow(width: 390, height: 844).windowClass,
        PanelWindowClass.compact,
      );
    });

    test('compares by size', () {
      expect(
        const PanelWindow(width: 390, height: 844),
        const PanelWindow(width: 390, height: 844),
      );
      expect(
        const PanelWindow(width: 390, height: 844),
        isNot(const PanelWindow(width: 390, height: 845)),
      );
    });
  });

  group('PanelOsFamily', () {
    test('only Android and iOS are mobile', () {
      expect(PanelOsFamily.values.where((f) => f.isMobile), [
        PanelOsFamily.android,
        PanelOsFamily.iOS,
      ]);
    });

    test('maps a target platform; the web is desktop whatever the OS', () {
      expect(
        PanelOsFamily.fromPlatform(TargetPlatform.iOS, isWeb: false),
        PanelOsFamily.iOS,
      );
      expect(
        PanelOsFamily.fromPlatform(TargetPlatform.android, isWeb: false),
        PanelOsFamily.android,
      );
      expect(
        PanelOsFamily.fromPlatform(TargetPlatform.macOS, isWeb: false),
        PanelOsFamily.macOS,
      );
      expect(
        PanelOsFamily.fromPlatform(TargetPlatform.windows, isWeb: false),
        PanelOsFamily.windows,
      );
      expect(
        PanelOsFamily.fromPlatform(TargetPlatform.linux, isWeb: false),
        PanelOsFamily.linux,
      );
      expect(
        PanelOsFamily.fromPlatform(TargetPlatform.fuchsia, isWeb: false),
        PanelOsFamily.fuchsia,
      );
      expect(
        PanelOsFamily.fromPlatform(TargetPlatform.android, isWeb: true),
        PanelOsFamily.web,
      );
    });
  });

  group('policy selection by family', () {
    test('mobile families get the mobile policy', () {
      for (final family in [PanelOsFamily.android, PanelOsFamily.iOS]) {
        expect(
          PanelPresentationPolicy.forFamily(family),
          isA<PanelPresentationPolicy$Mobile>(),
        );
      }
    });

    test('every other family gets the desktop policy', () {
      for (final family in PanelOsFamily.values.where((f) => !f.isMobile)) {
        expect(
          PanelPresentationPolicy.forFamily(family),
          isA<PanelPresentationPolicy$Desktop>(),
        );
      }
    });
  });

  group('default kind, OS family x window class', () {
    const mobile = PanelPresentationPolicy$Mobile();
    const desktop = PanelPresentationPolicy$Desktop();

    test('mobile replaces the keyboard at every window class', () {
      for (final windowClass in PanelWindowClass.values) {
        expect(
          mobile.defaultKind(windowClass: windowClass),
          const KeyboardReplacement(),
        );
      }
    });

    test('mobile ignores a dock preference', () {
      expect(
        mobile.defaultKind(
          windowClass: PanelWindowClass.expanded,
          dockPreferred: true,
        ),
        const KeyboardReplacement(),
      );
    });

    test('desktop opens a popup at every window class by default', () {
      for (final windowClass in PanelWindowClass.values) {
        expect(
          desktop.defaultKind(windowClass: windowClass),
          const AnchoredPopup(),
        );
      }
    });

    test('desktop docks only when preferred and the window is wide', () {
      expect(
        desktop.defaultKind(
          windowClass: PanelWindowClass.expanded,
          dockPreferred: true,
        ),
        const Docked(),
      );
      for (final windowClass in [
        PanelWindowClass.compact,
        PanelWindowClass.medium,
      ]) {
        expect(
          desktop.defaultKind(windowClass: windowClass, dockPreferred: true),
          const AnchoredPopup(),
        );
      }
    });

    test('only desktop can dock, and only in a wide window', () {
      expect(mobile.canDock(PanelWindowClass.expanded), isFalse);
      expect(desktop.canDock(PanelWindowClass.expanded), isTrue);
      expect(desktop.canDock(PanelWindowClass.medium), isFalse);
    });
  });

  group('host override', () {
    test('wins over the default for either policy', () {
      for (final policy in <PanelPresentationPolicy>[
        const PanelPresentationPolicy$Mobile(),
        const PanelPresentationPolicy$Desktop(),
      ]) {
        for (final kind in <PanelPresentation>[
          const KeyboardReplacement(),
          const AnchoredPopup(),
          const Docked(),
        ]) {
          expect(
            policy.resolve(
              windowClass: PanelWindowClass.compact,
              override: kind,
            ),
            kind,
          );
        }
      }
    });

    test('falls back to the default without one', () {
      const policy = PanelPresentationPolicy$Desktop();
      expect(
        policy.resolve(windowClass: PanelWindowClass.medium),
        policy.defaultKind(windowClass: PanelWindowClass.medium),
      );
    });
  });

  group('open triggers', () {
    test('only desktop opens on hover', () {
      expect(const PanelPresentationPolicy$Mobile().hoverOpens, isFalse);
      expect(const PanelPresentationPolicy$Desktop().hoverOpens, isTrue);
    });
  });

  group('dismissal', () {
    test('mobile dismisses by back for every kind and nothing else', () {
      const policy = PanelPresentationPolicy$Mobile();
      for (final kind in <PanelPresentation>[
        const KeyboardReplacement(),
        const AnchoredPopup(),
        const Docked(),
      ]) {
        expect(policy.dismissalsFor(kind), {PanelDismissal.back});
      }
    });

    test(
      'a desktop popup dismisses by Esc, outside press, leave and after a hold',
      () {
        expect(
          const PanelPresentationPolicy$Desktop().dismissalsFor(
            const AnchoredPopup(),
          ),
          {
            PanelDismissal.back,
            PanelDismissal.escape,
            PanelDismissal.outsidePress,
            PanelDismissal.leave,
            PanelDismissal.afterHold,
          },
        );
      },
    );

    test(
      'a desktop docked section and keyboard panel dismiss by back only',
      () {
        const policy = PanelPresentationPolicy$Desktop();
        expect(policy.dismissalsFor(const Docked()), {PanelDismissal.back});
        expect(policy.dismissalsFor(const KeyboardReplacement()), {
          PanelDismissal.back,
        });
      },
    );

    test(
      'timers follow the reference client: 300 ms leave, 3 s after a hold',
      () {
        const policy = PanelPresentationPolicy$Desktop();
        expect(policy.leaveDelay, const Duration(milliseconds: 300));
        expect(policy.afterHoldDelay, const Duration(seconds: 3));
      },
    );
  });

  group('sizing', () {
    const policy = PanelPresentationPolicy$Desktop();

    test('a popup is three quarters of the window height', () {
      expect(policy.popupHeight(windowHeight: 600), 450);
    });

    test('is clamped to 278 at the bottom and 640 at the top', () {
      expect(policy.popupHeight(windowHeight: 200), 278);
      expect(policy.popupHeight(windowHeight: 0), 278);
      expect(policy.popupHeight(windowHeight: 2000), 640);
    });
  });

  group('motion roles', () {
    const policy = PanelPresentationPolicy$Desktop();

    test('a popup uses the popup roles', () {
      expect(policy.showRole(const AnchoredPopup()), MotionRole.popupShow);
      expect(policy.hideRole(const AnchoredPopup()), MotionRole.popupHide);
    });

    test('the other kinds slide the panel', () {
      for (final kind in <PanelPresentation>[
        const KeyboardReplacement(),
        const Docked(),
      ]) {
        expect(policy.showRole(kind), MotionRole.panelSlide);
        expect(policy.hideRole(kind), MotionRole.panelSlide);
      }
    });

    test('switching presentations has its own role', () {
      expect(policy.switchRole, MotionRole.presentationSwitch);
    });
  });

  group('contract', () {
    runPresentationPolicyContract(
      r'PanelPresentationPolicy$Mobile',
      () => const PanelPresentationPolicy$Mobile(),
    );
    runPresentationPolicyContract(
      r'PanelPresentationPolicy$Desktop',
      () => const PanelPresentationPolicy$Desktop(),
    );
  });
}
