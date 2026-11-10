import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy_feedback.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_messages_copy_format.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_emoji_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/message_menu_chrome.dart';
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:content_model/content_model.dart'
    show ContentKey, LibraryEdit, PackId, RichClipboard;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Builds rows for a [ChatMessageMenuRequest] under a **selection policy**.
typedef MessageMenuItemsBuilder =
    List<ChatMessageMenuItem> Function(
      ChatMessageMenuRequest request,
      ChatSelectionPolicy policy, {
      MessageMenuContent? content,
    });

/// The sticker or GIF a message is, for the rows that act on it.
@immutable
sealed class MessageMenuContent {
  const MessageMenuContent._(this.key);

  /// A sticker: its [pack] (null when it has none) and whether that pack is
  /// installed, and whether the sticker is a favourite.
  const factory MessageMenuContent.sticker({
    required ContentKey key,
    required PackId? pack,
    required bool packInstalled,
    required bool favourite,
  }) = MessageMenuContent$Sticker;

  /// A GIF.
  const factory MessageMenuContent.gif({required ContentKey key}) =
      MessageMenuContent$Gif;

  /// The content.
  final ContentKey key;
}

/// [MessageMenuContent.sticker].
final class MessageMenuContent$Sticker extends MessageMenuContent {
  /// A sticker.
  const MessageMenuContent$Sticker({
    required ContentKey key,
    required this.pack,
    required this.packInstalled,
    required this.favourite,
  }) : super._(key);

  /// Its pack, or null.
  final PackId? pack;

  /// Whether [pack] is installed.
  final bool packInstalled;

  /// Whether the sticker is among the favourites.
  final bool favourite;
}

/// [MessageMenuContent.gif].
final class MessageMenuContent$Gif extends MessageMenuContent {
  /// A GIF.
  const MessageMenuContent$Gif({required ContentKey key}) : super._(key);
}

/// Stable action ids for [MessageMenuCatalog] rows.
///
/// String values match [ChatMessageMenuAction.id] on the package presenter.
/// Labels may change with membership / bulk vs single; **ids** stay stable
/// for [MessageMenu] dispatch and [MessageMenu.excludeActionIds].
abstract final class MessageMenuActionId {
  /// Reply to the target message.
  static const reply = 'reply';

  /// Copy message body / selected set as text (label varies).
  static const copy = 'copy';

  /// Copy the live **text selection** snapshot from the request.
  ///
  /// Desktop/web message-menu path when the host opted into secondary;
  /// mobile text chrome owns Copy instead.
  static const copySelected = 'copy_selected';

  /// Copy the URL from an inline link hit on the request.
  static const copyLink = 'copy_link';

  /// Copy the code payload from an inline code hit on the request.
  static const copyCode = 'copy_code';

  /// Pin the target message.
  static const pin = 'pin';

  /// Forward the target message or selected set (label varies).
  static const forward = 'forward';

  /// Edit the target message.
  static const edit = 'edit';

  /// Delete the target message or selected set (label varies).
  static const delete = 'delete';

  /// Enter **message selection** starting at the target.
  ///
  /// Desktop idle menu only — mobile enters selection via long-press, not a
  /// menu row.
  static const select = 'select';

  /// Extend **message selection** from the nearest selected id through
  /// [ChatMessageMenuRequest.selectUpToIds] (desktop elsewhere).
  static const selectUpTo = 'select_up_to';

  /// Clear the selected set.
  static const clearSelection = 'clear_selection';

  /// Open the packs of the message's custom emoji: the "contains emoji from
  /// N packs" entry under the actions ([MessageEmojiPacks]).
  static const emojiPacks = 'emoji_packs';

  /// Open the pack sheet of the message's sticker.
  static const viewPack = 'view_pack';

  /// Mark the message's sticker as a favourite.
  static const addFavourite = 'add_favourite';

  /// Take the message's sticker out of the favourites.
  static const removeFavourite = 'remove_favourite';

  /// Save the message's GIF.
  static const saveGif = 'save_gif';
}

