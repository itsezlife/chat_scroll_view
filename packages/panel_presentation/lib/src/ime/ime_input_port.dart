import 'package:listen/listen.dart';
import 'package:panel_presentation/src/ime/ime_sample.dart';

/// The **IME input port**: the one place raw soft-keyboard samples enter the
/// presentation, and what a strategy reads them from.
///
/// The presentation reads no platform insets itself; the host forwards
/// `MediaQuery` view insets, or a keyboard-insets package, through [report].
/// A strategy that cares (keyboard replacement) subscribes to [samples]; the
/// others never look.
abstract interface class ImeInputPort {
  /// The latest sample; [ImeSample.hidden] before the first report.
  ///
  /// Signals once per report that differs from the previous one.
  ValueListenable<ImeSample> get samples;

  /// Feeds a raw reading in. Ignored after [dispose].
  void report(ImeSample sample);

  /// Drops every listener. Idempotent.
  void dispose();
}

/// The port a host creates and feeds.
final class ImeInput implements ImeInputPort {
  final _samples = ValueNotifier<ImeSample>(ImeSample.hidden);
  var _disposed = false;

  @override
  ValueListenable<ImeSample> get samples => _samples;

  @override
  void report(ImeSample sample) {
    if (_disposed) return;
    _samples.value = sample;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _samples.dispose();
  }
}
