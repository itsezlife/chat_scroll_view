import 'dart:async';
import 'dart:developer' as dev;

import 'package:chat_composer/chat_composer.dart' show ComposerBottomFade;
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/common/panel_trace.dart';
import 'package:chat_scroll_view_example/src/common/soft_keyboard_port.dart';
import 'package:chat_scroll_view_example/src/common/widgets/measure_size.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_controller.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_state.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/unread_boundary_controller.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/backend_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/comments_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_linkify_util.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_data_source_extension.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/unread_boundary_sender_run_layout.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_bottom_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_dialogs.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_search_bar.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/date_separator.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_backend_error.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/scroll_to_bottom_button.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/selection_app_bar.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/chat_side_controls.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/unread_separator.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart'
    show PastedMedia, SemanticKind;
import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:panel_presentation/panel_presentation.dart';

/// Supplies the message source of a [WidgetChatScreen].
typedef ChatDataSourceLoader = Future<ChatDataSource> Function();

/// Demo screen for the widget-based [ChatScrollView] — the chat viewport,
/// a bottom composer, the emoji panel and a contextual selection bar, wired
/// together.
///
/// The screen creates one [ChatInputSet] (composer, panel shell, presentation)
/// over the app's [AppServices] and disposes it with itself.
class WidgetChatScreen extends StatefulWidget {
  /// Demo route wiring [ChatScrollView], composer, panel and selection chrome.
  const WidgetChatScreen({
    required this.services,
    this.dataSourceLoader,
    this.softKeyboard = const PlatformSoftKeyboard(),
    this.presentationPolicy,
    super.key,
  });

  /// The app's long-lived services; the screen disposes none of them.
  final AppServices services;

  /// Supplies the message source instead of the bundled comments asset, so a
  /// harness can run the real screen on generated messages with no backend.
  ///
  /// The screen owns the returned source and disposes it. The app leaves this
  /// null.
  final ChatDataSourceLoader? dataSourceLoader;

  /// The soft keyboard's readings and commands.
  final SoftKeyboardPort softKeyboard;

  /// Where the panel appears, or null for the policy of the platform.
  final PanelPresentationPolicy? presentationPolicy;

  @override
  State<WidgetChatScreen> createState() => _WidgetChatScreenState();
}

class _WidgetChatScreenState extends State<WidgetChatScreen> {
  ChatDataSource? _dataSource;
  late final ChatScrollController _controller;
  late final ChatSelectionController _selection;
  final GlobalKey _composerGlassKey = GlobalKey(debugLabel: 'ComposerGlass');
  final GlobalKey _presentationSpace = GlobalKey(debugLabel: 'PanelSpace');

  /// The per-chat input set; created with the first dependencies (it needs
  /// the view) and disposed with the screen.
  ChatInputSet? _inputSet;

  /// Logs the panel's signals when `PANEL_TRACE` is defined.
  PanelTrace? _trace;

  bool _loading = true;
  String? _errorMessage;
  MessageMenu? _messageMenu;

  /// Demo settings: message corner radius (0–17).
  double _bubbleRadius = ChatMessageThemeData.fallback.bubbleRadius;

  /// Highest message id counted as read for [ChatScrollToBottomButton]. Seeded
  /// to stored last-read on off-tail open; advanced by the FAB while scrolling.
  final ValueNotifier<int?> _pillLastSeenBaseline = ValueNotifier<int?>(null);

  /// Unread boundary of the current open; `null` until the open resolves.
  /// Independent of [_pillLastSeenBaseline] — reading advances the baseline,
  /// never the boundary.
  UnreadBoundaryController? _unreadBoundary;

  /// Whether the open has resolved, so there is a reading position worth
  /// saving.
  var _readingPositionKnown = false;

  /// Saves or drops this chat's reading position when the app hides.
  late final AppLifecycleListener _lifecycle;

  /// Page-down chrome show-intent — drives [ChatSideControlsBar] stack slot.
  var _pageDownChromeVisible = false;

  ChatSearchController? _search;

