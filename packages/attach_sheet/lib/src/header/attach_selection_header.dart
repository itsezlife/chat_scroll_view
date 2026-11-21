import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/src/policy/attach_selection_header_style.dart';
import 'package:flutter/foundation.dart';

/// What the selection header shows, apart from the pinned bar.
enum AttachSelectionHeaderPhase {
  /// Nothing selected.
  empty,

  /// Something selected: "N photos selected".
  selected,

  /// The selected-items preview in the grid's place.
  previewing,
}

/// What the selection holds, for the header's words.
enum AttachSelectionKinds {
  /// Nothing.
  none,

  /// Photos (and anything that is not a video).
  photos,

  /// Videos only.
  videos,

  /// Videos and other items together.
  media,
}

/// One state of the selection header, for any skin to draw.
@immutable
final class AttachSelectionHeaderValue {
  /// A state.
  const AttachSelectionHeaderValue({
    required this.count,
    required this.kinds,
    required this.previewing,
    required this.pinned,
    required this.canOpenPreview,
    required this.switching,
  });

  /// Nothing selected, nothing shown.
  static const AttachSelectionHeaderValue initial = AttachSelectionHeaderValue(
    count: 0,
    kinds: AttachSelectionKinds.none,
    previewing: false,
    pinned: false,
    canOpenPreview: false,
    switching: false,
  );

  /// How many items are selected.
  final int count;

  /// What they are.
  final AttachSelectionKinds kinds;

  /// Whether the selected-items preview shows.
  final bool previewing;

  /// Whether the sheet is at its top, where the pinned bar shows (the album
  /// switcher, the close button, the menu).
  final bool pinned;

  /// Whether a toggle would open the preview now.
  final bool canOpenPreview;

  /// Whether the switch between the grid and the preview is still moving:
  /// a toggle meanwhile does nothing.
  final bool switching;

  /// The header's phase.
  AttachSelectionHeaderPhase get phase => previewing
      ? AttachSelectionHeaderPhase.previewing
      : count == 0
      ? AttachSelectionHeaderPhase.empty
      : AttachSelectionHeaderPhase.selected;

  @override
  bool operator ==(Object other) =>
      other is AttachSelectionHeaderValue &&
      other.count == count &&
      other.kinds == kinds &&
      other.previewing == previewing &&
      other.pinned == pinned &&
      other.canOpenPreview == canOpenPreview &&
      other.switching == switching;

  @override
  int get hashCode =>
      Object.hash(count, kinds, previewing, pinned, canOpenPreview, switching);

  @override
  String toString() =>
      'AttachSelectionHeaderValue($phase, $count $kinds, pinned: $pinned, '
      'canOpenPreview: $canOpenPreview, switching: $switching)';
}

/// The selection header's behaviour, with no widgets: the header's state
/// (nothing selected, "N selected", the preview, the pinned bar) from the
/// selection and the sheet, and the preview toggle with its guard.
///
/// The sheet's own header is one skin over it; a host draws its own by
/// listening to [value] and calling [togglePreview] and [closePreview]. A
/// skin that animates the grid and preview swap ([AttachSelectionHeaderStyle.
/// previewSwitch]) calls [switchSettled] when the swap rests; until then a
/// toggle is ignored, so a burst of taps is one switch.
final class AttachSelectionHeaderController extends ChangeNotifier
    implements ValueListenable<AttachSelectionHeaderValue> {
  /// The header over [selection], by [style]'s rules.
  AttachSelectionHeaderController({
    required this.selection,
    required this.style,
  }) {
    selection.addListener(_update);
    _update();
  }

  /// The selection the header counts.
  final AttachSelection selection;

  /// The rules: whether the preview exists and from how many picks.
  final AttachSelectionHeaderStyle style;

  AttachSelectionHeaderValue _value = AttachSelectionHeaderValue.initial;
  bool _previewHosted = false;
  bool _previewing = false;
  bool _pinned = false;
  bool _switching = false;

  @override
  AttachSelectionHeaderValue get value => _value;

  /// Whether a page that shows the preview is there (the Gallery); without
  /// one the preview does not open.
  bool get previewHosted => _previewHosted;
  set previewHosted(bool value) {
    if (_previewHosted == value) return;
    _previewHosted = value;
    if (!value) _previewing = false;
    _update();
  }

  /// The sheet is at its top ([value] true) or not: the pinned bar's flag.
  set pinned(bool value) {
    if (_pinned == value) return;
    _pinned = value;
    _update();
  }

  /// Opens the preview, or goes back from it. False when it did nothing:
  /// the preview cannot open, or the last switch still moves.
  bool togglePreview() {
    if (_switching) return false;
    if (!_previewing && !_value.canOpenPreview) return false;
    _previewing = !_previewing;
    _switching = style.previewSwitch != null;
    _update();
    return true;
  }

  /// Goes back from the preview (back, the close button); false when it was
  /// not showing.
  bool closePreview() {
    if (!_previewing) return false;
    _previewing = false;
    _switching = style.previewSwitch != null;
    _update();
    return true;
  }

  /// Back (the system's, or the pinned bar's close): true when the header
  /// took it. A switch still moving takes it and does nothing more, so a
  /// burst of presses never runs past the preview into a close; the
  /// preview goes back to the grid.
  bool handleBack() => _switching || closePreview();

  /// The skin's swap between the grid and the preview came to rest.
  void switchSettled() {
    if (!_switching) return;
    _switching = false;
    _update();
  }

  void _update() {
    final items = selection.items;
    final count = items.length;
    if (count == 0) _previewing = false;
    var videos = 0;
    for (final item in items) {
      if (item.kind == AttachKind.video) videos++;
    }
    final kinds = count == 0
        ? AttachSelectionKinds.none
        : videos == count
        ? AttachSelectionKinds.videos
        : videos > 0
        ? AttachSelectionKinds.media
        : AttachSelectionKinds.photos;
    final next = AttachSelectionHeaderValue(
      count: count,
      kinds: kinds,
      previewing: _previewing,
      pinned: _pinned,
      canOpenPreview:
          style.previewEnabled && _previewHosted && count >= style.previewFrom,
      switching: _switching,
    );
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    selection.removeListener(_update);
    super.dispose();
  }
}
