import 'package:flutter/foundation.dart';
import 'package:listen/listen.dart' as listen;

/// Routes what `package:listen` reports to [FlutterError.reportError], once,
/// at startup.
///
/// The packages never set [listen.Listenable.onError]: its default rethrows,
/// which aborts a notification at the first listener that throws and leaves
/// the notifier's dispatch state behind, so one faulty listener would starve
/// the rest. The host owns the policy. Here an error is reported (to the log
/// and whatever [FlutterError.onError] the app installed) and not rethrown,
/// so every other listener still runs and the code that changed the state is
/// not interrupted. Misuse assertions (a notifier used after it was disposed)
/// take the same road.
void reportListenerErrors() {
  listen.Listenable.onError = (error, stackTrace, context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'package:listen',
        context: ErrorDescription(switch (context) {
          listen.ErrorContext.listener => 'while notifying a listener',
          listen.ErrorContext.assertion => 'while checking a notifier',
        }),
      ),
    );
  };
}
