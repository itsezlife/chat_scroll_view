import 'package:attach_sheet/attach_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

import 'sheet_rig.dart';

// Regenerate with `scripts/goldens --update` (baselines are the CI runner's).
// The collapsed sheet over the host's screen: scrim, corners, grabber and the
// resting height per platform family.
void main() {
  useGoldenBaselines('test/sheet/attach_sheet_golden_test.dart');

  final families = <String, AttachSheetPolicy>{
    'android': const AttachSheetPolicy.android(),
    'ios': const AttachSheetPolicy.ios(),
  };

  for (final MapEntry(key: name, value: policy) in families.entries) {
    testWidgets('collapsed $name', (tester) async {
      await SheetRig.open(
        tester,
        policy: policy,
        size: const Size(390, 844),
        padding: const EdgeInsets.only(top: 47),
        devicePixelRatio: 1,
        bottomBar: const SizedBox(
          height: 70,
          child: ColoredBox(color: Color(0xFF3A7BD5)),
        ),
      );
      await expectLater(
        find.byType(AttachSheet),
        matchesGoldenFile('goldens/attach_sheet_collapsed_$name.png'),
      );
    });
  }
}
