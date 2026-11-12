import 'dart:async';

import 'package:bulletins/bulletins.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatPreImeBackClaim;
import 'package:chat_scroll_view_example/src/app/app_platform_policy.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_confirm_box.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_sheet_bulletins.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_bulletins.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:panel_pages/panel_pages.dart';

/// What the feedback after a pack sheet's edits says: a title, and a line
/// under it.
typedef PackFeedback = ({String title, String info});

/// How this host shows a pack sheet and answers it: the library edit, the
/// bulletin after it, and what the sheet picks.
///
/// The sheet asks; the host applies each edit to [AppServices.library] and
/// shows one bulletin for the button's edits, with Undo when they took packs
/// away. A bulletin raised while the sheet is up shows over the sheet, above
/// its bottom bar ([ChatSheetBulletins]); one raised as it closes (the
/// button's) on the chat, through the chat's `BulletinController`. The bulletin's layout: the pack's
/// cover leads it, a removal or an archiving
/// stays [BulletinDuration.long] (2750 ms) and an addition
/// [BulletinDuration.short] (1500 ms).
abstract final class ChatPackSheets {
  /// The library's undo window of a removal or an archiving: only a guard
  /// (ADR 045, *Undo window*). The bulletin ends the window, committing the
  /// edits when it leaves by anything but Undo; this is comfortably longer
  /// than the bulletin can stay (its timeout and a press that holds it).
  static const Duration undoGuard = Duration(seconds: 30);

  /// The bulletin after [applied], a favourite, recent or saved GIF edit,
  /// or null when [platform] (this app's when null) shows none: every one
  /// where it says library edits, and elsewhere only a full list that
  /// replaced its oldest where it says those.
  static Bulletin? libraryEditBulletin(
    AppliedEdit applied, {
    required LibraryLimits limits,
    required BulletinController? bulletins,
    AppPlatformPolicy? platform,
  }) {
    final policy = platform ?? AppPlatformPolicy.current();
    final shows =
        bulletins != null &&
        (policy.saysLibraryEdits ||
            (policy.saysListReplacements && applied.evicted != null));
    if (!shows) return null;
    return ChatBulletins.ofLibraryEdit(
      applied,
      limits: limits,
      strings: ChatBulletinStrings.demo,
    );
  }

  /// Whether [requests] take packs away (a removal or an archiving).
  static bool takesAway(List<PackEditRequest> requests) => switch (requests) {
    [(edit: LibraryEdit$InstallPack(), pack: _), ...] || [] => false,
    _ => true,
  };

  /// The box that asks before [requests] take packs away, naming their
  /// packs by title.
  static ChatConfirmBox confirmBoxOf(
    List<PackEditRequest> requests, {
    ChatConfirmStrings strings = ChatConfirmStrings.demo,
  }) => ChatConfirmBox(
    question: strings.removePack(
      requests.map((request) => request.pack.title).join(', '),
    ),
    confirm: strings.removeAction,
    cancel: strings.cancelAction,
  );

  /// Opens the sheet of [pack], of [kind], over [context]; [onPick] (null when
  /// nothing can be sent or inserted here) takes what the sheet picks, and
  /// [onCopy] what an emoji sheet's preview copies. An
  /// emoji sheet opened from a custom emoji in a message shows that emoji,
  /// [previewEmoji], above it.
  static Future<void> open(
    BuildContext context, {
    required AppServices services,
    required BulletinController? bulletins,
    required PackId pack,
    required PackKind kind,
    ValueChanged<ContentDescriptor>? onPick,
    ValueChanged<ContentDescriptor>? onCopy,
    AppPlatformPolicy? platform,
    ContentKey? previewEmoji,
  }) => _show(
    context,
    services: services,
    bulletins: bulletins,
    packs: [pack],
    kind: kind,
    onPick: onPick,
    onCopy: onCopy,
    platform: platform ?? AppPlatformPolicy.current(),
    previewEmoji: previewEmoji,
  );

  /// Opens one emoji sheet of [packs] (each once, in order) over [context]:
  /// the packs of a message's custom emoji. [onPick] takes an emoji the sheet
  /// inserts, and [onCopy] one its preview copies.
  static Future<void> openEmojiPacks(
    BuildContext context, {
    required AppServices services,
    required BulletinController? bulletins,
    required List<PackId> packs,
    ValueChanged<ContentDescriptor>? onPick,
    ValueChanged<ContentDescriptor>? onCopy,
    AppPlatformPolicy? platform,
  }) => _show(
    context,
    services: services,
    bulletins: bulletins,
    packs: packs,
    kind: PackKind.emoji,
    onPick: onPick,
    onCopy: onCopy,
    platform: platform ?? AppPlatformPolicy.current(),
  );