/// Policy- and hit-aware row / reaction catalogs driven by a
/// [ChatMessageMenuRequest].
///
/// Branches on **selection policy** plus hit axes (**point state**,
/// **membership**, **inline hit**, **hasTextSelection**,
/// **overlapsTextSelection**, **selectUpToIds**).
///
/// | Concern | `$Mobile` | `$Desktop` |
/// |---|---|---|
/// | Idle Select row | no (long-press → selection) | yes |
/// | Outside surface | full idle rows | Select only |
/// | Membership elsewhere | reduced | Select (+ Select up to when chain) |
/// | Upon selected | bulk labels (+ Reply) | bulk labels (+ Reply) |
/// | Reaction strip | yes | no |
/// | Copy vs Copy selected | n/a on menu | see [_desktopCopyRows] |
/// | Inline link/code | Copy link / Copy code prefix | same |
abstract final class MessageMenuCatalog {
  /// Default reaction glyphs for the mobile scrim strip.
  static const List<String> mobileReactions = <String>[
    '👍',
    '❤️',
    '🔥',
    '🥰',
    '👏',
    '😁',
    '🤔',
    '🎉',
  ];

  // --- Shared row atoms ----------------------------------------------------

  static const ChatMessageMenuItem _reply = ChatMessageMenuItem(
    id: MessageMenuActionId.reply,
    label: 'Reply',
    icon: Icons.reply_outlined,
  );
  static const ChatMessageMenuItem _copy = ChatMessageMenuItem(
    id: MessageMenuActionId.copy,
    label: 'Copy',
    icon: Icons.content_copy_outlined,
  );
  static const ChatMessageMenuItem _copySelectedAsText = ChatMessageMenuItem(
    id: MessageMenuActionId.copy,
    label: 'Copy Selected as Text',
    icon: Icons.content_copy_outlined,
  );
  static const ChatMessageMenuItem _copySelectedText = ChatMessageMenuItem(
    id: MessageMenuActionId.copySelected,
    label: 'Copy Selected Text',
    icon: Icons.content_copy_outlined,
  );
  static const ChatMessageMenuItem _copyLink = ChatMessageMenuItem(
    id: MessageMenuActionId.copyLink,
    label: 'Copy link',
    icon: Icons.link_outlined,
  );
  static const ChatMessageMenuItem _copyCode = ChatMessageMenuItem(
    id: MessageMenuActionId.copyCode,
    label: 'Copy code',
    icon: Icons.code_outlined,
  );
  static const ChatMessageMenuItem _pin = ChatMessageMenuItem(
    id: MessageMenuActionId.pin,
    label: 'Pin',
    icon: Icons.push_pin_outlined,
  );
  static const ChatMessageMenuItem _forward = ChatMessageMenuItem(
    id: MessageMenuActionId.forward,
    label: 'Forward',
    icon: Icons.shortcut_outlined,
  );
  static const ChatMessageMenuItem _forwardSelected = ChatMessageMenuItem(
    id: MessageMenuActionId.forward,
    label: 'Forward Selected',
    icon: Icons.shortcut_outlined,
  );
  static const ChatMessageMenuItem _edit = ChatMessageMenuItem(
    id: MessageMenuActionId.edit,
    label: 'Edit',
    icon: Icons.edit_outlined,
  );
  static const ChatMessageMenuItem _delete = ChatMessageMenuItem(
    id: MessageMenuActionId.delete,
    label: 'Delete',
    icon: Icons.delete_outline,
  );
  static const ChatMessageMenuItem _deleteSelected = ChatMessageMenuItem(
    id: MessageMenuActionId.delete,
    label: 'Delete Selected',
    icon: Icons.delete_outline,
  );
  static const ChatMessageMenuItem _select = ChatMessageMenuItem(
    id: MessageMenuActionId.select,
    label: 'Select',
    icon: Icons.check_circle_outline,
  );
  static const ChatMessageMenuItem _selectUpTo = ChatMessageMenuItem(
    id: MessageMenuActionId.selectUpTo,
    label: 'Select up to this message',
    icon: Icons.expand_outlined,
  );
  static const ChatMessageMenuItem _clearSelection = ChatMessageMenuItem(
    id: MessageMenuActionId.clearSelection,
    label: 'Clear Selection',
    icon: Icons.deselect_outlined,
  );

