/// The runner's effects on a real device and the host file system. Thin by
/// design: every decision lives in the pure modules beside it.
library;

import 'dart:convert';
import 'dart:io';

import 'build_fingerprint.dart';
import 'device_lock.dart';
import 'gates.dart';

const kPackage = 'com.example.chat_scroll_view_example';

final class Adb {
  const Adb(this.device);

  final String device;

  Future<String> shell(String command) async {
    final r = await Process.run(
      'adb',
      ['-s', device, 'shell', command],
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
    );
    return r.exitCode == 0 ? r.stdout as String : '';
  }

  Future<BatteryReading> battery() async =>
      parseBattery(await shell('dumpsys battery'));

  Future<String> inputMethod() async =>
      (await shell('settings get secure default_input_method')).trim();

  Future<void> clearLogcat() async {
    await Process.run('adb', ['-s', device, 'logcat', '-b', 'all', '-c']);
  }

  Future<List<String>> logcat() async {
    // Another app's log lines can hold a UTF-8 sequence cut mid-character; the
    // package-replaced scan must not die on it.
    final r = await Process.run(
      'adb',
      ['-s', device, 'logcat', '-b', 'all', '-d'],
      stdoutEncoding: const Utf8Codec(allowMalformed: true),
    );
    return const LineSplitter().convert(r.stdout as String);
  }

  /// The gate inputs, read from the device.
  Future<DeviceState> state() async {
    final attached = await attachedDevices();
    final scales = await Future.wait([
      for (final k in const [
        'window_animation_scale',
        'transition_animation_scale',
        'animator_duration_scale',
      ])
        shell('settings get global $k').then(parseScale),
    ]);
    return DeviceState(
      attachedTargets: attached.length,
      awake: parseAwake(await shell('dumpsys power')),
      unlocked: !parseKeyguardShowing(await shell('dumpsys window')),
      powered: (await battery()).powered,
      thermalStatus:
          parseThermalStatus(await shell('dumpsys thermalservice')) ?? -1,
      animationScales: scales,
    );
  }
}

/// Ids of attached, authorised devices.
Future<List<String>> attachedDevices() async {
  final r = await Process.run('adb', ['devices']);
  return [
    for (final line in const LineSplitter().convert(r.stdout as String).skip(1))
      if (line.endsWith('\tdevice')) line.split('\t').first,
  ];
}

/// Locks as directories in the system temp: `mkdir` is the atomic step.
final class DirectoryLockStore implements LockStore {
  const DirectoryLockStore();

  Directory _dir(String key) => Directory('${Directory.systemTemp.path}/$key');

  @override
  bool tryCreate(String key, String owner) {
    final dir = _dir(key);
    // `Directory.createSync` succeeds on an existing directory; `mkdir` is
    // the atomic test-and-create.
    if (Process.runSync('mkdir', [dir.path]).exitCode != 0) return false;
    File('${dir.path}/owner').writeAsStringSync(owner);
    return true;
  }

  @override
  String? owner(String key) {
    final file = File('${_dir(key).path}/owner');
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  void delete(String key) {
    final dir = _dir(key);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// The suite's own sources, the workspace `lib/` and the package manifests,
/// by path, for [buildFingerprint].
Map<String, List<int>> buildInputs() {
  const roots = [
    'integration_test/chat_perf',
    'integration_test/panel_perf',
    '../lib',
    'pubspec.yaml',
    '../pubspec.lock',
  ];
  final files = <String, List<int>>{};
  void add(File f) => files[f.path] = f.readAsBytesSync();
  for (final root in roots) {
    if (FileSystemEntity.isFileSync(root)) {
      add(File(root));
    } else {
      for (final e in Directory(root).listSync(recursive: true)) {
        if (e is File) add(e);
      }
    }
  }
  for (final e in Directory('../packages').listSync()) {
    final lib = Directory('${e.path}/lib');
    if (lib.existsSync()) {
      for (final f in lib.listSync(recursive: true)) {
        if (f is File) add(f);
      }
    }
  }
  return files;
}