  /// Coalesces progressive baseline bumps while scrolling into a single
  /// `update_read_state` call; tail arrival flushes immediately.
  Timer? _persistLastReadTimer;

  static const Duration _persistLastReadDebounce = Duration(milliseconds: 500);

  int? _pendingLastReadBaseline;

  ChatInputSet get _input => _inputSet!;

  @override
  void initState() {
    super.initState();
    _controller = ChatScrollController();
    _selection = ChatSelectionController(
      onInteraction: _onSelectionInteraction,
      // Selections and code taps keep their formatting on the clipboard.
      copyWriter: (copy) => widget.services.clipboard.write(ChatCopy.of(copy)),
    )..selectionCap = 100;
    _pillLastSeenBaseline.addListener(_onPillBaselineChanged);
    _lifecycle = AppLifecycleListener(onHide: _saveReadingPosition);
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fresh = _inputSet == null;
    final input = _inputSet ??= ChatInputSet(
      services: widget.services,
      view: View.of(context),
      send: _handleSendMessage,
      edit: _handleEditSelected,
      confirmClearRecents: _confirmClearRecents,
      keyboard: widget.softKeyboard,
      policy: widget.presentationPolicy,
      onPastedMedia: _onPastedMedia,
    );
    if (fresh && kPanelTrace) _trace = PanelTrace(input);
    final safe = MediaQuery.viewPaddingOf(context);
    input
      ..updateEnvironment(
        size: MediaQuery.sizeOf(context),
        safeTop: safe.top,
        safeBottom: safe.bottom,
      )
      ..applyTheme(ChromeThemeScope.composerOf(context));
  }

  void _onSelectionInteraction(ChatSelectionInteraction interaction) {
    switch (interaction) {
      case ChatCopied(:final text, :final gesture):
        if (gesture == ChatInlineGesture.longPress) {
          HapticFeedback.lightImpact();
        }
        _showCopiedSnack(text);
      case ChatLinkActivated(
        :final messageId,
        :final title,
        :final url,
        :final gesture,
      ):
        switch (gesture) {
          case ChatInlineGesture.tap:
            _onLinkTap(messageId, title, url);
          case ChatInlineGesture.longPress:
            _onLinkLongPress(messageId, title, url);
        }
      case ChatMentionActivated() ||
          ChatHashtagActivated() ||
          ChatEmbedActivated():
        // The example opens none of these yet.
        break;
      case ChatCodeActivated(:final gesture):
        // Host-owned copy path only when [copyCodeOnClick] is false.
        if (gesture == ChatInlineGesture.longPress) {
          HapticFeedback.lightImpact();
        }
    }
  }