  /// Reaction strip for [policy] — empty omits the strip on the presenter.
  ///
  /// `$Mobile` → [mobileReactions]; `$Desktop` → empty (reactions live
  /// outside the context popup on desktop).
  static List<String> reactionsFor(ChatSelectionPolicy policy) =>
      switch (policy) {
        ChatSelectionPolicy$Mobile() ||
        ChatSelectionPolicy$TextOnly() => mobileReactions,
        ChatSelectionPolicy$Desktop() => const <String>[],
      };

  /// Builds rows from [request] under [policy].
  ///
  /// [excludeActionIds] drops matching [ChatMessageMenuItem.id] after the
  /// catalog is built (capability / chat policy filter — no catalog fork).
  ///
  /// [content], the sticker or GIF the message is, adds its rows to the menu
  /// of the message alone, where and as [platform] (the running one by
  /// default) lists them:
  ///
  /// | | Android | iOS | desktop |
  /// |---|---|---|---|
  /// | sticker | after Copy: Add to Stickers, Add to / Delete from Favorites | first: Add to / Remove from Favorites; after Pin: View Pack | after Pin: View sticker set (Add stickers when not installed), Add to / Remove from Favorites |
  /// | GIF | after Copy: Save to GIFs | after Pin: Save GIF | after Pin: Save GIF |
  static List<ChatMessageMenuItem> itemsFor(
    ChatMessageMenuRequest request,
    ChatSelectionPolicy policy, {
    Iterable<String>? excludeActionIds,
    MessageMenuContent? content,
    TargetPlatform? platform,
  }) {
    final rows = _ContentRows(content, platform ?? defaultTargetPlatform);
    final items = switch (policy) {
      ChatSelectionPolicy$Mobile() ||
      ChatSelectionPolicy$TextOnly() => _mobileItems(request, rows),
      ChatSelectionPolicy$Desktop() => _desktopItems(request, rows),
    };
    return excluding(items, excludeActionIds);
  }

  /// Drops rows whose [ChatMessageMenuItem.id] is in [excludeActionIds].
  static List<ChatMessageMenuItem> excluding(
    List<ChatMessageMenuItem> items,
    Iterable<String>? excludeActionIds,
  ) {
    if (excludeActionIds == null) return items;
    final banned = excludeActionIds is Set<String>
        ? excludeActionIds
        : excludeActionIds.toSet();
    if (banned.isEmpty) return items;
    return [
      for (final item in items)
        if (item is! ChatMessageMenuAction || !banned.contains(item.id)) item,
    ];
  }

  static List<ChatMessageMenuItem> _inlinePrefix(
    ChatMessageMenuRequest request,
  ) => switch (request.inlineHit) {
    ChatInlineHit$Link() => const <ChatMessageMenuItem>[_copyLink],
    ChatInlineHit$Code() => const <ChatMessageMenuItem>[_copyCode],
    // Nothing to copy from a mention, a hashtag, an embed or a sticker by
    // itself.
    ChatInlineHit$Mention() ||
    ChatInlineHit$Hashtag() ||
    ChatInlineHit$Embed() ||
    ChatInlineHit$Sticker() ||
    null => const <ChatMessageMenuItem>[],
  };

  /// Desktop/web idle Inside: Copy Selected Text when upon the range;
  /// whole-message Copy when there is no live text selection on this
  /// subject; **neither** when text is selected but the press is not upon
  /// the range.
  static List<ChatMessageMenuItem> _desktopCopyRows(
    ChatMessageMenuRequest request,
  ) {
    if (request.overlapsTextSelection) {
      return const <ChatMessageMenuItem>[_copySelectedText];
    }
    if (request.hasTextSelection) {
      return const <ChatMessageMenuItem>[];
    }
    return const <ChatMessageMenuItem>[_copy];
  }

