/// The row appearance of a fresh outgoing message per platform: the
/// policy's defaults, the form its resolver gives for each case, the start
/// delay of the fade and scale, and reduce motion.
///
/// **Seam:** `OutgoingAppearancePolicy` and the `OutgoingAppearance` its
/// `resolve` answers, plain values; the expected numbers are the spec's
/// table of values, not recomputed from the code.
library;

import 'package:chat_outbox/chat_outbox.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const listCurve = Cubic(0.199, 0.011, 0.279, 0.910);

  group('defaults', () {
    test('Android: a slide at the bottom, a fade and scale elsewhere', () {
      const policy = OutgoingAppearancePolicy.android();
      expect(policy.atBottom, OutgoingAppearanceForm.slideUp);
      expect(policy.offBottom, OutgoingAppearanceForm.fadeScale);
      expect(policy.fliesFromOrigin, isFalse);
      expect(policy.slideDuration, const Duration(milliseconds: 250));
      expect(policy.slideCurve, listCurve);
      expect(policy.fadeScaleDuration, const Duration(milliseconds: 250));
      expect(policy.opacityFrom, 0);
      expect(policy.scaleFrom, 0.9);
      expect(policy.maxStartDelay, const Duration(milliseconds: 100));
    });

    test('iOS: the media flies from its origin, else as Android', () {
      const policy = OutgoingAppearancePolicy.ios();
      expect(policy.fliesFromOrigin, isTrue);
      expect(policy.atBottom, OutgoingAppearanceForm.slideUp);
      expect(policy.offBottom, OutgoingAppearanceForm.fadeScale);
      expect(policy.slideDuration, const Duration(milliseconds: 250));
      expect(policy.slideCurve, listCurve);
      expect(policy.scaleFrom, 0.9);
    });

    test('desktop: no appearance', () {
      const policy = OutgoingAppearancePolicy.desktop();
      expect(policy.atBottom, OutgoingAppearanceForm.none);
      expect(policy.offBottom, OutgoingAppearanceForm.none);
      expect(policy.fliesFromOrigin, isFalse);
    });

    test('platform picks the preset of each target platform', () {
      expect(
        OutgoingAppearancePolicy.platform(TargetPlatform.android),
        const OutgoingAppearancePolicy.android(),
      );
      expect(
        OutgoingAppearancePolicy.platform(TargetPlatform.fuchsia),
        const OutgoingAppearancePolicy.android(),
      );
      expect(
        OutgoingAppearancePolicy.platform(TargetPlatform.iOS),
        const OutgoingAppearancePolicy.ios(),
      );
      for (final desktop in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          OutgoingAppearancePolicy.platform(desktop),
          const OutgoingAppearancePolicy.desktop(),
        );
      }
    });
  });

  group('resolve', () {
    OutgoingAppearance resolve(
      OutgoingAppearancePolicy policy, {
      bool atBottom = true,
      bool originPresent = false,
      bool textOnly = false,
      bool reduceMotion = false,
    }) => policy.resolve(
      atBottom: atBottom,
      originPresent: originPresent,
      textOnly: textOnly,
      reduceMotion: reduceMotion,
    );

    test('Android at the bottom slides the rows up by the added height', () {
      final form = resolve(const OutgoingAppearancePolicy.android());
      expect(
        form,
        isA<OutgoingAppearance$SlideUp>()
            .having(
              (f) => f.duration,
              'duration',
              const Duration(milliseconds: 250),
            )
            .having((f) => f.curve, 'curve', listCurve),
      );
      expect(form.form, OutgoingAppearanceForm.slideUp);
    });

    test('Android off the bottom fades and scales the bubble in', () {
      final form = resolve(
        const OutgoingAppearancePolicy.android(),
        atBottom: false,
      );
      expect(
        form,
        isA<OutgoingAppearance$FadeScale>()
            .having(
              (f) => f.duration,
              'duration',
              const Duration(milliseconds: 250),
            )
            .having((f) => f.opacityFrom, 'opacityFrom', 0)
            .having((f) => f.scaleFrom, 'scaleFrom', 0.9),
      );
      expect(form.form, OutgoingAppearanceForm.fadeScale);
    });

    test('Android ignores a send origin: no flight', () {
      expect(
        resolve(const OutgoingAppearancePolicy.android(), originPresent: true),
        isA<OutgoingAppearance$SlideUp>(),
      );
    });

    test('iOS with an origin leaves the row still: the media flies', () {
      for (final atBottom in [true, false]) {
        final form = resolve(
          const OutgoingAppearancePolicy.ios(),
          atBottom: atBottom,
          originPresent: true,
        );
        expect(form, isA<OutgoingAppearance$Flight>());
        expect(form.form, OutgoingAppearanceForm.flight);
      }
    });

    test('iOS without an origin appears as Android does', () {
      expect(
        resolve(const OutgoingAppearancePolicy.ios()),
        isA<OutgoingAppearance$SlideUp>(),
      );
      expect(
        resolve(const OutgoingAppearancePolicy.ios(), atBottom: false),
        isA<OutgoingAppearance$FadeScale>(),
      );
    });

    test('a text-only message appears as media does, never with a flight', () {
      expect(
        resolve(
          const OutgoingAppearancePolicy.ios(),
          originPresent: true,
          textOnly: true,
        ),
        isA<OutgoingAppearance$SlideUp>(),
      );
      expect(
        resolve(const OutgoingAppearancePolicy.android(), textOnly: true),
        isA<OutgoingAppearance$SlideUp>(),
      );
      expect(
        resolve(
          const OutgoingAppearancePolicy.android(),
          atBottom: false,
          textOnly: true,
        ),
        isA<OutgoingAppearance$FadeScale>(),
      );
    });

    test('desktop: none in every case', () {
      for (final atBottom in [true, false]) {
        for (final origin in [true, false]) {
          expect(
            resolve(
              const OutgoingAppearancePolicy.desktop(),
              atBottom: atBottom,
              originPresent: origin,
            ),
            isA<OutgoingAppearance$None>(),
          );
        }
      }
    });

    test('reduce motion collapses every form to none', () {
      for (final policy in const [
        OutgoingAppearancePolicy.android(),
        OutgoingAppearancePolicy.ios(),
      ]) {
        for (final atBottom in [true, false]) {
          for (final origin in [true, false]) {
            final form = resolve(
              policy,
              atBottom: atBottom,
              originPresent: origin,
              reduceMotion: true,
            );
            expect(form, isA<OutgoingAppearance$None>());
            expect(form.form, OutgoingAppearanceForm.none);
          }
        }
      }
    });
  });

  group('the fade and scale start delay', () {
    const fade = OutgoingAppearance$FadeScale(
      duration: Duration(milliseconds: 250),
      curve: Curves.linear,
      opacityFrom: 0,
      scaleFrom: 0.9,
      maxStartDelay: Duration(milliseconds: 100),
    );

    test('is (1 - bottom / listHeight) * 100 ms', () {
      expect(fade.delayAt(rowBottom: 600, listHeight: 600), Duration.zero);
      expect(
        fade.delayAt(rowBottom: 0, listHeight: 600),
        const Duration(milliseconds: 100),
      );
      expect(
        fade.delayAt(rowBottom: 450, listHeight: 600),
        const Duration(milliseconds: 25),
      );
      expect(
        fade.delayAt(rowBottom: 200, listHeight: 800),
        const Duration(milliseconds: 75),
      );
    });

    test('clamps a bottom outside the list to the list', () {
      expect(fade.delayAt(rowBottom: 900, listHeight: 600), Duration.zero);
      expect(
        fade.delayAt(rowBottom: -40, listHeight: 600),
        const Duration(milliseconds: 100),
      );
    });

    test('is none for a list of no height', () {
      expect(fade.delayAt(rowBottom: 10, listHeight: 0), Duration.zero);
    });
  });
}
