import 'dart:io';

/// Ends the process at once, as the system kills an app: no exit handlers
/// and no flush, so only what was already written survives.
void $killProcess() => Process.killPid(pid, ProcessSignal.sigkill);
