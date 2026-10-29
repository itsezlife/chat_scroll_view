import 'dart:async';

import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_markdown_autoscroll.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_secondary_message_tap_scope.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart'
    show
        AdaptiveTextSelectionToolbar,
        ContextMenuButtonItem,
        ContextMenuButtonType;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:meta/meta.dart';

/// The text selection wiring of a body that registers a text model with the
/// facade: the per-body [MarkdownSelectionScope] (ADR 015) with the viewport's
/// policy gates, the facade's copy / select-all / dismiss actions, the desktop
/// press that arms the body as the **text selection subject**, and the
/// adaptive toolbar.
///
/// Both viewport bodies that paint selectable text ([ChatMarkdownBody] and the
/// text layout of [ChatEmojiBody]) mount their surface under this one widget,
/// so the entry, retarget and dismiss rules of ADR 012 and ADR 015 have one
/// home and the two bodies cannot drift. It owns no geometry: the child
/// mounts a `MarkdownSelectionSurface` on [ChatSelectionController.markdownSelection]
/// when [mountSurface] says the facade exposes one.
///
/// Rebuild it when the facade notifies (a body does, through a
/// `ListenableBuilder`): the gates read live membership and subject.
@internal
class ChatBodySelectionScope extends StatefulWidget {
  /// Creates the scope of [messageId] around [child].
  const ChatBodySelectionScope({
    required this.controller,
    required this.messageId,
    required this.mountSurface,
    required this.child,
    this.autoscroll,
    super.key,
  });

  /// The selection facade.
  final ChatSelectionController controller;

  /// The message whose body [child] paints.
  final int messageId;

  /// Whether the child mounts a selection surface now
  /// ([ChatSelectionController.exposesSelectionSurface] and the registration
  /// scope's say-so). Off, the scope is inert.
  final bool mountSurface;

  /// Edge autoscroll knobs; null is enabled with the policy's defaults.
  final ChatMarkdownAutoscrollOptions? autoscroll;

  /// The body, whose render object is the selection surface.
  final Widget child;

  @override
  State<ChatBodySelectionScope> createState() => _ChatBodySelectionScopeState();
}

class _ChatBodySelectionScopeState extends State<ChatBodySelectionScope> {
  // Rebuilt only when options / policy / display Hz change so mid-drag list
  // rebuilds keep the scope's cached target (the config has no value
  // equality, and resolver identity is part of it).
  MarkdownSelectionAutoscrollConfig? _autoscroll;
  ChatMarkdownAutoscrollOptions? _autoscrollOptions;
  ChatSelectionPolicy? _autoscrollPolicy;
  double? _autoscrollHz;

  ChatSelectionController get _controller => widget.controller;
  int get _id => widget.messageId;

  MarkdownSelectionAutoscrollConfig _resolvedAutoscroll() {
    final options = widget.autoscroll ?? const ChatMarkdownAutoscrollOptions();
    final policy = _controller.selectionPolicy;
    final hz = ChatMarkdownAutoscroll.readDisplayRefreshHz();
    if (_autoscroll case final cached?
        when options == _autoscrollOptions &&
            identical(policy, _autoscrollPolicy) &&
            hz == _autoscrollHz) {
      return cached;
    }
    _autoscrollOptions = options;
    _autoscrollPolicy = policy;
    _autoscrollHz = hz;
    return _autoscroll = ChatMarkdownAutoscroll.config(
      options: options,
      policy: policy,
      displayRefreshHz: hz,
    );
  }

  /// Whether a hit is something a tap does: every kind, except an embed the
  /// host does not act on (it is part of the text, so a press on it may begin
  /// a selection).
  bool _blocksSelection(ChatInlineHit? hit) =>
      hit != null &&
      (hit is! ChatInlineHit$Embed || _controller.handlesEmbedHits);

  bool get _scopeEnabled {
    if (!widget.mountSurface) return false;
    if (_controller.textSelectionSubject == _id) return true;
    final policy = _controller.selectionPolicy;
    // Mobile message-then-text: selected bodies stay armed for continuous
    // text entry and retarget, including while text is live on another
    // subject (ADR 015). Unselected rows stay off so message-selection
    // long-press wins.
    if (policy.nestsTextSubjectInMessageSelection &&
        _controller.isSelected(_id)) {
      return true;
    }
    // Desktop/web: direct entry only while message membership is empty:
    // settled message selection and text selection are exclusive under
    // [$Desktop]. Surfaces may still mount for inline hit-testing; the scope
    // stays off.
    if (policy.allowsTextEntryWithoutMessageSelection) {
      return !_controller.isSelectionMode && !_controller.hasDragSelection;
    }
    return false;
  }

  /// Whether the scope arms touch long-press for continuous text entry.
  ///
  /// Mobile: only when this body is message-selected or the text subject.
  /// Desktop: false, mouse recognizers cover direct entry and touch
  /// multi-tap must not steal viewport taps.
  bool _enableTouchGestures(bool scopeEnabled) {
    if (!scopeEnabled) return false;
    final policy = _controller.selectionPolicy;
    if (!policy.usesTimerBasedLongPress) return false;
    // Touch text-only: every body is armed, no message selection first.
    return !policy.allowsMessageSelection ||
        _controller.isSelected(_id) ||
        _controller.textSelectionSubject == _id;
  }

