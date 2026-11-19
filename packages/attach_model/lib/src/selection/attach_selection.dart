import 'package:attach_model/src/item/attach_item.dart';
import 'package:attach_model/src/item/attach_limits.dart';
import 'package:attach_model/src/policy/attach_policy.dart';
import 'package:listen/listen.dart';
import 'package:meta/meta.dart';

/// Why the attach selection refused to take an item.
enum AttachRefusal {
  /// The selection already holds its cap.
  capReached,

  /// The attach limits forbid the item's kind.
  kindNotAllowed,

  /// The item is over the attach limits' file size limit.
  fileTooLarge,
}

/// The outcome of one toggle of the attach selection.
///
/// A refusal is a value, not an exception: the picker raises it to the host
/// as an attach interaction (a bulletin, a haptic) and the selection is left
/// as it was.
@immutable
sealed class AttachToggle {
  const AttachToggle._();

  /// The item joined the selection.
  const factory AttachToggle.selected() = AttachToggle$Selected;

  /// The item left the selection.
  const factory AttachToggle.deselected() = AttachToggle$Deselected;

  /// The item could not join, for [reason].
  const factory AttachToggle.refused(AttachRefusal reason) =
      AttachToggle$Refused;

  /// Whether the selection took the toggle (selected or deselected).
  bool get changesSelection => switch (this) {
    AttachToggle$Selected() || AttachToggle$Deselected() => true,
    AttachToggle$Refused() => false,
  };
}

/// [AttachToggle.selected].
final class AttachToggle$Selected extends AttachToggle {
  /// The item joined.
  const AttachToggle$Selected() : super._();

  @override
  bool operator ==(Object other) => other is AttachToggle$Selected;

  @override
  int get hashCode => (AttachToggle$Selected).hashCode;

  @override
  String toString() => 'AttachToggle.selected()';
}

/// [AttachToggle.deselected].
final class AttachToggle$Deselected extends AttachToggle {
  /// The item left.
  const AttachToggle$Deselected() : super._();

  @override
  bool operator ==(Object other) => other is AttachToggle$Deselected;

  @override
  int get hashCode => (AttachToggle$Deselected).hashCode;

  @override
  String toString() => 'AttachToggle.deselected()';
}

/// [AttachToggle.refused].
final class AttachToggle$Refused extends AttachToggle {
  /// The item was refused for [reason].
  const AttachToggle$Refused(this.reason) : super._();

  /// Why it was refused.
  final AttachRefusal reason;

  @override
  bool operator ==(Object other) =>
      other is AttachToggle$Refused && other.reason == reason;

  @override
  int get hashCode => Object.hash(AttachToggle$Refused, reason);

  @override
  String toString() => 'AttachToggle.refused(${reason.name})';
}

/// A frozen copy of the attach selection, for an undo or to reopen with.
///
/// Items keep their order and their per-item state. A snapshot that names
/// one item twice keeps the first occurrence when restored.
@immutable
final class AttachSelectionSnapshot {
  /// A snapshot of [items], in order.
  AttachSelectionSnapshot(Iterable<AttachItem> items)
    : items = List.unmodifiable(items);

  /// The items, in selection order.
  final List<AttachItem> items;
}

/// The **attach selection**: the ordered list of attach items the user is
/// about to send.
///
/// Order is selection order and gives each item its 1-based **order
/// number**. The cap is the policy's ([AttachPolicy.selectionCap]; 1 under
/// single select) and the gates are the attach limits' (kind, file size); a
/// toggle past either is refused with a reason and changes nothing. Every
/// change signals [changes] once.
///
/// One selection serves every source of one open (library picks, captures,
/// files), so they share one set of order numbers.
final class AttachSelection with ChangeNotifier {
  /// An empty selection under [policy] and [limits].
  AttachSelection({required this.policy, required this.limits});

  /// The rules for the cap.
  final AttachPolicy policy;

  /// The host's limits for this open.
  final AttachLimits limits;

  final List<AttachItem> _$items = [];

  /// Signals once after every change.
  Listenable get changes => this;

  /// The most items the selection takes; null for no cap.
  int? get cap => limits.singleSelect ? 1 : policy.selectionCap;

  /// The items, in selection order. Unmodifiable.
  List<AttachItem> get items => List.unmodifiable(_$items);

  /// How many items are selected.
  int get length => _$items.length;

