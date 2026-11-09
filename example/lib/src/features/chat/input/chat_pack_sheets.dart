import 'dart:async';

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatPreImeBackClaim;
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

/// What the feedback after a pack sheet's edits says: a title, and a line
/// under it.
typedef PackFeedback = ({String title, String info});

/// How this host shows a pack sheet and answers it: the library edit, the
/// bulletin after it, and what the sheet picks.
///
/// The sheet asks; the host applies each edit to [AppServices.library] (a
/// removal or an archiving inside the bulletin's [undoWindow], as the
/// reference client holds `toggleStickerSet` behind its Undo) and shows one
/// bulletin for the button's edits, with Undo when they took packs away.
/// The reference's bulletin durations: `Bulletin.DURATION_LONG` (2750 ms)
/// for a removal, `DURATION_SHORT` (1500 ms) for an addition.
abstract final class ChatPackSheets {
  /// How long a removal or an archiving can be taken back.
  static const Duration undoWindow = Duration(milliseconds: 2750);

  /// How long the bulletin after an addition stays.
  static const Duration addedDuration = Duration(milliseconds: 1500);

  /// The arrangement a sheet opens in on this platform: a centred box on
  /// desktop, a bottom sheet elsewhere.
  static PanelArrangement get arrangement => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => PanelArrangement.pointer,
    _ => PanelArrangement.touch,
  };

  /// Opens the sheet of [pack], of [kind], over [context]; [onPick] (null when
  /// nothing can be sent or inserted here) takes what the sheet picks. An
  /// emoji sheet opened from a custom emoji in a message shows that emoji,
  /// [previewEmoji], above it (the reference's `setPreviewEmoji`).
  static Future<void> open(
    BuildContext context, {
    required AppServices services,
    required PackId pack,
    required PackKind kind,
    ValueChanged<ContentDescriptor>? onPick,
    PanelArrangement? arrangement,
    ContentKey? previewEmoji,
  }) => _show(
    context,
    services: services,
    packs: [pack],
    kind: kind,
    onPick: onPick,
    arrangement: arrangement,
    previewEmoji: previewEmoji,
  );

  /// Opens one emoji sheet of [packs] (each once, in order) over [context]:
  /// the reference's `EmojiPacksAlert` over the packs of a message's custom
  /// emoji. [onPick] takes an emoji the sheet inserts.
  static Future<void> openEmojiPacks(
    BuildContext context, {
    required AppServices services,
    required List<PackId> packs,
    ValueChanged<ContentDescriptor>? onPick,
    PanelArrangement? arrangement,
  }) => _show(
    context,
    services: services,
    packs: packs,
    kind: PackKind.emoji,
    onPick: onPick,
    arrangement: arrangement,
  );

  static Future<void> _show(
    BuildContext context, {
    required AppServices services,
    required List<PackId> packs,
    required PackKind kind,
    required ValueChanged<ContentDescriptor>? onPick,
    required PanelArrangement? arrangement,
    ContentKey? previewEmoji,
  }) {
    // Favourites from the sheet's preview: at once, as from the panel's.
    void libraryEdit(LibraryEdit edit) => services.library.apply(edit);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final strings = ChromeStringsScope.packSheetOf(context);
    void edits(List<PackEditRequest> requests) =>
        apply(services.library, requests, strings, messenger);
    void unavailable(PackLookup _) => messenger
      ?..clearSnackBars()
      ..showSnackBar(
        _bulletin(
          Text(
            kind == PackKind.emoji
                ? strings.emojiNotFound
                : strings.stickersNotFound,
          ),
        ),
      );
    final picked = switch (onPick) {
      final pick? => (PackSheetItem item) => pick(item.item),
      null => null,
    };
    // Back closes the sheet first (with its own reverse animation): its claim
    // stacks over the panel's and is taken before a raised keyboard.
    BuildContext? sheetContext;
    final backClaim = ChatPreImeBackClaim.push(() async {
      if (services.previews.dismiss()) return true;
      if (sheetContext case final sheet? when sheet.mounted) {
        unawaited(Navigator.maybePop(sheet));
      }
      return true;
    });
    return PackSheet.show(
      context,
      arrangement: arrangement ?? ChatPackSheets.arrangement,
      builder: (sheet) {
        sheetContext = sheet;
        return switch (kind) {
          PackKind.emoji => EmojiPackSheet(
            packIds: packs,
            packs: services.packs,
            library: services.library,
            assets: services.assets,
            onEditsRequested: edits,
            onPick: picked,
            onUnavailable: unavailable,
            previewEmoji: previewEmoji,
          ),
          PackKind.stickers || PackKind.masks => StickerPackSheet(
            pack: packs.single,
            packs: services.packs,
            library: services.library,
            assets: services.assets,
            onEditsRequested: edits,
            onPick: picked,
            onUnavailable: unavailable,
            previews: services.previews,
            onLibraryEditRequested: libraryEdit,
          ),
        };
      },
    ).whenComplete(backClaim.pop);
  }

  /// Applies [requests] to [library] and shows their bulletin through
  /// [messenger], with Undo for a removal or an archiving.
  static void apply(
    ContentLibrary library,
    List<PackEditRequest> requests,
    PackSheetStrings strings,
    ScaffoldMessengerState? messenger,
  ) {
    if (requests.isEmpty) return;
    final takesAway = requests.first.edit is! LibraryEdit$InstallPack;
    final applied = [
      for (final request in requests)
        library.apply(
          request.edit,
          undoWindow: takesAway ? undoWindow : Duration.zero,
        ),
    ];
    final feedback = feedbackOf(requests, strings);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        _bulletin(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feedback.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(feedback.info),
            ],
          ),
          duration: takesAway ? undoWindow : addedDuration,
          action: takesAway
              ? SnackBarAction(
                  label: strings.undoAction,
                  onPressed: () {
                    // Each comes back to its own place: the library replays
                    // the edits still in their window.
                    for (final edit in applied.reversed) {
                      edit.undo();
                    }
                  },
                )
              : null,
        ),
      );
  }

  /// Applies [edit] of a pack nothing describes, with no bulletin to name
  /// it: a removal still keeps its undo window.
  static AppliedEdit applyAlone(ContentLibrary library, LibraryPackEdit edit) =>
      library.apply(
        edit,
        undoWindow: edit is LibraryEdit$InstallPack
            ? Duration.zero
            : undoWindow,
      );

  /// What the bulletin after [requests] says, in [strings]: the reference's
  /// `StickerSetBulletinLayout` texts by kind and by what happened.
  static PackFeedback feedbackOf(
    List<PackEditRequest> requests,
    PackSheetStrings strings,
  ) {
    final (:edit, :pack) = requests.first;
    if (requests.length > 1) {
      final count = requests.length;
      return switch (edit) {
        LibraryEdit$InstallPack() => (
          title: strings.emojiAdded,
          info: strings.emojiPacksAddedInfo(count),
        ),
        _ => (
          title: strings.emojiRemoved,
          info: strings.emojiPacksRemovedInfo(count),
        ),
      };
    }
    final title = pack.title;
    return switch ((edit, pack.kind)) {
      (LibraryEdit$InstallPack(), PackKind.stickers) => (
        title: strings.stickersAdded,
        info: strings.stickersAddedInfo(title),
      ),
      (LibraryEdit$InstallPack(), PackKind.masks) => (
        title: strings.masksAdded,
        info: strings.masksAddedInfo(title),
      ),
      (LibraryEdit$InstallPack(), PackKind.emoji) => (
        title: strings.emojiAdded,
        info: strings.emojiAddedInfo(title),
      ),
      (LibraryEdit$ArchivePack(), PackKind.stickers) => (
        title: strings.stickersArchived,
        info: strings.stickersArchivedInfo(title),
      ),
      (LibraryEdit$ArchivePack(), PackKind.masks) => (
        title: strings.masksArchived,
        info: strings.masksArchivedInfo(title),
      ),
      (LibraryEdit$ArchivePack(), PackKind.emoji) => (
        title: strings.emojiArchived,
        info: strings.emojiArchivedInfo(title),
      ),
      (LibraryEdit$RemovePack(), PackKind.stickers) => (
        title: strings.stickersRemoved,
        info: strings.stickersRemovedInfo(title),
      ),
      (LibraryEdit$RemovePack(), PackKind.masks) => (
        title: strings.masksRemoved,
        info: strings.masksRemovedInfo(title),
      ),
      (LibraryEdit$RemovePack(), PackKind.emoji) => (
        title: strings.emojiRemoved,
        info: strings.emojiRemovedInfo(title),
      ),
    };
  }

  static SnackBar _bulletin(
    Widget content, {
    Duration duration = addedDuration,
    SnackBarAction? action,
  }) => SnackBar(
    content: content,
    behavior: SnackBarBehavior.floating,
    duration: duration,
    action: action,
  );
}