  /// Mobile scrim: full idle rows even on Outside (slot opened the menu).
  /// No Select. Text Copy stays on text chrome.
  static List<ChatMessageMenuItem> _mobileItems(
    ChatMessageMenuRequest request,
    _ContentRows content,
  ) {
    switch (request.membership) {
      case ChatMessageMenuMembership.uponSelected:
        return const <ChatMessageMenuItem>[
          _reply,
          _copySelectedAsText,
          _forwardSelected,
          _deleteSelected,
          _clearSelection,
        ];
      case ChatMessageMenuMembership.elsewhere:
        // Rare: mobile does not open the menu in selection mode.
        return <ChatMessageMenuItem>[
          ..._inlinePrefix(request),
          if (!request.hasTextSelection) _copy,
        ];
      case ChatMessageMenuMembership.idle:
        return <ChatMessageMenuItem>[
          ...content.first,
          ..._inlinePrefix(request),
          _reply,
          if (!request.hasTextSelection) _copy,
          ...content.afterCopy,
          _forward,
          _pin,
          ...content.afterPin,
          _edit,
          _delete,
        ];
    }
  }

  /// Desktop: Outside → Select; elsewhere → Select (+ up-to); upon → bulk;
  /// Inside idle → full rows with copy rules and inline prefix.
  static List<ChatMessageMenuItem> _desktopItems(
    ChatMessageMenuRequest request,
    _ContentRows content,
  ) {
    switch (request.membership) {
      case ChatMessageMenuMembership.uponSelected:
        return <ChatMessageMenuItem>[
          _reply,
          if (request.overlapsTextSelection) _copySelectedText,
          _copySelectedAsText,
          _forwardSelected,
          _deleteSelected,
          _clearSelection,
        ];
      case ChatMessageMenuMembership.elsewhere:
        return <ChatMessageMenuItem>[
          _select,
          if (request.canSelectUpTo) _selectUpTo,
        ];
      case ChatMessageMenuMembership.idle:
        if (request.pointState == ChatMessageMenuPointState.outside) {
          return const <ChatMessageMenuItem>[_select];
        }
        return <ChatMessageMenuItem>[
          ..._inlinePrefix(request),
          _reply,
          _edit,
          _pin,
          ...content.afterPin,
          ..._desktopCopyRows(request),
          _forward,
          _delete,
          _select,
        ];
    }
  }
}

// The rows of a message's sticker or GIF, in the three places a platform puts
// them.
final class _ContentRows {
  factory _ContentRows(MessageMenuContent? content, TargetPlatform platform) {
    final family = switch (platform) {
      TargetPlatform.iOS => _Family.ios,
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => _Family.desktop,
      TargetPlatform.android || TargetPlatform.fuchsia => _Family.android,
    };
    ChatMessageMenuItem row(String id, String label, IconData icon) =>
        ChatMessageMenuItem(id: id, label: label, icon: icon);
    switch (content) {
      case null:
        return const _ContentRows._();
      case MessageMenuContent$Gif():
        final save = row(MessageMenuActionId.saveGif, switch (family) {
          _Family.android => 'Save to GIFs',
          _Family.ios || _Family.desktop => 'Save GIF',
        }, Icons.gif_box_outlined);
        return switch (family) {
          _Family.android => _ContentRows._(afterCopy: [save]),
          _Family.ios || _Family.desktop => _ContentRows._(afterPin: [save]),
        };
      case MessageMenuContent$Sticker(
        :final pack,
        :final packInstalled,
        :final favourite,
      ):
        final viewPack = pack == null
            ? null
            : row(MessageMenuActionId.viewPack, switch (family) {
                _Family.android => 'Add to Stickers',
                _Family.ios => 'View Pack',
                _Family.desktop =>
                  packInstalled ? 'View sticker set' : 'Add stickers',
              }, Icons.sticky_note_2_outlined);
        final fave = favourite
            ? row(MessageMenuActionId.removeFavourite, switch (family) {
                _Family.android => 'Delete from Favorites',
                _Family.ios || _Family.desktop => 'Remove from Favorites',
              }, Icons.star_outline)
            : row(
                MessageMenuActionId.addFavourite,
                'Add to Favorites',
                Icons.star_border,
              );
        return switch (family) {
          _Family.android => _ContentRows._(afterCopy: [?viewPack, fave]),
          _Family.ios => _ContentRows._(first: [fave], afterPin: [?viewPack]),
          _Family.desktop => _ContentRows._(afterPin: [?viewPack, fave]),
        };
    }
  }

