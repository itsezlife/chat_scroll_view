import 'package:flutter_test/flutter_test.dart';

import '../../tool/chat_perf/dependency_stamp.dart';
import '../../tool/chat_perf/gates.dart';
import '../../tool/chat_perf/perf_mode.dart';

const _battery = '''
Current Battery Service state:
  AC powered: false
  USB powered: true
  Wireless powered: false
  level: 72
  scale: 100
  temperature: 340
''';

DeviceState _ok({
  int attached = 1,
  bool awake = true,
  bool unlocked = true,
  bool powered = true,
  int thermal = 0,
  List<double> scales = const [1, 1, 1],
}) => DeviceState(
  attachedTargets: attached,
  awake: awake,
  unlocked: unlocked,
  powered: powered,
  thermalStatus: thermal,
  animationScales: scales,
);

void main() {
  group('gates', () {
    test('a healthy device passes', () {
      expect(evaluateGates(_ok()), isEmpty);
    });

    test('each failing gate is named in its own message', () {
      expect(
        evaluateGates(_ok(attached: 0)).single,
        allOf(contains('device'), contains('0')),
      );
      expect(evaluateGates(_ok(attached: 2)).single, contains('device'));
      expect(evaluateGates(_ok(awake: false)).single, contains('awake'));
      expect(evaluateGates(_ok(unlocked: false)).single, contains('unlocked'));
      expect(evaluateGates(_ok(powered: false)).single, contains('power'));
      expect(evaluateGates(_ok(thermal: 2)).single, contains('thermal'));
      expect(
        evaluateGates(_ok(scales: const [1, 0.5, 1])).single,
        contains('animation'),
      );
    });

    test('every failure is reported, not only the first', () {
      expect(evaluateGates(_ok(awake: false, thermal: 1)), hasLength(2));
    });
  });

  group('parsers', () {
    test('battery reading', () {
      final b = parseBattery(_battery);
      expect(b.level, 72);
      expect(b.temperatureC, 34.0);
      expect(b.powered, isTrue);
    });

    test('battery on no power', () {
      final b = parseBattery(
        _battery.replaceAll('USB powered: true', 'USB powered: false'),
      );
      expect(b.powered, isFalse);
    });

    test('thermal status, wakefulness, keyguard, scale', () {
      expect(parseThermalStatus('  Thermal Status: 3\n'), 3);
      expect(parseThermalStatus('nothing'), isNull);
      expect(parseAwake('  mWakefulness=Awake\n'), isTrue);
      expect(parseAwake('  mWakefulness=Asleep\n'), isFalse);
      expect(parseKeyguardShowing('    isKeyguardShowing=false'), isFalse);
      expect(parseKeyguardShowing('    isKeyguardShowing=true'), isTrue);
      expect(parseScale('1.0\n'), 1.0);
      expect(parseScale('null\n'), 1.0, reason: 'unset means the default 1.0');
    });
  });

  group('dependency stamp', () {
    const lock = '''
packages:
  flutter_md:
    dependency: "direct main"
    description:
      path: "../md"
      relative: true
    source: path
    version: "0.8.1"
  other_git:
    dependency: transitive
    description:
      resolved-ref: abc123
      url: "https://example.com/x.git"
    source: git
    version: "1.2.3"
''';

    test('reads a path entry and a git entry', () {
      final md = parseLockEntry(lock, 'flutter_md')!;
      expect((md.version, md.source, md.location), ('0.8.1', 'path', '../md'));
      expect(md.revision, isNull);
      final git = parseLockEntry(lock, 'other_git')!;
      expect((git.version, git.revision), ('1.2.3', 'abc123'));
      expect(git.toJson()['location'], 'https://example.com/x.git');
      expect(parseLockEntry(lock, 'missing'), isNull);
    });

    test('names the commit HEAD points at', () {
      expect(
        parseHeadRevision('ref: refs/heads/main\n', (r) => 'c0ffee\n'),
        'c0ffee',
      );
      expect(parseHeadRevision('deadbeef\n', (_) => null), 'deadbeef');
      expect(parseHeadRevision('ref: refs/heads/x', (_) => null), isNull);
    });
  });

  group('PerfMode.parse', () {
    test('defaults to fixed, accepts both names, rejects others', () {
      expect(PerfMode.parse(''), PerfMode.fixed);
      expect(PerfMode.parse('system'), PerfMode.system);
      expect(() => PerfMode.parse('turbo'), throwsFormatException);
    });
  });
}
