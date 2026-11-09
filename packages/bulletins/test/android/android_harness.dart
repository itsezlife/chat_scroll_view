import 'package:bulletins/bulletins.dart';
import 'package:bulletins/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';

/// A surface with the Android policy mounted over it: chrome scopes, a fixed
/// size, a manual clock and an announcement recorder.
class AndroidHarness {
  AndroidHarness({
    EdgeInsets obstruction = EdgeInsets.zero,
    this.surface = const Size(400, 800),
  }) : clock = ManualBulletinClock(),
       obstruction = ValueNotifier(obstruction) {
    controller = BulletinController(
      policy: const BulletinPolicy.android(),
      clock: clock,
    );
  }

  final ManualBulletinClock clock;
  final Size surface;
  late final BulletinController controller;
  final ValueNotifier<EdgeInsets> obstruction;
  final announced = <String>[];

  Widget app({
    BulletinBuilders builders = const BulletinBuilders(),
    ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
    Widget background = const SizedBox.expand(),
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(size: surface),
      child: ChromeThemeScope(
        palette: const ChromePalette.light(),
        child: ChromeStringsScope(
          strings: ChromeStringsPresets.english,
          child: ChromeMotionScope(
            speed: speed,
            child: Center(
              child: SizedBox.fromSize(
                size: surface,
                child: BulletinHost(
                  controller: controller,
                  obstruction: obstruction,
                  builders: builders,
                  announce: (_, message) => announced.add(message),
                  child: background,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void dispose() {
    controller.dispose();
    obstruction.dispose();
  }
}
