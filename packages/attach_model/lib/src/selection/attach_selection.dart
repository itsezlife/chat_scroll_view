import 'package:attach_model/src/item/attach_item.dart';
import 'package:attach_model/src/item/attach_limits.dart';
import 'package:attach_model/src/policy/attach_policy.dart';
import 'package:attach_model/src/send/send_plan.dart';
import 'package:content_model/content_model.dart';
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

  /// The item is a file of no bytes.
  emptyFile,
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
///
/// It also holds the captions: the shared [caption] (the sheet's field) and
/// each item's own, related by the policy's [AttachPolicy.itemCaptions].
/// [captionOf] is what the picker viewer shows for an item and
/// [setCaptionOf] what it writes; [itemsToSend] are the items with their
/// own captions on. A caption change signals [captionChanges], not
/// [changes].
final class AttachSelection with ChangeNotifier {
  /// An empty selection under [policy] and [limits].
  AttachSelection({required this.policy, required this.limits});

  /// The rules for the cap.
  final AttachPolicy policy;

  /// The host's limits for this open.
  final AttachLimits limits;

  final List<AttachItem> _$items = [];
  RichText _$caption = RichText.empty;
  final Map<AttachItemId, RichText> _$captions = {};
  final ChangeNotifier _$captionChanges = ChangeNotifier();

  /// Signals once after every change of the items (not of their captions).
  Listenable get changes => this;

  // --- Captions ---

  /// Signals once after every change of a caption, shared or an item's.
  Listenable get captionChanges => _$captionChanges;

  ItemCaptions get _rule => policy.itemCaptions;

  /// The shared caption: the sheet's field.
  RichText get caption => _$caption;
  set caption(RichText value) {
    if (value == _$caption) return;
    _$caption = value;
    _$captionChanges.notifyListeners();
  }

  /// The item [id]'s own caption, apart from the shared one; null for none.
  RichText? ownCaptionOf(AttachItemId id) => _$captions[id];

  /// Whether another item than the first has a caption of its own: under
  /// [ItemCaptions.firstItem], the viewer no longer shows the shared
  /// caption on every item.
  bool get captionsPerItem => switch (_rule) {
    ItemCaptions.sharedOnly => false,
    ItemCaptions.forced => _$caption.isEmpty && _$captions.isNotEmpty,
    ItemCaptions.firstItem =>
      _$items.skip(1).any((item) => _$captions.containsKey(item.id)),
  };

  /// The caption the picker viewer shows for the item [id], selected or not.
  RichText captionOf(AttachItemId id) => switch (_rule) {
    ItemCaptions.sharedOnly => _$caption,
    ItemCaptions.forced when !_$caption.isEmpty => _$caption,
    ItemCaptions.forced => _$captions[id] ?? RichText.empty,
    ItemCaptions.firstItem when _isFirst(id) => _$caption,
    ItemCaptions.firstItem when !captionsPerItem => _$caption,
    ItemCaptions.firstItem => _$captions[id] ?? RichText.empty,
  };

  /// Writes [text] as [item]'s caption from the picker viewer, by the
  /// policy's rule: the shared caption, or the item's own (see
  /// [ItemCaptions]). Under [ItemCaptions.firstItem] a non-empty caption on
  /// an item not selected selects it first; one the selection refuses is
  /// dropped.
  void setCaptionOf(AttachItem item, RichText text) {
    switch (_rule) {
      case ItemCaptions.sharedOnly:
        caption = text;
      case ItemCaptions.forced when !_$caption.isEmpty:
        caption = text;
      case ItemCaptions.forced:
        _setOwn(item.id, text);
      case ItemCaptions.firstItem:
        if (!contains(item.id)) {
          if (text.isEmpty) return;
          if (!toggle(item).changesSelection) return;
        }
        if (_isFirst(item.id)) {
          caption = text;
        } else if (!captionsPerItem && text == _$caption) {
          return;
        } else {
          _setOwn(item.id, text);
        }
    }
  }

  /// The items in selection order with their own captions on
  /// ([AttachItem.caption]), for a send request.
  List<AttachItem> get itemsToSend => [
    for (final item in _$items)
      switch (_$captions[item.id]) {
        final own? => item.copyWith(caption: own),
        null when item.caption != null => item.copyWith(clearCaption: true),
        null => item,
      },
  ];

  bool _isFirst(AttachItemId id) =>
      _$items.isNotEmpty && _$items.first.id == id;

  void _setOwn(AttachItemId id, RichText text) {
    final had = _$captions[id];
    if (text.isEmpty) {
      if (_$captions.remove(id) == null) return;
    } else {
      if (had == text) return;
      _$captions[id] = text;
    }
    _$captionChanges.notifyListeners();
  }

