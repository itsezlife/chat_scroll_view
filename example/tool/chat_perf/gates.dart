/// Preconditions of a launch (spec 9): what the device must look like, and the
/// parsers for the `adb shell` text that says so. Pure Dart.
library;

/// What the runner observed about the device before a launch.
final class DeviceState {
  const DeviceState({
    required this.attachedTargets,
    required this.awake,
    required this.unlocked,
    required this.powered,
    required this.thermalStatus,
    required this.animationScales,
  });

  /// Devices attached that the run could target.
  final int attachedTargets;
  final bool awake;
  final bool unlocked;

  /// Charger or USB power connected.
  final bool powered;

  /// `Thermal Status` from the thermal service; 0 is none.
  final int thermalStatus;

  /// Window, transition and animator duration scales.
  final List<double> animationScales;
}

/// One message per failing gate, each naming the gate; empty when the device
/// can give meaningful numbers.
List<String> evaluateGates(DeviceState s) => [
  if (s.attachedTargets != 1)
    'device: exactly one target device must be attached, '
        'found ${s.attachedTargets}',
  if (!s.awake) 'awake: the screen must be awake',
  if (!s.unlocked) 'unlocked: the device must be unlocked',
  if (!s.powered) 'power: charger or USB power must be connected',
  if (s.thermalStatus != 0)
    'thermal: thermal status must be 0, is ${s.thermalStatus}',
  if (s.animationScales.any((v) => v != 1.0))
    'animation: window, transition and animator scales must be 1.0, '
        'are ${s.animationScales.join(', ')}',
];

/// Battery as `dumpsys battery` reports it.
final class BatteryReading {
  const BatteryReading({
    required this.level,
    required this.temperatureC,
    required this.powered,
  });

  final int level;
  final double temperatureC;
  final bool powered;

  Map<String, Object?> toJson() => {
    'level': level,
    'temperatureC': temperatureC,
  };
}

BatteryReading parseBattery(String dumpsysBattery) {
  String? field(String name) => RegExp(
    '^\\s*$name: *(.+)\$',
    multiLine: true,
  ).firstMatch(dumpsysBattery)?.group(1)?.trim();
  bool on(String name) => field(name) == 'true';
  return BatteryReading(
    level: int.tryParse(field('level') ?? '') ?? -1,
    // Tenths of a degree.
    temperatureC: (int.tryParse(field('temperature') ?? '') ?? 0) / 10,
    powered: on('AC powered') || on('USB powered') || on('Wireless powered'),
  );
}

int? parseThermalStatus(String dumpsysThermal) => int.tryParse(
  RegExp(r'Thermal Status: *(\d+)').firstMatch(dumpsysThermal)?.group(1) ?? '',
);

bool parseAwake(String dumpsysPower) =>
    RegExp('mWakefulness=Awake').hasMatch(dumpsysPower);

bool parseKeyguardShowing(String dumpsysWindow) =>
    RegExp('isKeyguardShowing=true').hasMatch(dumpsysWindow);

/// A `settings get` scale; an unset key means the platform default 1.0.
double parseScale(String settingsValue) =>
    double.tryParse(settingsValue.trim()) ?? 1.0;