  static Future<void> _show(
    BuildContext context, {
    required AppServices services,
    required BulletinController? bulletins,
    required List<PackId> packs,
    required PackKind kind,
    required ValueChanged<ContentDescriptor>? onPick,
    required AppPlatformPolicy platform,
    ValueChanged<ContentDescriptor>? onCopy,
    ContentKey? previewEmoji,
  }) {
    // A bulletin raised while the sheet is up shows over it, above its
    // bottom bar; one raised as it closes (the button's edit) on the screen.
    final sheetBulletins = ChatSheetBulletins(bulletins);
    // Favourites from the sheet's preview: at once, as from the panel's, and
    // shown at once by the panel under the sheet, with their bulletin.
    void libraryEdit(LibraryEdit edit) {
      final applied = services.libraryShown.apply(edit);
      final target = sheetBulletins.target;
      if (libraryEditBulletin(
            applied,
            limits: services.library.limits,
            bulletins: target,
            platform: platform,
          )
          case final bulletin?) {
        target?.show(bulletin);
      }
    }

    final strings = ChromeStringsScope.packSheetOf(context);
    BuildContext? sheetContext;
    // Under a pointer a removal asks first, in a box that takes the pack
    // box's place on its layer. Cancelled, the pack box comes back;
    // confirmed, the layer closes with both and the pack is removed.
    void edits(List<PackEditRequest> requests) {
      final sheet = sheetContext;
      if (platform.confirmsPackRemovals &&
          takesAway(requests) &&
          sheet != null &&
          sheet.mounted) {
        ChromeBoxLayer.of(sheet).show<bool>((_) => confirmBoxOf(requests)).then(
          (confirmed) {
            if (confirmed ?? false) {
              apply(
                services.library,
                requests,
                strings,
                sheetBulletins.target,
                platform: platform,
              );
            }
          },
        ).ignore();
        return;
      }
      apply(
        services.library,
        requests,
        strings,
        sheetBulletins.target,
        platform: platform,
      );
    }

    // A pack that cannot be found is said in an error bulletin, on the screen
    // the sheet closes back to.
    void unavailable(PackLookup _) => bulletins?.show(
      ChatBulletins.error(
        kind == PackKind.emoji
            ? strings.emojiNotFound
            : strings.stickersNotFound,
      ),
    );
    final picked = switch (onPick) {
      final pick? => (PackSheetItem item) => pick(item.item),
      null => null,
    };
    // Back closes the sheet first (with its own reverse animation): its claim
    // stacks over the panel's and is taken before a raised keyboard.
    final backClaim = ChatPreImeBackClaim.push(() async {
      if (services.previews.dismiss()) return true;
      if (sheetContext case final sheet? when sheet.mounted) {
        unawaited(Navigator.maybePop(sheet));
      }
      return true;
    });
    return PackSheet.show(
      context,
      arrangement: platform.packSheetArrangement,
      layer: sheetBulletins.layer,
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
            previews: services.previews,
            onCopyRequested: switch (onCopy) {
              final copy? => (item) => copy(item.item),
              null => null,
            },
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
  /// [bulletins], with Undo for a removal or an archiving.
  ///
  /// A removal is held for as long as its bulletin shows Undo: the
  /// bulletin's commit on leave commits the edits (timed out, replaced by
  /// another, swiped away, the chat gone), and Undo takes them back. The
  /// library's own window, [undoGuard], is only a bound. With no [bulletins],
  /// or where [platform] (this app's when null) says no library edits, there
  /// is no Undo, and the edits commit at once.
  static void apply(
    ContentLibrary library,
    List<PackEditRequest> requests,
    PackSheetStrings strings,
    BulletinController? bulletins, {
    AppPlatformPolicy? platform,
  }) {
    if (requests.isEmpty) return;
    // Where no bulletin says it, a removal holds no Undo: it is done once
    // confirmed.
    if (bulletins == null ||
        !(platform ?? AppPlatformPolicy.current()).saysLibraryEdits) {
      for (final request in requests) {
        library.apply(request.edit, undoWindow: Duration.zero);
      }
      return;
    }
    final takesAway = ChatPackSheets.takesAway(requests);
    final applied = [
      for (final request in requests)
        library.apply(
          request.edit,
          undoWindow: takesAway ? undoGuard : Duration.zero,
        ),
    ];
    final feedback = feedbackOf(requests, strings);
    final pack = requests.first.pack;
    bulletins.show(
      Bulletin(
        title: feedback.title,
        message: feedback.info,
        leading: switch (pack.cover ?? pack.items.firstOrNull?.key) {
          final cover? => BulletinLeading.thumbnail(cover),
          null => null,
        },
        duration: takesAway ? BulletinDuration.long : BulletinDuration.short,
        action: takesAway
            ? BulletinAction.undo(
                // Each comes back to its own place: the library replays the
                // edits still in their window.
                onUndo: () {
                  for (final edit in applied.reversed) {
                    edit.undo();
                  }
                },
                // An edit already undone ignores its commit.
                onCommit: () {
                  for (final edit in applied) {
                    edit.commit();
                  }
                },
              )
            : null,
      ),
    );
  }

  // Nothing shows Undo for it: the window of the bulletin.
  static const Duration _aloneWindow = Duration(milliseconds: 2750);

  /// Applies [edit] of a pack nothing describes, with no bulletin to name
  /// it: a removal still keeps its undo window.
  static AppliedEdit applyAlone(ContentLibrary library, LibraryPackEdit edit) =>
      library.apply(
        edit,
        undoWindow: edit is LibraryEdit$InstallPack
            ? Duration.zero
            : _aloneWindow,
      );

  /// What the bulletin after [requests] says, in [strings]: its texts by kind
  /// and by what happened.
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
}