  /// Under [ItemCaptions.firstItem] each caption stays with its item when
  /// the first item changes: the one left first takes the shared caption as
  /// its own when it is still selected, and the new first item's own becomes
  /// the shared one. A first item deselected keeps the shared caption on
  /// the field unless the new first item has its own.
  void _firstChanged(AttachItemId? before, {required bool moved}) {
    if (_rule != ItemCaptions.firstItem) return;
    final after = _$items.isEmpty ? null : _$items.first.id;
    if (after == before) return;
    var next = _$caption;
    if (before != null && moved && contains(before)) {
      if (!_$caption.isEmpty) _$captions[before] = _$caption;
      next = RichText.empty;
    }
    if (after != null) {
      if (_$captions.remove(after) case final own?) next = own;
    }
    if (next != _$caption) _$caption = next;
    _$captionChanges.notifyListeners();
  }

  /// Drops the own captions of items no longer selected, under
  /// [ItemCaptions.firstItem]: deselecting clears an item's caption.
  void _dropDeselected() {
    if (_rule != ItemCaptions.firstItem) return;
    final selected = {for (final item in _$items) item.id};
    final before = _$captions.length;
    _$captions.removeWhere((id, _) => !selected.contains(id));
    if (_$captions.length != before) _$captionChanges.notifyListeners();
  }

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

  /// Why [item] could not join now, or null when it could (or is already
  /// selected). What a picker reads to dim an item it would refuse.
  AttachRefusal? refusalOf(AttachItem item) {
    if (contains(item.id)) return null;
    if (!limits.allows(item.kind)) return AttachRefusal.kindNotAllowed;
    if (item.facts.byteSize == 0) return AttachRefusal.emptyFile;
    if ((limits.fileSizeLimit, item.facts.byteSize) case (
      final limit?,
      final size?,
    ) when size > limit) {
      return AttachRefusal.fileTooLarge;
    }
    if (limits.singleSelect) return null;
    if (cap case final cap? when _$items.length >= cap) {
      return AttachRefusal.capReached;
    }
    return null;
  }

  /// Selects [item], or deselects it when it is already selected.
  ///
  /// Under single select, selecting replaces the selected item.
  AttachToggle toggle(AttachItem item) {
    final first = _firstId;
    final result = _toggle(item, select: !contains(item.id));
    if (result.changesSelection) {
      _afterChange(first);
      notifyListeners();
    }
    return result;
  }

  /// Selects [item] ahead of everything selected (a capture joins first),
  /// under the same cap and gates as [toggle]; an item already selected
  /// moves to the front.
  AttachToggle selectFirst(AttachItem item) {
    final index = _indexOf(item.id);
    if (index >= 0) {
      if (index > 0) {
        final first = _firstId;
        _$items.insert(0, _$items.removeAt(index));
        _firstChanged(first, moved: true);
        notifyListeners();
      }
      return const AttachToggle.selected();
    }
    if (refusalOf(item) case final reason?) return AttachToggle.refused(reason);
    if (limits.singleSelect) _$items.clear();
    _$items.insert(0, item);
    notifyListeners();
    return const AttachToggle.selected();
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
    final first = _firstId;
    final results = [for (final item in list) _toggle(item, select: select)];
    if (results.any((r) => r.changesSelection)) {
      _afterChange(first);
      notifyListeners();
    }
    return results;
  }

  /// Deselects [id]; nothing when it is not selected.
  void remove(AttachItemId id) {
    final index = _indexOf(id);
    if (index < 0) return;
    final first = _firstId;
    _$items.removeAt(index);
    _afterChange(first);
    notifyListeners();
  }

  /// Moves the item at [from] to [to], both indexes into [items] before the
  /// move. The item keeps its per-item state.
  void reorder(int from, int to) {
    RangeError.checkValidIndex(from, _$items, 'from');
    RangeError.checkValidIndex(to, _$items, 'to');
    if (from == to) return;
    final first = _firstId;
    _$items.insert(to, _$items.removeAt(from));
    _firstChanged(first, moved: true);
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
    _dropDeselected();
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
    _dropDeselected();
    notifyListeners();
  }

  // --- Machinery ---

  AttachItemId? get _firstId => _$items.isEmpty ? null : _$items.first.id;

  // A change of membership: deselected items lose their captions, and a
  // first item that left hands the shared caption on. An item added first
  // (a capture) takes the shared caption over, as the field shows it.
  void _afterChange(AttachItemId? first) {
    final stillThere = first != null && contains(first);
    _dropDeselected();
    if (!stillThere) _firstChanged(first, moved: false);
  }

  int _indexOf(AttachItemId id) => _$items.indexWhere((item) => item.id == id);

  /// Applies one toggle without signalling.
  AttachToggle _toggle(AttachItem item, {required bool select}) {
    final index = _indexOf(item.id);
    if (!select) {
      if (index >= 0) _$items.removeAt(index);
      return const AttachToggle.deselected();
    }
    if (index >= 0) return const AttachToggle.selected();
    if (refusalOf(item) case final reason?) return AttachToggle.refused(reason);
    if (limits.singleSelect) _$items.clear();
    _$items.add(item);
    return const AttachToggle.selected();
  }
}