  void _showCopiedSnack(String text) {
    if (!mounted || text.isEmpty) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return; // Do not show the snackbar on Android
    }
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text('Copied'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ),
      );
  }

  void _onLinkTap(int messageId, String title, String url) {
    if (!mounted) return;
    final label = switch (ChatBodyLinkifyUtil.activation(url)) {
      WebLinkActivation(:final uri) => 'Opening: $uri',
      MentionLinkActivation(:final username) => 'Mention: $username',
      OtherLinkActivation(:final url) => 'Link: $url',
    };
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(label),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _onLinkLongPress(int messageId, String title, String url) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    unawaited(
      showLinkActionsSheet(
        context,
        title: title,
        url: url,
        onOpen: () => _onLinkTap(messageId, title, url),
        onCopied: _showCopiedSnack,
      ),
    );
  }

  void _onAvatarTap(String sender) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('User Profile: $sender'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
  }

  @override
  void dispose() {
    _pillLastSeenBaseline.removeListener(_onPillBaselineChanged);
    _lifecycle.dispose();
    _saveReadingPosition();
    _flushPendingLastRead();
    _persistLastReadTimer?.cancel();
    _pillLastSeenBaseline.dispose();
    _unreadBoundary?.dispose();
    _search?.dispose();
    _controller.dispose();
    _selection.dispose();
    _trace?.dispose();
    _inputSet?.dispose();
    if (_dataSource case final BackendChatDataSource source) {
      source.removeReconnectGapListener(_onReconnectGap);
    }
    _dataSource?.dispose();
    _messageMenu = null;
    super.dispose();
  }

  /// Makes the unread boundary pending where a realtime reconnect may have
  /// missed messages.
  void _onReconnectGap(RealtimeReconnectGap gap) =>
      _unreadBoundary?.markReconnectGap(
        newestBeforeDrop: gap.newestBeforeDrop,
        readMark: gap.lastReadMessageId,
      );

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // final backend = await BackendChatDataSource.connect(
      //   client: Supabase.instance.client,
      // );
      final backend =
          await (widget.dataSourceLoader ?? CommentsDataSource.load)();

      // The screen may have been popped while `load()` was in flight. The
      // `dispose()` above already ran with `_dataSource == null`, so we
      // would otherwise assign the newly-loaded source into the dead State
      // and never free it.
      if (!mounted) {
        backend.dispose();
        return;
      }
      // Owned from here on: `dispose()` and the catch below free it.
      _dataSource = backend;

      // Only the server-backed source persists read state; the bundled
      // sources open without a stored last-read.
      final lastRead = switch (backend) {
        final BackendChatDataSource source =>
          await source.getLastReadMessageId(),
        CommentsDataSource() => 9990,
        _ => null,
      };
      final centerBands = widget.services.centerBands;
      final openPosition = await backend.resolveOpenPosition(
        storedLastRead: lastRead,
        isSelfMessage: _isSelfMessage,
        savedCenterBand: switch (_readingPositionKey(backend)) {
          final key? => await centerBands.read(key),
          null => null,
        },
      );
      if (!mounted) return;
      _readingPositionKnown = true;

      _messageMenu = MessageMenu(
        dataSource: backend,
        clipboard: widget.services.clipboard,
        selection: _selection,
        actions: MessageMenuActions(
          onDelete: (messageId) => _handleDeleteSelected([messageId]),
          onDeleteSelected: _handleDeleteSelected,
          onEdit: _beginEdit,
          onCopy: _showCopiedSnack,
          onCopySelected: _showCopiedSnack,
          onCopyLink: _showCopiedSnack,
          onCopyCode: _showCopiedSnack,
        ),
      );
      _search?.dispose();
      _search = ChatSearchController(dataSource: backend);
      final newest = backend.newestKnownId;
      _pillLastSeenBaseline.value =
          lastRead != null && newest != null && lastRead < newest
          ? lastRead
          : null;
      _unreadBoundary?.dispose();
      final boundary = _unreadBoundary = UnreadBoundaryController(
        dataSource: backend,
        controller: _controller,
        isSelfMessage: _isSelfMessage,
        boundary: switch (openPosition) {
          MessageOpenPosition(:final unreadBoundary) => unreadBoundary,
          CenterBandOpenPosition() => null,
        },
        readElsewhere: switch (backend) {
          final BackendChatDataSource source => source.readElsewhere,
          _ => null,
        },
      );
      if (backend case final BackendChatDataSource source) {
        source.addReconnectGapListener(_onReconnectGap);
      }
      switch (openPosition) {
        case MessageOpenPosition(
          :final anchor,
          :final alignment,
          :final tailFitFraction,
          :final pixelOffset,
        ):
          _controller.jumpTo(
            anchor,
            alignment: alignment,
            tailFitFraction: tailFitFraction,
            pixelOffset: pixelOffset,
          );
        case CenterBandOpenPosition(
          :final centerBand,
          :final pendingBoundaryFrom,
        ):
          if (pendingBoundaryFrom case final fromId?) {
            boundary.setPendingBoundary(fromId);
          }
          _controller.jumpToCenterBand(
            centerBand.messageId,
            centerBand.offsetFromMessageTop,
          );
      }
    } on Object catch (error, stackTrace) {
      dev.log(
        'Error initializing chat screen',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _unreadBoundary?.dispose();
      _unreadBoundary = null;
      _readingPositionKnown = false;
      _dataSource?.dispose();
      _dataSource = null;
      _messageMenu = null;
      _errorMessage = error.toString();
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _onPillBaselineChanged() {
    final newest = _dataSource?.newestKnownId;
    final baseline = _pillLastSeenBaseline.value;
    if (newest == null || baseline == null) return;
    final backend = _dataSource;
    if (backend is! BackendChatDataSource) return;

    _pendingLastReadBaseline = baseline;
    _persistLastReadTimer?.cancel();

    if (baseline >= newest) {
      _flushPendingLastRead();
      return;
    }

    _persistLastReadTimer = Timer(
      _persistLastReadDebounce,
      _flushPendingLastRead,
    );
  }

  void _flushPendingLastRead() {
    _persistLastReadTimer?.cancel();
    _persistLastReadTimer = null;
    final baseline = _pendingLastReadBaseline;
    if (baseline == null) return;
    final backend = _dataSource;
    if (backend is! BackendChatDataSource) return;
    _pendingLastReadBaseline = null;
    unawaited(backend.updateLastReadMessageId(baseline));
  }

  /// Key of [source]'s chat in the center-band store (a key-value name), or
  /// `null` for a chat whose history does not survive a relaunch.
  static String? _readingPositionKey(ChatDataSource source) => switch (source) {
    BackendChatDataSource(:final chatId) => 'backend.$chatId',
    CommentsDataSource() => 'comments',
    _ => null,
  };

  /// Saves the reading position for the next open, or drops it when the
  /// chat is left at the tail or at the start of unread content — see
  /// [ChatDataSourceX.resolveLeavePosition]. Leaves the store untouched
  /// before the open's first layout.
  void _saveReadingPosition() {
    final source = _dataSource;
    if (!_readingPositionKnown || source == null) return;
    final key = _readingPositionKey(source);
    final range = _controller.visibleRange.value;
    if (key == null || range == null) return;
    final centerBand = source.resolveLeavePosition(
      centerBand: _controller.centerBand.value,
      isAtTail: _controller.isAtTail.value,
      newestVisibleId: range.lastId,
      readMark: _pillLastSeenBaseline.value,
      isSelfMessage: _isSelfMessage,
    );
    unawaited(
      widget.services.centerBands.write(key, centerBand).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        dev.log(
          'Saving the reading position failed',
          name: 'chat_open',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  /// Page-down goes to the unread boundary until its separator has been
  /// seen, pending boundaries included; afterwards it goes to the newest
  /// message.
  bool _pageDownToUnseenBoundary() {
    final fromId = _unreadBoundary?.unseenFromId;
    if (fromId == null) return false;
    unawaited(
      _controller.animateTo(
        fromId,
        alignment: ChatDataSourceX.unreadBoundaryAlignment,
        pixelOffset: ChatDataSourceX.unreadBoundaryPixelOffset,
        highlight: false,
      ),
    );
    return true;
  }

  static const String _demoSender = 'Hixie';

  /// Demo "signed-in user" — same predicate for viewport follow-tail and FAB.
  static bool _isSelfMessage(IChatMessage message) =>
      message.sender == _demoSender;

  /// Sends [text] as the signed-in user. A send that succeeds clears the
  /// unread boundary of the open it was sent from, whether or not the tail
  /// holding the sent message is loaded.
  Future<void> _handleSendMessage(String text) async {
    final boundary = _unreadBoundary;
    switch (_dataSource) {
      case final CommentsDataSource ds:
        ds.sendMessage(sender: _demoSender, content: text);
      case final GeneratedChatDataSource ds:
        ds.sendMessage(sender: _demoSender, content: text);
      case final BackendChatDataSource ds:
        try {
          await ds.sendMessage(text);
        } on BackendConnectionException catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(error.message),
                behavior: SnackBarBehavior.floating,
              ),
            );
          rethrow;
        }
      case _:
        return;
    }
    boundary?.clear();
  }

  void _handleDeleteSelected(Iterable<int> ids) {
    final toDelete = ids.toList();
    final ds = _dataSource;
    ds?.removeMessages(toDelete);
    _selection.clear();
  }

  Future<void> _handleEditSelected(int messageId, String text) async {
    final ds = _dataSource;
    if (ds is CommentsDataSource) {
      final message = ds.getMessage(messageId);
      if (message is UserChatMessage) {
        ds.editMessage(message, text);
      }
      return;
    }
    if (ds is GeneratedChatDataSource) {
      final message = ds.getMessage(messageId);
      if (message is UserChatMessage) {
        ds.editMessage(message, text);
      }
      return;
    }
    final message = ds?.getMessage(messageId);
    if (message != null) {
      ds?.updateMessage(
        UserChatMessage(
          id: message.id,
          sender: message.sender,
          createdAt: message.createdAt,
          updatedAt: DateTime.now(),
          content: ChatBodyLinkifyUtil.materialize(text),
        ),
      );
    }
  }

  /// Host message-menu seam for idle primary tap (mobile) and secondary tap
  /// (desktop right-click) — [ChatScrollView] routes each per selection policy.
  Future<void> _presentMessageMenu(ChatMessageMenuRequest request) async {
    final menu = _messageMenu;
    if (menu == null || !mounted) return;
    await menu.present(context, request);
  }

  Future<void> _openBubbleRadiusSettings() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showBubbleRadiusDialog(
      context,
      initial: _bubbleRadius,
    );
    if (selected == null || !mounted) return;
    setState(() => _bubbleRadius = selected);
  }

  /// Stable per-state tear-off — same reference for the widget's lifetime,
  /// so the viewport's skip-rebuild cache stays warm across parent rebuilds.
  /// Sender-run chrome comes from viewport [MessageRunLayout], not ad-hoc
  /// neighbor walks here.
  Widget _buildMessage(
    BuildContext context,
    int id,
    IChatMessage? message,
    ChatMessageStatus status,
    MessageRunLayout runLayout,
  ) => buildDemoMessage(
    context,
    id,
    message,
    status,
    runLayout,
    selection: _selection,
    onAvatarTap: _onAvatarTap,
    onSenderTap: _onAvatarTap,
  );

  void _selectTextFromBar() {
    if (_selection.count != 1) return;
    _selection.enterTextSelection(_selection.selectedIds.first);
  }

  Widget _buildChunkError(
    BuildContext context,
    ChatChunkErrorDetails details,
  ) => DemoChunkErrorTile(
    firstId: details.firstId,
    lastId: details.lastId,
    attempt: details.attempt,
    onRetry: details.retry,
  );

  Widget _buildEmpty(BuildContext context) => const DemoEmptyState();

  Widget _buildUnreadSeparator(BuildContext context) => const UnreadSeparator();

  Widget _buildInitialSkeleton(BuildContext context) =>
      const DemoInitialSkeleton();

  void _beginEdit(int messageId) {
    final content = _dataSource?.getMessage(messageId)?.text;
    if (content == null) return;
    _selection.clear();
    _input.beginEdit(messageId, content);
  }

  /// Asks before the recent content of [kind] is cleared.
  Future<bool> _confirmClearRecents(SemanticKind kind) async {
    if (!mounted) return false;
    final panel = ChromeStringsScope.panelOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(panel.clearRecentsTitle),
        content: Text(panel.clearRecentsMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(panel.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(panel.clearAction),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // The demo sends no media: it shows what it would send, as the reference
  // clients show pasted media before sending it. Cancelling pastes the text
  // that came with the media, if any.
  Future<bool> _onPastedMedia(List<PastedMedia> media) async {
    if (!mounted) return false;
    final send = await showPastedMediaSheet(context, media);
    if (send) {
      _showDemoSnack(
        media.length == 1
            ? 'Would send 1 item'
            : 'Would send ${media.length} items',
      );
    }
    return send;
  }

  void _showDemoSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
  }

  void _copySelected() {
    if (_selection.isTextSelectionActive) {
      unawaited(_selection.copyTextSelection());
      return;
    }
    final ids = _selection.selectedIds.toList()..sort();
    final copied = ChatCopy.messages([
      for (final id in ids) ?_dataSource?.getMessage(id)?.text,
    ]);
    if (copied.isEmpty) return;
    unawaited(widget.services.clipboard.write(copied));
    _selection.clear();
    _showCopiedSnack(copied.plain);
  }

  void _editSelectedFromBar() {
    if (_selection.count != 1) return;
    _beginEdit(_selection.selectedIds.first);
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return DemoBackendError(message: _errorMessage!, onRetry: _init);
    }
    if (_loading || _dataSource == null || _search == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final chatScrollTheme = ChatScrollTheme.of(context);
    final messageTheme = chatScrollTheme.message;
    final newMessageTheme = messageTheme?.copyWith(bubbleRadius: _bubbleRadius);
    final search = _search!;
    final input = _input;
    final insets = input.insets;
    final mobilePanel =
        input.presentation.policy is PanelPresentationPolicy$Mobile;

    return ControllerScope.value(
      search,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          final isOpenSearch = search.state.maybeMap(
            closed: (_) => false,
            orElse: () => true,
          );
          if (isOpenSearch) {
            search.close();
          }
          if (_messageMenu?.isPresenting ?? false) return;
          if (_selection.isTextSelectionActive) {
            _selection.clearTextSelection();
            return;
          }
          final hasSelection = _selection.isSelectionMode;
          if (hasSelection) {
            _selection.clear();
            return;
          }
          if (input.isPanelVisible) {
            unawaited(input.handleBack());
            return;
          }
          // No-op, since no navigation is supported in this demo.
        },
        child: ChatScrollTheme(
          data: chatScrollTheme.copyWith(message: newMessageTheme),
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
              systemNavigationBarContrastEnforced: false,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarDividerColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.light,
              systemStatusBarContrastEnforced: false,
            ),
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              body: StateConsumer<ChatSearchController, ChatSearchState>(
                listener: _onSearchStateChanged,
                child: GlassSourceScope(
                  child: Stack(
                    key: _presentationSpace,
                    children: <Widget>[
                      // A docked panel takes width from the chat region; the
                      // popup and the dock draw above it.
                      Positioned.fill(
                        child: ValueListenableBuilder<double>(
                          valueListenable: insets.inlineEnd,
                          builder: (context, inlineEnd, child) => Padding(
                            padding: EdgeInsetsDirectional.only(end: inlineEnd),
                            child: child,
                          ),
                          child: _buildChatRegion(
                            search: search,
                            mobilePanel: mobilePanel,
                          ),
                        ),
                      ),
                      if (!mobilePanel)
                        Positioned.fill(
                          child: PanelPresentationView(
                            controller: input.presentation,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The chat, its chrome and the composer, in the box the docked panel
  /// leaves.
  Widget _buildChatRegion({
    required ChatSearchController search,
    required bool mobilePanel,
  }) {
    final input = _input;
    final insets = input.insets;
    return Stack(
      children: <Widget>[
        // Chat fills the screen; the composer is stacked over its bottom.
        Positioned.fill(
          child: GlassSource(
            child: ChatKeyboardShortcuts(
              controller: _controller,
              selectionController: _selection,
              reverse: true,
              preserveExternalFocus: true,
              child: ChatScrollView(
                reverse: true,
                dataSource: _dataSource!,
                controller: _controller,
                selectionController: _selection,
                onIdleMessageTap: _presentMessageMenu,
                onSecondaryMessageTap: _presentMessageMenu,
                isSelfMessage: _isSelfMessage,
                bottomPadding: insets.bottomPadding,
                topPadding: insets.topPadding,
                messageBuilder: _buildMessage,
                chunkErrorBuilder: _buildChunkError,
                emptyBuilder: _buildEmpty,
                loadingBuilder: _buildInitialSkeleton,
                scrollActivityTiming: const ChatScrollActivityTiming(),
                dayHeaderDelegate: const ChatPushingDayHeader(),
                dateSeparatorBuilder: (context, bucket, date) =>
                    DateSeparator(date: date),
                unreadBoundary: _unreadBoundary,
                unreadSeparatorBuilder: _buildUnreadSeparator,
                senderRunLayout: switch (_unreadBoundary) {
                  final boundary? => UnreadBoundarySenderRunLayout(
                    boundary: boundary,
                  ),
                  null => DefaultChatSenderRunLayout.instance,
                },
              ),
            ),
          ),
        ),
        // Side controls — page-down + search up/down share one stack.
        _ChatSideControlsHost(
          pageDownChromeVisible: _pageDownChromeVisible,
          bottomInset: insets.bottomPadding,
          onSearchStep: _onSearchStep,
          pageDown: ChatScrollToBottomButton(
            embedded: true,
            controller: _controller,
            dataSource: _dataSource!,
            isSelfMessage: _isSelfMessage,
            lastSeenNewestId: _pillLastSeenBaseline,
            interceptTap: _pageDownToUnseenBoundary,
            onChromeVisibleChanged: (visible) {
              if (_pageDownChromeVisible == visible) return;
              setState(() => _pageDownChromeVisible = visible);
            },
          ),
        ),
        // Soft fade over chat in the chrome zone. Under the composer so the
        // panel is not washed, and outside the glass source so the island
        // frosts the chat and not this wash.
        ValueListenableBuilder<double>(
          valueListenable: insets.bottomPadding,
          builder: (context, zoneHeight, _) {
            if (zoneHeight <= 0) return const SizedBox.shrink();
            return Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: zoneHeight,
              child: ComposerBottomFade(
                zoneHeight: zoneHeight,
                color: ChromeThemeScope.composerOf(context).contentFade,
              ),
            );
          },
        ),
        // Bottom chrome. Insets math:
        //   bottomPadding = composer extent + presentation occupancy.bottom
        // The occupancy holds the live soft keyboard or the panel, whichever
        // is taller, bottom safe area included; the composer's own pad is
        // the part of the band the occupancy has not covered.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ChatBottomChrome(
            input: input,
            selection: _selection,
            islandKey: _composerGlassKey,
            anchorSpace: _presentationSpace,
            onAttachPressed: () =>
                _showDemoSnack('Attachments are not in the demo'),
            onVoicePressed: () => _showDemoSnack('Voice is not in the demo'),
          ),
        ),
        // Contextual selection bar — overlays the top. [headerReserve] is
        // driven every animation frame so the floating day header tracks the
        // slide.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SelectionAppBar(
            selection: _selection,
            topInset: insets.headerReserve,
            onSelectText: _selectTextFromBar,
            onCopy: _copySelected,
            onEdit: _editSelectedFromBar,
            onDelete: () => _handleDeleteSelected(_selection.selectedIds),
          ),
        ),
        // Demo: search + bubble radius — top-right chrome. Position
        // against [chromeTop] (not [topPadding]) so search reserve does not
        // push this row further down. [Positioned] must be a *direct* Stack
        // child; wrapping it in ValueListenableBuilder makes the builder
        // expand and cover the chat.
        Positioned(
          top: 0,
          right: 12,
          child: ValueListenableBuilder<double>(
            valueListenable: insets.chromeTop,
            builder: (context, chromeTop, child) => Padding(
              padding: EdgeInsets.only(top: chromeTop + 8),
              child: child,
            ),
            child: ListenableBuilder(
              listenable: _selection,
              builder: (context, _) {
                if (_selection.isSelectionMode) {
                  return const SizedBox.shrink();
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ChatSearchToggleButton(),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      tooltip: 'Message corners',
                      onPressed: _openBubbleRadiusSettings,
                      icon: const Icon(Icons.rounded_corner, size: 20),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 12,
          right: 118,
          child: ValueListenableBuilder<double>(
            valueListenable: insets.chromeTop,
            builder: (context, chromeTop, _) => ValueListenableBuilder<bool>(
              valueListenable: search.select(
                (s) => s.maybeMap(closed: (_) => false, orElse: () => true),
              ),
              builder: (context, isOpen, _) {
                if (!isOpen) return const SizedBox.shrink();
                // Position against chromeTop; measure only the local pad +
                // field into searchReserve.
                return Padding(
                  padding: EdgeInsets.only(top: chromeTop),
                  child: MeasureSize(
                    onChange: (size) => insets.setSearchReserve(size.height),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: ChatSearchBar(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _onSearchStateChanged(
    BuildContext context,
    ChatSearchController controller,
    ChatSearchState previous,
    ChatSearchState current,
  ) {
    final wasOpen = previous.maybeMap(closed: (_) => false, orElse: () => true);
    final isOpen = current.maybeMap(closed: (_) => false, orElse: () => true);
    if (wasOpen && !isOpen) {
      _input.insets.setSearchReserve(0);
    }

    final prevPopulated = previous.mapOrNull(populated: (s) => s);
    final nextPopulated = current.mapOrNull(populated: (s) => s);
    if (nextPopulated == null) return;
    // Index-only commits from [_onSearchStep] keep the same hits list.
    // Re-animating here would double-fire after every accepted step.
    if (prevPopulated != null &&
        identical(prevPopulated.hits, nextPopulated.hits)) {
      return;
    }
    unawaited(
      _controller.animateTo(
        nextPopulated.hits[nextPopulated.index],
        highlight: true,
        alignment: 0.5,
        loadPolicy: AnimateToLoadPolicy.immediate,
        busyPolicy: AnimateToBusyPolicy.ignore,
      ),
    );
  }

  /// Search up/down: one step per in-flight animate under ignore.
  ///
  /// Commit the hit index only when the viewport can accept the navigation.
  /// Advancing first (old [ChatSearchController.goOlder]) races selection
  /// ahead of [AnimateToBusyPolicy.ignore] drops and kills bound-gated FABs.
  void _onSearchStep({required bool towardOlder}) {
    final search = _search;
    if (search == null) return;
    if (_controller.isAnimating) return;
    final step = towardOlder ? search.peekOlder() : search.peekNewer();
    if (step == null) return;
    search.selectIndex(step.index);
    unawaited(
      _controller.animateTo(
        step.id,
        highlight: true,
        alignment: 0.5,
        loadPolicy: AnimateToLoadPolicy.immediate,
        busyPolicy: AnimateToBusyPolicy.ignore,
      ),
    );
  }
}

/// Search up/down + page-down chrome driven by [ChatSearchController].
class _ChatSideControlsHost extends StatelessWidget {
  const _ChatSideControlsHost({
    required this.pageDownChromeVisible,
    required this.bottomInset,
    required this.pageDown,
    required this.onSearchStep,
  });

  final bool pageDownChromeVisible;
  final ValueListenable<double> bottomInset;
  final Widget pageDown;
  final void Function({required bool towardOlder}) onSearchStep;

  @override
  Widget build(BuildContext context) {
    final search = context.controllerOf<ChatSearchController>();
    return ValueListenableBuilder(
      valueListenable: search.select(
        (s) => (
          searching: s.maybeMap(closed: (_) => false, orElse: () => true),
          hitCount: s.maybeMap(
            populated: (p) => p.hits.length,
            orElse: () => 0,
          ),
          index: s.maybeMap(populated: (p) => p.index, orElse: () => 0),
        ),
        (prev, next) => prev != next,
      ),
      builder: (context, slice, _) => ChatSideControlsBar(
        searching: slice.searching,
        pageDownVisible: pageDownChromeVisible,
        bottomInset: bottomInset,
        onSearchUp: () => onSearchStep(towardOlder: true),
        onSearchDown: () => onSearchStep(towardOlder: false),
        searchHitCount: slice.hitCount,
        searchUpEnabled: slice.index > 0,
        searchDownEnabled:
            slice.hitCount > 0 && slice.index < slice.hitCount - 1,
        pageDown: pageDown,
      ),
    );
  }
}
