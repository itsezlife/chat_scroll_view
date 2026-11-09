import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// One library edit a pack sheet asks the host for, with the pack it is
/// about: the host applies [edit] and names [pack] in its feedback.
typedef PackEditRequest = ({LibraryPackEdit edit, Pack pack});

/// Asked to apply [requests] together: one button's worth of edits, which the
/// host applies (with its undo window for a removal or an archiving) and
/// confirms with one piece of feedback.
typedef PackEditsRequested = void Function(List<PackEditRequest> requests);

/// What the bottom button of a pack sheet does for the packs it shows:
///
/// | Packs shown | Install states | Button |
/// | --- | --- | --- |
/// | one | not installed, archived | add it ("Add 20 stickers") |
/// | one | installed, official | archive it, worded as a removal |
/// | one | installed | remove it ("Remove 20 stickers") |
/// | several | any not installed | add those ("Add 2 emoji packs"; one left says its emoji) |
/// | several | all installed | remove them all ("Remove 2 emoji packs") |
///
/// A value of the packs and states it was built from: a sheet builds a new
/// one whenever either changes.
@immutable
final class PackSheetAction {
  const PackSheetAction._(this.requests, {required this.removes});

  /// The action for [packs], whose install states [stateOf] answers, or null
  /// for no pack (nothing to offer).
  static PackSheetAction? of(
    List<Pack> packs,
    PackInstallState Function(PackId id) stateOf,
  ) {
    if (packs.isEmpty) return null;
    if (packs case [final pack]) {
      return switch (stateOf(pack.id)) {
        PackInstallState.notInstalled ||
        PackInstallState.archived => PackSheetAction._([
          (edit: LibraryEdit$InstallPack(pack.id, pack.kind), pack: pack),
        ], removes: false),
        // An official pack is archived where any other is removed, and both
        // are worded as a removal.
        PackInstallState.installed => PackSheetAction._([
          (
            edit: pack.official
                ? LibraryEdit$ArchivePack(pack.id, pack.kind)
                : LibraryEdit$RemovePack(pack.id, pack.kind),
            pack: pack,
          ),
        ], removes: true),
      };
    }
    final toAdd = [
      for (final pack in packs)
        if (stateOf(pack.id) != PackInstallState.installed) pack,
    ];
    if (toAdd.isNotEmpty) {
      return PackSheetAction._([
        for (final pack in toAdd)
          (edit: LibraryEdit$InstallPack(pack.id, pack.kind), pack: pack),
      ], removes: false);
    }
    // `removeMultipleStickerSets`: removed, not archived, official or not.
    return PackSheetAction._([
      for (final pack in packs)
        (edit: LibraryEdit$RemovePack(pack.id, pack.kind), pack: pack),
    ], removes: true);
  }

  /// The edits the button asks for, in the packs' order.
  final List<PackEditRequest> requests;

  /// Whether the button takes packs away (drawn as a flat attention-coloured
  /// button) rather than adds them (a filled one).
  final bool removes;

  /// The button's words in [strings].
  String labelIn(PackSheetStrings strings) {
    if (requests case [(:final pack, edit: _)]) {
      final count = pack.count;
      return switch ((pack.kind, removes)) {
        (PackKind.stickers, false) => strings.addStickers(count),
        (PackKind.stickers, true) => strings.removeStickers(count),
        (PackKind.masks, false) => strings.addMasks(count),
        (PackKind.masks, true) => strings.removeMasks(count),
        (PackKind.emoji, false) => strings.addEmoji(count),
        (PackKind.emoji, true) => strings.removeEmoji(count),
      };
    }
    return removes
        ? strings.removeEmojiPacks(requests.length)
        : strings.addEmojiPacks(requests.length);
  }

  @override
  bool operator ==(Object other) =>
      other is PackSheetAction &&
      other.removes == removes &&
      _sameRequests(other.requests, requests);

  @override
  int get hashCode => Object.hash(removes, Object.hashAll(requests));

  static bool _sameRequests(List<PackEditRequest> a, List<PackEditRequest> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() =>
      'PackSheetAction(${removes ? 'remove' : 'add'} ${requests.length})';
}
