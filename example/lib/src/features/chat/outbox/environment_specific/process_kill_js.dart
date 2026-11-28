import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The web has no process to kill: a reload drops the page's state the
/// same way, keeping only what was already stored.
void $killProcess() => globalContext
    .getProperty<JSObject>('location'.toJS)
    .callMethod<JSAny?>('reload'.toJS);
