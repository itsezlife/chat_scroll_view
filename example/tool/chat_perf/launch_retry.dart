/// A launch that a foreign package install killed is discarded and retried
/// once; a second one fails the run (spec 9).
library;

final class ForeignInstallException implements Exception {
  const ForeignInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class RetryResult<T> {
  const RetryResult(this.value, this.discarded);

  /// The surviving launch's result.
  final T value;

  /// Launches thrown away for a foreign install.
  final int discarded;
}

Future<RetryResult<T>> runWithRetry<T>({
  required Future<T> Function() launch,
  required Future<bool> Function() foreignInstall,
}) async {
  var discarded = 0;
  while (true) {
    final value = await launch();
    if (!await foreignInstall()) return RetryResult(value, discarded);
    discarded++;
    if (discarded > 1) {
      throw const ForeignInstallException(
        'the app package was replaced by a foreign install during two '
        'launches in a row; the phone is not exclusive',
      );
    }
  }
}

/// Separate installs of [package] in [logcat]. One install makes the whole
/// system log it (every broadcast receiver, within a moment), so the lines are
/// grouped: install lines less than [gap] apart are one install.
int countInstallEvents(
  Iterable<String> logcat,
  String package, {
  Duration gap = const Duration(seconds: 5),
}) {
  final stamp = RegExp(r'^\d\d-\d\d (\d\d):(\d\d):(\d\d)\.(\d\d\d)');
  final install = RegExp('PACKAGE_(ADDED|REPLACED)');
  var installs = 0;
  Duration? last;
  for (final line in logcat) {
    if (!line.contains(package) || !install.hasMatch(line)) continue;
    final m = stamp.firstMatch(line);
    if (m == null) continue;
    final at = Duration(
      hours: int.parse(m[1]!),
      minutes: int.parse(m[2]!),
      seconds: int.parse(m[3]!),
      milliseconds: int.parse(m[4]!),
    );
    if (last == null || at - last > gap) installs++;
    last = at;
  }
  return installs;
}

/// The runner's own install (by `flutter drive`) is one install; any more came
/// from another adb client.
bool hasForeignInstall(Iterable<String> logcat, String package) =>
    countInstallEvents(logcat, package) > 1;
