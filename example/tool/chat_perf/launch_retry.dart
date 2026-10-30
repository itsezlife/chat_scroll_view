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

/// Package-manager lines in [logcat] that install or replace [package].
int countInstallEvents(Iterable<String> logcat, String package) => logcat
    .where(
      (l) =>
          RegExp(
            'Replacing package:|Adding package|PACKAGE_REPLACED|'
            'PACKAGE_ADDED',
          ).hasMatch(l) &&
          l.contains(package),
    )
    .length;

/// The runner's own install (by `flutter drive`) leaves one event; any more
/// came from another adb client.
bool hasForeignInstall(Iterable<String> logcat, String package) =>
    countInstallEvents(logcat, package) > 1;
