import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const android = AttachSheetPolicy.android();
  const ios = AttachSheetPolicy.ios();

  group('Android geometry', () {
    test('rests at 2/5 of the height in portrait, plus the header line', () {
      // 800 tall, 24 status bar: 776 available, 2/5 is 310.4; the header
      // line adds 56 - 52 + 48 and the sheet's background starts 13 above the
      // first row: 310.4 + 39 + 24.
      expect(
        android.collapsedTop(
          const Size(400, 800),
          const EdgeInsets.only(top: 24),
        ),
        closeTo(373.4, 0.01),
      );
    });

    test('rests at 1/3.5 of the height in landscape', () {
      expect(
        android.collapsedTop(const Size(800, 400), EdgeInsets.zero),
        closeTo(400 / 3.5 + 39, 0.01),
      );
    });

    test('pins under the status bar', () {
      expect(android.expandedTop(const EdgeInsets.only(top: 24)), 24);
    });

    test('dims to 51/255 over 400 ms with an overshoot, after 20 ms', () {
      expect(android.dimOpacity, closeTo(0.2, 0.001));
      expect(android.dimIn.duration, const Duration(milliseconds: 400));
      expect(android.dimIn.curve.transform(0.8), greaterThan(1));
      expect(android.dimDelay, const Duration(milliseconds: 20));
    });

    test('opens on a spring of damping 0.75, stiffness 350', () {
      expect(
        android.openMotion,
        AttachSheetMotion.spring(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: 350,
            ratio: 0.75,
          ),
        ),
      );
    });

    test('closes over 250 ms ease out', () {
      expect(
        android.closeMotion,
        const AttachSheetMotion.timed(
          MotionSpec(Duration(milliseconds: 250), Cubic(0, 0, 0.58, 1)),
        ),
      );
    });

    test('reopens the keyboard 200 ms after close', () {
      expect(android.keyboardReopenDelay, const Duration(milliseconds: 200));
      expect(ios.keyboardReopenDelay, isNull);
    });
  });

  group('Android release', () {
    AttachSheetRelease? release(
      double top, {
      double velocity = 0,
      double dpr = 3,
    }) => android.release(
      AttachSheetReleaseInput(
        top: top,
        collapsedTop: 400,
        expandedTop: 24,
        velocity: velocity,
        startedExpanded: false,
        devicePixelRatio: dpr,
      ),
    );

    test('past 0.8 cm below its rest it dismisses', () {
      // 0.8 cm is 50.39 logical pixels.
      expect(release(400 + 50.4), AttachSheetRelease.dismiss);
      expect(release(400 + 50.3), AttachSheetRelease.holdCollapsed);
    });

    test('moving up, it never dismisses: it goes back to its rest, however '
        'far below it', () {
      expect(
        release(400 + 54, velocity: -1303),
        AttachSheetRelease.holdCollapsed,
      );
      expect(
        release(400 + 300, velocity: -1),
        AttachSheetRelease.holdCollapsed,
      );
      // Still: past 0.8 cm it goes.
      expect(release(400 + 54), AttachSheetRelease.dismiss);
    });

    test('a downward fling of 3500 physical px/s dismisses', () {
      expect(release(410, velocity: 3500 / 3), AttachSheetRelease.dismiss);
      expect(
        release(410, velocity: 3499 / 3),
        AttachSheetRelease.holdCollapsed,
      );
      expect(
        release(410, velocity: 1200, dpr: 2),
        AttachSheetRelease.holdCollapsed,
      );
    });

    test('springs back over 250 ms for each 0.8 cm', () {
      final spec = android.holdMotion(50.394 / 2);
      expect(spec.duration.inMilliseconds, closeTo(125, 1));
      expect(spec.curve, const Cubic(0.25, 0.1, 0.25, 1));
    });

    test('between its rest and the top it flings with the page', () {
      expect(release(200, velocity: -800), AttachSheetRelease.fling);
      expect(release(24), isNull);
    });

    test('has no snap at the top: the sheet stops where the list does', () {
      expect(android.pinSnapZone, isNull);
    });
  });

  group('iOS geometry', () {
    test('the collapsed inset is 0.2488 of the long side, floored', () {
      expect(
        ios.collapsedTop(const Size(390, 844), const EdgeInsets.only(top: 47)),
        (844 * 0.2488).floorToDouble(),
      );
    });

    test('0.15 on a narrow screen', () {
      expect(
        ios.collapsedTop(const Size(320, 568), EdgeInsets.zero),
        (568 * 0.15).floorToDouble(),
      );
    });

    test('none in landscape', () {
      expect(ios.collapsedTop(const Size(844, 390), EdgeInsets.zero), 0);
    });

    test('radius 38, grabber 36 x 5 at 5, dim 25 %', () {
      expect(ios.cornerRadius, 38);
      expect(
        ios.grabber,
        const AttachSheetGrabber(
          size: Size(36, 5),
          top: 5,
          fadesWithHeader: false,
        ),
      );
      expect(ios.dimOpacity, 0.25);
      expect(
        ios.dimIn,
        const MotionSpec(Duration(milliseconds: 300), Curves.linear),
      );
      expect(
        ios.dimOut,
        const MotionSpec(Duration(milliseconds: 250), Curves.easeInOut),
      );
    });

    test('no corner radius in landscape', () {
      expect(ios.cornerRadiusFor(const Size(844, 390)), 0);
      expect(ios.cornerRadiusFor(const Size(390, 844)), 38);
    });

    test('the pan stops while the keyboard is up', () {
      expect(ios.panDisabledWithKeyboard, isTrue);
      expect(android.panDisabledWithKeyboard, isFalse);
    });

    test('a pan past 40 with a selection asks first', () {
      expect(ios.discardPanThreshold, 40);
      expect(android.discardPanThreshold, isNull);
      expect(ios.discardWording, AttachDiscardWording.cancelSelection);
      expect(android.discardWording, AttachDiscardWording.discardSelection);
    });
  });

  group('iOS release', () {
    const collapsed = 210.0;
    const expanded = 47.0;

    AttachSheetRelease? release(
      double top, {
      double velocity = 0,
      bool startedExpanded = false,
    }) => ios.release(
      AttachSheetReleaseInput(
        top: top,
        collapsedTop: collapsed,
        expandedTop: expanded,
        velocity: velocity,
        startedExpanded: startedExpanded,
        devicePixelRatio: 3,
      ),
    );

    test('collapsed: past 60 down dismisses', () {
      expect(release(collapsed + 61), AttachSheetRelease.dismiss);
      expect(release(collapsed + 59), AttachSheetRelease.holdCollapsed);
    });

    test('collapsed: any way down at over 300 pt/s dismisses', () {
      expect(release(collapsed + 5, velocity: 301), AttachSheetRelease.dismiss);
      expect(
        release(collapsed + 5, velocity: 299),
        AttachSheetRelease.holdCollapsed,
      );
    });

    test('collapsed: up at over 300 pt/s or past half the inset expands', () {
      expect(
        release(collapsed - 10, velocity: -301),
        AttachSheetRelease.expand,
      );
      const half = (collapsed - expanded) / 2;
      expect(release(collapsed - half - 1), AttachSheetRelease.expand);
      expect(release(collapsed - half + 1), AttachSheetRelease.holdCollapsed);
    });

    test('expanded: down at over 1800 pt/s dismisses', () {
      expect(
        release(expanded + 30, velocity: 1801, startedExpanded: true),
        AttachSheetRelease.dismiss,
      );
    });

    test(
      'expanded: down at over 300 pt/s or past half the inset collapses',
      () {
        expect(
          release(expanded + 10, velocity: 301, startedExpanded: true),
          AttachSheetRelease.collapse,
        );
        const half = (collapsed - expanded) / 2;
        expect(
          release(expanded + half + 1, startedExpanded: true),
          AttachSheetRelease.collapse,
        );
        expect(
          release(expanded + 10, startedExpanded: true),
          AttachSheetRelease.holdExpanded,
        );
      },
    );

    test('settles on springs of damping 124, dismisses on 180', () {
      expect(
        ios.settleMotion(AttachSheetRelease.expand),
        const AttachSheetMotion.spring(
          SpringDescription(mass: 5, stiffness: 900, damping: 124),
        ),
      );
      expect(
        ios.settleMotion(AttachSheetRelease.dismiss),
        const AttachSheetMotion.spring(
          SpringDescription(mass: 5, stiffness: 900, damping: 180),
        ),
      );
      expect(
        ios.settleMotion(AttachSheetRelease.holdExpanded),
        const AttachSheetMotion.timed(
          MotionSpec(Duration(milliseconds: 300), Curves.easeInOut),
        ),
      );
    });
  });

  group('iOS regular width', () {
    test('a 390 card anchored to the attach button', () {
      final card = ios.cardFor(
        const Size(1024, 768),
        EdgeInsets.zero,
        anchor: const Rect.fromLTWH(20, 700, 44, 44),
      );
      // x = min(1024 - 390 - 28, 42 - 195 - 2) = -155, kept on screen at 28.
      // height = min(670, 768); y = min(768 - 670 - 0 - 54, 700 - 670) = 30.
      expect(card, const Rect.fromLTWH(28, 30, 390, 670));
    });

    test('none on a phone', () {
      expect(
        ios.cardFor(const Size(390, 844), EdgeInsets.zero, anchor: Rect.zero),
        isNull,
      );
      expect(
        android.cardFor(
          const Size(1024, 768),
          EdgeInsets.zero,
          anchor: Rect.zero,
        ),
        isNull,
      );
    });

    test('dims to 10 % behind the card', () {
      expect(ios.cardDimOpacity, 0.1);
    });
  });

  group('forPlatform', () {
    test('Android and iOS are their own', () {
      expect(
        AttachSheetPolicy.forPlatform(TargetPlatform.android, isWeb: false),
        isA<AttachSheetPolicy$Android>(),
      );
      expect(
        AttachSheetPolicy.forPlatform(TargetPlatform.iOS, isWeb: false),
        isA<AttachSheetPolicy$IOS>(),
      );
    });
  });
}