  const _ContentRows._({
    this.first = const [],
    this.afterCopy = const [],
    this.afterPin = const [],
  });

  final List<ChatMessageMenuItem> first;
  final List<ChatMessageMenuItem> afterCopy;
  final List<ChatMessageMenuItem> afterPin;
}

enum _Family { android, ios, desktop }

/// Host verbs applied when a [MessageMenu] session chooses an action.
@immutable
final class MessageMenuActions {
  /// Creates the host action bundle.
  const MessageMenuActions({
    required this.onDelete,
    required this.onEdit,
    this.onDeleteSelected,
    this.onReply,
    this.onPin,
    this.onForward,
    this.onReact,
    this.onCopy,
    this.onCopySelected,
    this.onCopyLink,
    this.onCopyCode,
    this.onEmojiPacks,
    this.onViewPack,
    this.onLibraryEdit,
    this.onNotice,
  });

  /// Delete one message.
  final ValueChanged<int> onDelete;

  /// Edit one message.
  final ValueChanged<int> onEdit;

  /// Delete the selected set (preferred over repeated [onDelete] when set).
  final ValueChanged<Iterable<int>>? onDeleteSelected;

  /// Optional reply handler; default feedback when null.
  final ValueChanged<int>? onReply;

  /// Optional pin handler; default feedback when null.
  final ValueChanged<int>? onPin;

  /// Optional forward handler; receives target id and selected ids when
  /// over-selection.
  final void Function(int messageId, List<int> selectedIds)? onForward;

  /// Optional reaction handler; default feedback when null.
  final ValueChanged<String>? onReact;

  /// After [MessageMenuActionId.copy] wrote the clipboard (message body or
  /// selected set as text). Receives the copied plain text.
  final ValueChanged<String>? onCopy;

  /// After [MessageMenuActionId.copySelected] wrote the live text-selection
  /// snapshot.
  final ValueChanged<String>? onCopySelected;

  /// After [MessageMenuActionId.copyLink] wrote the inline link URL.
  final ValueChanged<String>? onCopyLink;

  /// After [MessageMenuActionId.copyCode] wrote the inline code payload.
  final ValueChanged<String>? onCopyCode;

  /// Opens the packs of the message's custom emoji, each once, in order
  /// ([MessageMenuActionId.emojiPacks]).
  final ValueChanged<List<PackId>>? onEmojiPacks;

  /// Opens the pack of the message's sticker ([MessageMenuActionId.viewPack]).
  final ValueChanged<PackId>? onViewPack;

  /// Applies the library edit a content row asks for: a favourite added or
  /// taken away, a GIF saved.
  final ValueChanged<LibraryEdit>? onLibraryEdit;

  /// Shows what a demo row with no handler would do (a reaction, a reply, a
  /// pin, a forward): the host's bulletin. Nothing shows when null.
  final ValueChanged<String>? onNotice;
}

