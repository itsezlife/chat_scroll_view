/// Between launches: wait for the battery to cool back near the run's start.
library;

final class CooldownResult {
  const CooldownResult({required this.endTempC, required this.boundHit});

  final double endTempC;

  /// The wait ran out before the temperature came back.
  final bool boundHit;
}

Future<CooldownResult> waitForCooldown({
  required double startTempC,
  required Future<double> Function() readTempC,
  required Future<void> Function(Duration) sleep,
  Duration bound = const Duration(minutes: 10),
  Duration interval = const Duration(seconds: 30),
  double toleranceC = 2,
}) async {
  var waited = Duration.zero;
  while (true) {
    final temp = await readTempC();
    if (temp - startTempC <= toleranceC) {
      return CooldownResult(endTempC: temp, boundHit: false);
    }
    if (waited >= bound) {
      return CooldownResult(endTempC: temp, boundHit: true);
    }
    await sleep(interval);
    waited += interval;
  }
}
