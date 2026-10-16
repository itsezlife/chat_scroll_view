import 'package:content_model/content_model.dart';
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
  ValueObservable<ImeSample> get samples;

  /// Feeds a raw reading in. Ignored after [dispose].
  void report(ImeSample sample);

  /// Drops every listener. Idempotent.
  void dispose();
}

/// The port a host creates and feeds.
final class ImeInput implements ImeInputPort {
  final _samples = ObservableValue<ImeSample>(ImeSample.hidden);

  @override
  ValueObservable<ImeSample> get samples => _samples;

  @override
  void report(ImeSample sample) {
    if (_samples.isDisposed) return;
    _samples.value = sample;
  }

  @override
  void dispose() => _samples.dispose();
}