/// Host-owned **message menu** session.
///
/// Wire once with data source, selection, and [MessageMenuActions]. Present
/// each [ChatMessageMenuRequest] via [present] — no library-level present
/// helper. Catalog and reactions default from the bound **selection policy**.
/// Chrome stays on package [ChatMessageMenu.show].
final class MessageMenu {
  /// Creates a host message menu bound to [dataSource] and [actions].
  ///
  /// [itemsFor] defaults to [MessageMenuCatalog.itemsFor]. [reactions]
  /// `null` derives from policy via [MessageMenuCatalog.reactionsFor]; an
  /// empty list omits the strip; a non-empty list forces those reactions.
  ///
  /// [excludeActionIds] drops catalog rows by id after build (e.g. omit
  /// Reply/Forward when the chat cannot support them) without forking the
  /// presenter.
  MessageMenu({
    required this.dataSource,
    required this.actions,
    required this.clipboard,
    this.selection,
    MessageMenuItemsBuilder? itemsFor,
    List<String>? reactions,
    this.excludeActionIds,
    this.canEdit,
    this.emojiPacks,
    this.contentOf,
  }) : itemsFor = itemsFor ?? MessageMenuCatalog.itemsFor,
       _reactionsOverride = reactions;

  /// Presence + copy text source.
  final ChatDataSource dataSource;

  /// Outcome handlers for chosen rows / reactions.
  final MessageMenuActions actions;

  /// Where the copy rows write: messages and code as rich text, so a paste
  /// into the composer brings back their entities (ADR 032).
  final RichClipboard clipboard;

  /// Optional selection facade for Select / Clear / bulk membership and
  /// **selection policy** (catalog + presentation).
  final ChatSelectionController? selection;

  /// Builds rows for a request under the active policy.
  final MessageMenuItemsBuilder itemsFor;

  /// Action ids to omit from every present (capability / chat policy).
  final Iterable<String>? excludeActionIds;

  /// Whether the message with the given id may be edited, or null for every
  /// message. A message that may not be edited gets a menu without the Edit
  /// row, whatever [excludeActionIds] says: the rule is per message (a sticker
  /// has no text), where [excludeActionIds] is per chat.
  final bool Function(int messageId)? canEdit;

  /// The packs of a message's custom emoji, offered under the actions of a
  /// message that is not part of a selection; null offers none.
  final MessageEmojiPacks? emojiPacks;

  /// The sticker or GIF the message with the given id is, or null; null
  /// offers no content rows.
  final MessageMenuContent? Function(int messageId)? contentOf;

  final List<String>? _reactionsOverride;

  var _sessionOpen = false;

  /// Whether a session is currently presenting.
  bool get isPresenting => _sessionOpen;

  /// **Selection policy** used for catalog, reactions, and presentation.
  ChatSelectionPolicy get selectionPolicy =>
      selection?.selectionPolicy ?? ChatSelectionPolicy.forPlatform();

  /// Opens a **message menu session** for [request].
  ///
  /// Rows and reactions follow [selectionPolicy]. Does not clear membership
  /// or text selection on open. Silent when a session is already open.
  Future<void> present(
    BuildContext context,
    ChatMessageMenuRequest request,
  ) async {
    if (_sessionOpen) return;
    _sessionOpen = true;
    try {
      final policy = selectionPolicy;
      final selectedSnapshot = request.overSelection
          ? (selection?.selectedIds.toList(growable: false) ?? const <int>[])
          : const <int>[];
      final reactions =
          _reactionsOverride ?? MessageMenuCatalog.reactionsFor(policy);
      final packs = _emojiPacksFor(request, policy);
      final content = request.membership == ChatMessageMenuMembership.idle
          ? contentOf?.call(request.messageId)
          : null;
      final presentation = ChatMessageMenuPresentation.forPolicy(policy);
      final surfaceBuilder = MessageMenuChrome.surfaceBuilderFor(presentation);

      final result = await ChatMessageMenu.show(
        context: context,
        messageRect: request.slotGlobal,
        tapGlobal: request.tapGlobal,
        surfaceRect: request.surfaceGlobal,
        surfaceShape: request.surfaceShape,
        visibleRect: request.bandGlobal,
        items: MessageMenuCatalog.excluding(
          itemsFor(request, policy, content: content),
          switch (canEdit) {
            final canEdit? when !canEdit(request.messageId) => [
              ...?excludeActionIds,
              MessageMenuActionId.edit,
            ],
            _ => excludeActionIds,
          },
        ),
        reactions: reactions,
        selectionPolicy: policy,
        menuBuilder: switch ((packs, emojiPacks)) {
          ([_, ...], final emojiPacks?) => (context, slots) => _WithEmojiPacks(
            slots: slots,
            button: MessageContainsEmojiButton(
              packs: packs,
              source: emojiPacks.source,
              onTap: () => slots.onSelectItem(MessageMenuActionId.emojiPacks),
              surfaceBuilder: surfaceBuilder,
            ),
          ),
          _ => null,
        },
        // The chrome's rows, surface and appear motion, as every other menu
        // and overlay of the app moves (MessageMenuChrome).
        itemBuilder: MessageMenuChrome.itemBuilderFor(presentation),
        surfaceBuilder: surfaceBuilder,
        transitionBuilder: MessageMenuChrome.transition,
        presence: _ChatDataSourceListenable(dataSource),
        isPresent: () => dataSource.getMessage(request.messageId) != null,
      );
      if (!context.mounted || result == null) return;
      await _dispatch(
        context: context,
        request: request,
        result: result,
        selectedSnapshot: selectedSnapshot,
        emojiPacks: packs,
        content: content,
      );
    } finally {
      _sessionOpen = false;
    }
  }