  /// Whether nothing is selected.
  bool get isEmpty => _$items.isEmpty;

  /// Whether something is selected.
  bool get isNotEmpty => _$items.isNotEmpty;

  /// Whether the item [id] is selected.
  bool contains(AttachItemId id) => _indexOf(id) >= 0;

  /// The 1-based order number of [id], or null when it is not selected.
  int? orderOf(AttachItemId id) {
    final index = _indexOf(id);
    return index < 0 ? null : index + 1;
  }

  /// Selects [item], or deselects it when it is already selected.
  ///
  /// Under single select, selecting replaces the selected item.
  AttachToggle toggle(AttachItem item) {
    final result = _toggle(item, select: !contains(item.id));
    if (result.changesSelection) notifyListeners();
    return result;
  }

  /// Toggles every item of [items] to the state the first one takes: when
  /// the first is not selected, every item is selected (those already
  /// selected stay); when it is, every item is deselected. Signals once.
  ///
  /// The result has one entry per item, in order; items that already had
  /// the state report it again.
  List<AttachToggle> toggleRange(Iterable<AttachItem> items) {
    final list = items.toList();
    if (list.isEmpty) return const [];
    final select = !contains(list.first.id);
    final results = [for (final item in list) _toggle(item, select: select)];
    if (results.any((r) => r.changesSelection)) notifyListeners();
    return results;
  }

  /// Deselects [id]; nothing when it is not selected.
  void remove(AttachItemId id) {
    final index = _indexOf(id);
    if (index < 0) return;
    _$items.removeAt(index);
    notifyListeners();
  }

  /// Moves the item at [from] to [to], both indexes into [items] before the
  /// move. The item keeps its per-item state.
  void reorder(int from, int to) {
    RangeError.checkValidIndex(from, _$items, 'from');
    RangeError.checkValidIndex(to, _$items, 'to');
    if (from == to) return;
    _$items.insert(to, _$items.removeAt(from));
    notifyListeners();
  }

  /// Replaces the selected item [id] with what [change] makes of it (its
  /// spoiler, timer, caption, edits). The id must not change. Nothing when
  /// [id] is not selected.
  void update(AttachItemId id, AttachItem Function(AttachItem item) change) {
    final index = _indexOf(id);
    if (index < 0) return;
    final next = change(_$items[index]);
    if (next.id != id) {
      throw ArgumentError.value(next.id, 'change', 'must keep the item id $id');
    }
    if (next == _$items[index]) return;
    _$items[index] = next;
    notifyListeners();
  }

  /// Deselects everything.
  void clear() {
    if (_$items.isEmpty) return;
    _$items.clear();
    notifyListeners();
  }

  /// A frozen copy of the selection.
  AttachSelectionSnapshot snapshot() => AttachSelectionSnapshot(_$items);

  /// Replaces the selection with [snapshot]'s items, keeping the first
  /// occurrence of an item named twice. The cap and gates are not applied:
  /// a snapshot is a selection that was already accepted.
  void restore(AttachSelectionSnapshot snapshot) {
    final seen = <AttachItemId>{};
    _$items
      ..clear()
      ..addAll(snapshot.items.where((item) => seen.add(item.id)));
    notifyListeners();
  }

  // --- Machinery ---

  int _indexOf(AttachItemId id) => _$items.indexWhere((item) => item.id == id);

  /// Applies one toggle without signalling.
  AttachToggle _toggle(AttachItem item, {required bool select}) {
    final index = _indexOf(item.id);
    if (!select) {
      if (index >= 0) _$items.removeAt(index);
      return const AttachToggle.deselected();
    }
    if (index >= 0) return const AttachToggle.selected();
    if (!limits.allows(item.kind)) {
      return const AttachToggle.refused(AttachRefusal.kindNotAllowed);
    }
    if ((limits.fileSizeLimit, item.facts.byteSize) case (
      final limit?,
      final size?,
    ) when size > limit) {
      return const AttachToggle.refused(AttachRefusal.fileTooLarge);
    }
    if (limits.singleSelect) {
      _$items
        ..clear()
        ..add(item);
      return const AttachToggle.selected();
    }
    if (cap case final cap? when _$items.length >= cap) {
      return const AttachToggle.refused(AttachRefusal.capReached);
    }
    _$items.add(item);
    return const AttachToggle.selected();
  }
}
