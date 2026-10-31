import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/chat_perf_test.dart' show allScenarios;
import '../../integration_test/chat_perf/scenario_index.dart';

void main() {
  test('the runner index lists the registry, in order, with cold flags', () {
    expect(scenarioIndex, [
      for (final s in allScenarios.all) (id: s.id, cold: s.cold),
    ]);
  });

  test('the runner lists the scenarios of the traced pass', () {
    expect(tracedScenarioIds, [
      for (final s in allScenarios.all)
        if (s.traced) s.id,
    ]);
  });

  test('selecting by filter agrees with the registry', () {
    for (final filter in [
      '',
      'scroll.*',
      'kbd.open_tail,panel.*',
      'nav.jump*',
    ]) {
      for (final cold in [false, true]) {
        expect(
          [
            for (final s in selectScenarios(scenarioIndex, filter, cold: cold))
              s.id,
          ],
          [for (final s in allScenarios.where(filter, cold: cold)) s.id],
          reason: 'filter "$filter" cold $cold',
        );
      }
    }
  });
}
