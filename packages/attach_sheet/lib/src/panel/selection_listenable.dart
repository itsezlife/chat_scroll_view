import 'package:attach_model/attach_model.dart';
import 'package:flutter/foundation.dart';

/// The attach selection's change signal as a Flutter [Listenable], for a
/// builder: the model signals through `package:listen`'s own type.
@internal
final class SelectionListenable implements Listenable {
  /// The signal of [selection].
  const SelectionListenable(this.selection);

  /// The selection whose changes are forwarded.
  final AttachSelection selection;

  @override
  void addListener(VoidCallback listener) =>
      selection.changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      selection.changes.removeListener(listener);
}