  Future<void> _dispatch({
    required BuildContext context,
    required ChatMessageMenuRequest request,
    required ChatMessageMenuResult result,
    required List<int> selectedSnapshot,
    required List<PackId> emojiPacks,
    required MessageMenuContent? content,
  }) async {
    switch (result) {
      case ChatMessageMenuReactionResult(:final reaction):
        if (actions.onReact case final onReact?) {
          onReact(reaction);
          return;
        }
        actions.onNotice?.call('Reacted $reaction');
      case ChatMessageMenuItemResult(:final itemId):
        switch (itemId) {
          case MessageMenuActionId.copySelected:
            final text = request.selectedTextSnapshot;
            if (text == null || text.isEmpty) return;
            // The live selection with its spans; its plain snapshot when the
            // selection has gone since the menu opened.
            await clipboard.write(switch (selection?.textSelectionContent()) {
              final content? => ChatCopy.selection(content),
              null => model.RichText.plain(text),
            });
            ChatCopyFeedback.endSelection(selection);
            actions.onCopySelected?.call(text);
          case MessageMenuActionId.copyLink:
            final hit = request.inlineHit;
            if (hit is! ChatInlineHit$Link) return;
            await clipboard.write(model.RichText.plain(hit.url));
            actions.onCopyLink?.call(hit.url);
          case MessageMenuActionId.copyCode:
            final hit = request.inlineHit;
            if (hit is! ChatInlineHit$Code) return;
            await clipboard.write(ChatCopy.code(hit.code));
            actions.onCopyCode?.call(hit.code);
          case MessageMenuActionId.copy:
            final ids = request.overSelection
                ? selectedSnapshot
                : [request.messageId];
            final copied = ChatMessagesCopyFormat.forPolicy(
              selectionPolicy,
            ).compose(ChatCopiedMessage.of(ids, dataSource));
            if (copied.isEmpty) return;
            await clipboard.write(copied);
            if (request.overSelection) ChatCopyFeedback.endSelection(selection);
            actions.onCopy?.call(copied.plain);
          case MessageMenuActionId.delete:
            if (request.overSelection) {
              if (actions.onDeleteSelected case final deleteSelected?) {
                deleteSelected(selectedSnapshot);
              } else {
                selectedSnapshot.forEach(actions.onDelete);
              }
              selection?.clear();
              return;
            }
            actions.onDelete(request.messageId);
          case MessageMenuActionId.edit:
            actions.onEdit(request.messageId);
          case MessageMenuActionId.select:
            selection?.startSelection(request.messageId);
          case MessageMenuActionId.selectUpTo:
            final chain = request.selectUpToIds;
            if (chain == null || chain.isEmpty || selection == null) return;
            selection!.replaceSelectedIds({
              ...selection!.selectedIds,
              ...chain,
            });
          case MessageMenuActionId.emojiPacks:
            actions.onEmojiPacks?.call(emojiPacks);
          case MessageMenuActionId.viewPack:
            if (content case MessageMenuContent$Sticker(:final pack?)) {
              actions.onViewPack?.call(pack);
            }
          case MessageMenuActionId.addFavourite:
            if (content case MessageMenuContent$Sticker(:final key)) {
              actions.onLibraryEdit?.call(LibraryEdit.favouriteSticker(key));
            }
          case MessageMenuActionId.removeFavourite:
            if (content case MessageMenuContent$Sticker(:final key)) {
              actions.onLibraryEdit?.call(LibraryEdit.unfavouriteSticker(key));
            }
          case MessageMenuActionId.saveGif:
            if (content case MessageMenuContent$Gif(:final key)) {
              actions.onLibraryEdit?.call(LibraryEdit.saveGif(key));
            }
          case MessageMenuActionId.clearSelection:
            selection?.clear();
          case MessageMenuActionId.reply:
            if (actions.onReply case final onReply?) {
              onReply(request.messageId);
              return;
            }
            actions.onNotice?.call(MessageMenuActionId.reply);
          case MessageMenuActionId.pin:
            if (actions.onPin case final onPin?) {
              onPin(request.messageId);
              return;
            }
            actions.onNotice?.call(MessageMenuActionId.pin);
          case MessageMenuActionId.forward:
            if (actions.onForward case final onForward?) {
              onForward(request.messageId, selectedSnapshot);
              return;
            }
            actions.onNotice?.call(
              request.overSelection
                  ? 'forward ${selectedSnapshot.length}'
                  : MessageMenuActionId.forward,
            );
          default:
            return;
        }
    }
  }

