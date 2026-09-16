import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Builds rows for a [ChatMessageMenuRequest] under a **selection policy**.
typedef MessageMenuItemsBuilder =
    List<ChatMessageMenuItem> Function(
      ChatMessageMenuRequest request,
      ChatSelectionPolicy policy,
    );

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
        ChatSelectionPolicy$Mobile() => mobileReactions,
        ChatSelectionPolicy$Desktop() => const <String>[],
      };

  /// Builds rows from [request] under [policy].
  ///
  /// [excludeActionIds] drops matching [ChatMessageMenuItem.id] after the
  /// catalog is built (capability / chat policy filter — no catalog fork).
  static List<ChatMessageMenuItem> itemsFor(
    ChatMessageMenuRequest request,
    ChatSelectionPolicy policy, {
    Iterable<String>? excludeActionIds,
  }) {
    final items = switch (policy) {
      ChatSelectionPolicy$Mobile() => _mobileItems(request),
      ChatSelectionPolicy$Desktop() => _desktopItems(request),
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
        if (item is! ChatMessageMenuAction || !banned.contains(item.id))
          item,
    ];
  }

  static List<ChatMessageMenuItem> _inlinePrefix(
    ChatMessageMenuRequest request,
  ) => switch (request.inlineHit) {
    ChatInlineHit$Link() => const <ChatMessageMenuItem>[_copyLink],
    ChatInlineHit$Code() => const <ChatMessageMenuItem>[_copyCode],
    null => const <ChatMessageMenuItem>[],
  };

  /// Desktop/web idle Inside: Copy Selected Text when upon the range;
  /// whole-message Copy when there is no live text selection on this
  /// subject; **neither** when text is selected but the press is not upon
  /// the range (Telegram `isUponSelected == -1`).
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
          ..._inlinePrefix(request),
          _reply,
          if (!request.hasTextSelection) _copy,
          _forward,
          _pin,
          _edit,
          _delete,
        ];
    }
  }

  /// Desktop: Outside → Select; elsewhere → Select (+ up-to); upon → bulk;
  /// Inside idle → full rows with copy rules and inline prefix.
  static List<ChatMessageMenuItem> _desktopItems(
    ChatMessageMenuRequest request,
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
          ..._desktopCopyRows(request),
          _forward,
          _delete,
          _select,
        ];
    }
  }
}

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
}

/// Host-owned **message menu** session.
///
/// Wire once with data source, selection, and [MessageMenuActions]. Present
/// each [ChatMessageMenuRequest] via [present] — no library-level present
/// helper. Catalog and reactions default from the bound **selection policy**.
/// Chrome stays on package [showChatMessageMenu].
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
    this.selection,
    MessageMenuItemsBuilder? itemsFor,
    List<String>? reactions,
    this.excludeActionIds,
  }) : itemsFor = itemsFor ?? MessageMenuCatalog.itemsFor,
       _reactionsOverride = reactions;

  /// Presence + copy text source.
  final ChatDataSource dataSource;

  /// Outcome handlers for chosen rows / reactions.
  final MessageMenuActions actions;

  /// Optional selection facade for Select / Clear / bulk membership and
  /// **selection policy** (catalog + presentation).
  final ChatSelectionController? selection;

  /// Builds rows for a request under the active policy.
  final MessageMenuItemsBuilder itemsFor;

  /// Action ids to omit from every present (capability / chat policy).
  final Iterable<String>? excludeActionIds;

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

      final result = await showChatMessageMenu(
        context: context,
        messageRect: request.slotGlobal,
        tapGlobal: request.tapGlobal,
        items: MessageMenuCatalog.excluding(
          itemsFor(request, policy),
          excludeActionIds,
        ),
        reactions: reactions,
        selectionPolicy: policy,
        presence: _ChatDataSourceListenable(dataSource),
        isPresent: () => dataSource.getMessage(request.messageId) != null,
      );
      if (!context.mounted || result == null) return;
      await _dispatch(
        context: context,
        request: request,
        result: result,
        selectedSnapshot: selectedSnapshot,
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
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    switch (result) {
      case ChatMessageMenuReactionResult(:final reaction):
        if (actions.onReact case final onReact?) {
          onReact(reaction);
          return;
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text('Reacted $reaction'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      case ChatMessageMenuItemResult(:final itemId):
        switch (itemId) {
          case MessageMenuActionId.copySelected:
            final text = request.selectedTextSnapshot;
            if (text == null || text.isEmpty) return;
            await Clipboard.setData(ClipboardData(text: text));
            actions.onCopySelected?.call(text);
          case MessageMenuActionId.copyLink:
            final hit = request.inlineHit;
            if (hit is! ChatInlineHit$Link) return;
            await Clipboard.setData(ClipboardData(text: hit.url));
            actions.onCopyLink?.call(hit.url);
          case MessageMenuActionId.copyCode:
            final hit = request.inlineHit;
            if (hit is! ChatInlineHit$Code) return;
            await Clipboard.setData(ClipboardData(text: hit.code));
            actions.onCopyCode?.call(hit.code);
          case MessageMenuActionId.copy:
            if (request.overSelection) {
              final buffer = StringBuffer();
              for (final id in selectedSnapshot) {
                final text = dataSource.getMessage(id)?.text;
                if (text == null || text.isEmpty) continue;
                if (buffer.isNotEmpty) buffer.writeln();
                buffer.write(text);
              }
              final text = buffer.toString();
              if (text.isEmpty) return;
              await Clipboard.setData(ClipboardData(text: text));
              selection?.clear();
              actions.onCopy?.call(text);
              return;
            }
            final text = dataSource.getMessage(request.messageId)?.text;
            if (text == null || text.isEmpty) return;
            await Clipboard.setData(ClipboardData(text: text));
            actions.onCopy?.call(text);
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
          case MessageMenuActionId.clearSelection:
            selection?.clear();
          case MessageMenuActionId.reply:
            if (actions.onReply case final onReply?) {
              onReply(request.messageId);
              return;
            }
            _stubFeedback(messenger, MessageMenuActionId.reply);
          case MessageMenuActionId.pin:
            if (actions.onPin case final onPin?) {
              onPin(request.messageId);
              return;
            }
            _stubFeedback(messenger, MessageMenuActionId.pin);
          case MessageMenuActionId.forward:
            if (actions.onForward case final onForward?) {
              onForward(request.messageId, selectedSnapshot);
              return;
            }
            _stubFeedback(
              messenger,
              request.overSelection
                  ? 'forward ${selectedSnapshot.length}'
                  : MessageMenuActionId.forward,
            );
          default:
            return;
        }
    }
  }

  void _stubFeedback(ScaffoldMessengerState messenger, String label) {
    messenger.showSnackBar(
      SnackBar(content: Text(label), behavior: SnackBarBehavior.floating),
    );
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