  /// Whether the scope may begin a character range at [global].
  ///
  /// Plain body text always may. Fenced copy chrome never may (not text).
  /// Under mobile message-then-text (selected body or active subject), link
  /// and inline-code spans may: long-press enters text selection there. Idle
  /// and desktop keep the scope off those hits so tap activation wins.
  bool _canStartTextSelectionAt(Offset global) {
    final hit = _controller.resolveInlineHit(_id, global);
    if (!_blocksSelection(hit)) {
      // The painter reports fenced copy chrome even when resolveInlineHit
      // missed (a position clamp edge): never arm text over COPY CODE.
      final surface = _controller.surfaceFor(_id);
      if (surface != null && surface.isLinkAtGlobal(global)) return false;
      return true;
    }
    // Fenced copy chrome: no text contour, not a selection start.
    if (hit case ChatInlineHit$Code(
      :final contourPath,
      :final touchOrigin,
    ) when contourPath == null && touchOrigin == null) {
      return false;
    }
    final policy = _controller.selectionPolicy;
    return policy.usesTimerBasedLongPress &&
        (_controller.isSelected(_id) ||
            _controller.textSelectionSubject == _id);
  }

  Widget _buildContextMenu(
    BuildContext context,
    MarkdownSelectionScopeState state,
  ) {
    final items = <ContextMenuButtonItem>[];
    if (_controller.textSelection case final sel? when !sel.isCollapsed) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () async {
            await _controller.copyTextSelection();
            state.hideToolbar();
          },
        ),
      );
    }
    if (_controller.hasBody(_id)) {
      items.add(
        ContextMenuButtonItem(
          type: ContextMenuButtonType.selectAll,
          onPressed: () {
            _controller.selectAllText();
            state.showToolbar();
          },
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return AdaptiveTextSelectionToolbar.buttonItems(
      buttonItems: items,
      anchors: state.contextMenuAnchors,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scopeEnabled = _scopeEnabled;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        // Desktop: a mouse press arms this body as the subject (ADR 012), so
        // the scope's recognizers can take the drag; a press on something a
        // tap does is left to the viewport.
        if (event.kind != PointerDeviceKind.mouse) return;
        final policy = _controller.selectionPolicy;
        if (!policy.allowsTextEntryWithoutMessageSelection ||
            _controller.isSelectionMode) {
          return;
        }
        if (_blocksSelection(
          _controller.resolveInlineHit(_id, event.position),
        )) {
          return;
        }
        _controller.armTextSelection(_id);
      },
      // The scope answers [CopySelectionTextIntent] itself, nearer to its
      // focus than the actions below, and writes plain text to the platform
      // clipboard: no host writer, no rich form, no copy feedback. The copy
      // key is therefore routed to an intent of the facade's own, which no
      // scope knows.
      child: Shortcuts(
        shortcuts: _copyShortcuts(),
        child: Actions(
          actions: <Type, Action<Intent>>{
            _CopyTextSelectionIntent: _CopyTextSelectionAction(_controller),
            CopySelectionTextIntent: CallbackAction<CopySelectionTextIntent>(
              onInvoke: (_) {
                unawaited(_controller.copyTextSelection());
                return null;
              },
            ),
            SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
              onInvoke: (_) {
                _controller.selectAllText();
                return null;
              },
            ),
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _controller.clearTextSelection();
                return null;
              },
            ),
          },
          child: MarkdownSelectionScope(
            controller: _controller.markdownSelection,
            enabled: scopeEnabled,
            // Drive the anchor viewport.
            autoscroll: _resolvedAutoscroll(),
            // Continuous text: touch long-press, word, drag-extend (ADR 015).
            // Consecutive taps stay off so the viewport owns toggle / dismiss
            // taps; mouse multi-click remains desktop.
            enableTouchGestures: _enableTouchGestures(scopeEnabled),
            enableTouchConsecutiveTaps: false,
            canStartSelectionAt: _canStartTextSelectionAt,
            // Subject-only chrome: siblings share the controller under mobile
            // multi-select but must not paint this body's handles or toolbar
            // until they are the text selection subject.
            ownsSelectionChrome: (documentId) =>
                documentId == _id && _controller.textSelectionSubject == _id,
            // Desktop + host secondary: yield right-click to the full-slot
            // message menu. Mobile keeps adaptive text chrome even when
            // secondary is also wired (menu entry is idle primary).
            contextMenuBuilder:
                ChatSecondaryMessageTapScope.hostOwnsSecondaryOf(context) &&
                    _controller.selectionPolicy.secondaryMessageTapOwnsFullSlot
                ? null
                : _buildContextMenu,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The copy key of the platform (Cmd+C on Apple platforms, Ctrl+C elsewhere)
/// over a body's text selection, as the platform's own text fields bind it.
///
/// Built per call, never cached: the platform is read when the scope builds,
/// not once per process (a cached map kept the key of whichever platform
/// built the first scope).
Map<ShortcutActivator, Intent> _copyShortcuts() => <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.keyC, meta: _isApple, control: !_isApple):
      const _CopyTextSelectionIntent(),
};

bool get _isApple => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.iOS => true,
  _ => false,
};

/// Copy of the facade's text selection, apart from [CopySelectionTextIntent]
/// (see the comment where the shortcut is bound).
class _CopyTextSelectionIntent extends Intent {
  const _CopyTextSelectionIntent();
}

class _CopyTextSelectionAction extends Action<_CopyTextSelectionIntent> {
  _CopyTextSelectionAction(this._controller);

  final ChatSelectionController _controller;

  // Off with no text selected, so the key goes on to the message copy.
  @override
  bool isEnabled(_CopyTextSelectionIntent intent) =>
      _controller.isTextSelectionActive;

  @override
  Object? invoke(_CopyTextSelectionIntent intent) {
    unawaited(_controller.copyTextSelection());
    return null;
  }
}
