import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// An [Observable] seen as a Flutter [Listenable], to merge with the
/// controllers that are one (`Listenable.merge`, `ListenableBuilder`).
final class ObservableListenable implements Listenable {
  /// Adapts [observable].
  const ObservableListenable(this._observable);

  final Observable _observable;

  @override
  void addListener(VoidCallback listener) => _observable.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _observable.removeListener(listener);
}