  // Offered on the message alone: the button is built only for the menu of
  // one message, not over a selection, and not beside the
  // bubble on desktop, where the menu is Select alone.
  List<PackId> _emojiPacksFor(
    ChatMessageMenuRequest request,
    ChatSelectionPolicy policy,
  ) {
    final emojiPacks = this.emojiPacks;
    if (emojiPacks == null ||
        request.membership != ChatMessageMenuMembership.idle) {
      return const [];
    }
    return switch ((request.pointState, policy)) {
      (ChatMessageMenuPointState.outside, ChatSelectionPolicy$Desktop()) =>
        const [],
      _ => emojiPacks.of(request.messageId),
    };
  }
}

/// Forwards [ChatDataSource] data notifications as a [Listenable].
final class _ChatDataSourceListenable implements Listenable {
  const _ChatDataSourceListenable(this.dataSource);

  final ChatDataSource dataSource;

  @override
  void addListener(VoidCallback listener) =>
      dataSource.addDataListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      dataSource.removeDataListener(listener);
}

/// The default menu column with the contains-emoji entry under the action
/// card, 8 px apart.
///
/// As wide as the column: the entry wraps its text to the card's width and
/// does not widen the menu.
class _WithEmojiPacks extends StatelessWidget {
  const _WithEmojiPacks({required this.slots, required this.button});

  final ChatMessageMenuSlots slots;
  final Widget button;

  @override
  Widget build(BuildContext context) => IntrinsicWidth(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChatMessageMenuColumn(slots: slots),
        const SizedBox(height: 8),
        _NoIntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.only(
              left: ChatMessageMenuReactions.startOverhang,
              right: ChatMessageMenuReactions.endOverhang,
            ),
            child: button,
          ),
        ),
      ],
    ),
  );
}

/// Reports no intrinsic width, so [child] takes the width the others set.
class _NoIntrinsicWidth extends SingleChildRenderObjectWidget {
  const _NoIntrinsicWidth({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNoIntrinsicWidth();
}

class _RenderNoIntrinsicWidth extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;
}
