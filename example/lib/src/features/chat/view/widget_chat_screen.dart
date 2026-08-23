import 'dart:async';
import 'dart:developer' as dev;

import 'package:chat_chrome/chat_chrome.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/common/widgets/measure_size.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_controller.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/chat_search_state.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/backend_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_data_source_extension.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/comments_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets_binding.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/demo_message_menu.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_search_bar.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/date_separator.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_backend_error.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/scroll_to_bottom_button.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/selection_app_bar.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/side_controls/chat_side_controls.dart';
import 'package:control/control.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Demo screen for the widget-based [ChatScrollView] — the chat viewport,
/// a bottom composer, and a contextual selection bar, wired together.
class WidgetChatScreen extends StatefulWidget {
  /// Demo route wiring [ChatScrollView], composer, and selection chrome.
  ///
  /// Prefer a preloaded [keyboardHeightStore] / [emojiDataSource] from `main`
  /// so the composer button shows the last type tab (GIF / stickers) on first
  /// paint instead of the default smile.
  const WidgetChatScreen({
    this.keyboardHeightStore,
    this.emojiDataSource,
    super.key,
  });

  /// Optional preloaded prefs store (IME heights + last type tab).
  final KeyboardHeightStore? keyboardHeightStore;

  /// Optional preloaded emoji catalog. When null, the screen owns one.
  final DefaultEmojiDataSource? emojiDataSource;

  @override
  State<WidgetChatScreen> createState() => _WidgetChatScreenState();
}

class _WidgetChatScreenState extends State<WidgetChatScreen>
    with ChatViewportInsetsBinding {
  ChatDataSource? _dataSource;
  late final DefaultEmojiDataSource _emojiDataSource;
  var _ownsEmojiDataSource = false;
  late final ChatScrollController _controller;
  late final ChatSelectionController _selection;
  final GlobalKey<ChatComposerState> _composerKey =
      GlobalKey<ChatComposerState>();
  final GlobalKey<EmojiPanelState> _emojiPanelKey =
      GlobalKey<EmojiPanelState>();

  /// Demo: all type tabs so the floating glass pill matches Telegram.
  static const EmojiPanelAllow _emojiAllow = EmojiPanelAllow.emojiOnly;

  var _emojiPanelOpen = false;
  EmojiPanelTab? _lastEmojiTab;
  ChatPreImeBackClaim? _emojiBackClaim;

  bool _loading = true;
  String? _errorMessage;
  var _menuOpen = false;

  /// Demo settings: message corner radius (0–17).
  double _bubbleRadius = ChatMessageThemeData.fallback.bubbleRadius;

  /// Highest message id counted as read for [ChatScrollToBottomButton]. Seeded
  /// to stored last-read on off-tail open; advanced by the FAB while scrolling.
  final ValueNotifier<int?> _pillLastSeenBaseline = ValueNotifier<int?>(null);

  /// Page-down chrome show-intent — drives [ChatSideControlsBar] stack slot.
  var _pageDownChromeVisible = false;

  ChatSearchController? _search;

  /// Coalesces progressive baseline bumps while scrolling into a single
  /// `update_read_state` call; tail arrival flushes immediately.
  Timer? _persistLastReadTimer;

  static const Duration _persistLastReadDebounce = Duration(milliseconds: 500);

  int? _pendingLastReadBaseline;

  @override
  KeyboardHeightStore createKeyboardHeightStore() =>
      widget.keyboardHeightStore ?? KeyboardHeightStore();

  @override
  void onKeyboardHeightStoreReady() {
    final tab = _lastTabFromStore(keyboardHeightStore);
    if (tab == null || tab == _lastEmojiTab || !mounted) return;
    setState(() => _lastEmojiTab = tab);
  }

  @override
  void initState() {
    super.initState();
    final injected = widget.emojiDataSource;
    if (injected != null) {
      _emojiDataSource = injected;
    } else {
      _ownsEmojiDataSource = true;
      _emojiDataSource = DefaultEmojiDataSource(
        catalog: LocaleEmojiCatalogProvider(
          locale: const Locale('ru'),
          categoryTitles: EmojiCategoryTitles.russian,
          stripIconFor: EmojiTabAssets.stripIconForId,
        ),
      )..load();
    }
    // Prefs already loaded from main → seed before first composer paint.
    _lastEmojiTab = _lastTabFromStore(keyboardHeightStore);
    _controller = ChatScrollController();
    _selection = ChatSelectionController()..selectionCap = 100;
    _pillLastSeenBaseline.addListener(_onPillBaselineChanged);
    _init();
  }

  /// Last type tab from prefs, restricted to [_emojiAllow] tabs.
  static EmojiPanelTab? _lastTabFromStore(KeyboardHeightStore store) {
    if (!store.isReady) return null;
    final preferred = EmojiPanelTabPrefs.fromPrefs(store.selectedPage);
    final tabs = _emojiAllow.tabs;
    if (tabs.contains(preferred)) return preferred;
    return tabs.isEmpty ? null : tabs.first;
  }

  @override
  void dispose() {
    _emojiBackClaim?.pop();
    _emojiBackClaim = null;
    _pillLastSeenBaseline.removeListener(_onPillBaselineChanged);
    _flushPendingLastRead();
    _persistLastReadTimer?.cancel();
    _pillLastSeenBaseline.dispose();
    _search?.dispose();
    _controller.dispose();
    _selection.dispose();
    if (_ownsEmojiDataSource) {
      _emojiDataSource.dispose();
    }
    _dataSource?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // final backend = await BackendChatDataSource.connect(
      //   client: Supabase.instance.client,
      // );
      final backend = await CommentsDataSource.load();
      // final backend = GeneratedChatDataSource(messageCount: 100);

      // The screen may have been popped while `load()` was in flight. The
      // `dispose()` above already ran with `_dataSource == null`, so we
      // would otherwise assign the newly-loaded source into the dead State
      // and never free it.
      if (!mounted) {
        backend.dispose();
        return;
      }
      _dataSource = backend;
      _search?.dispose();
      _search = ChatSearchController(dataSource: backend);
      final newest = backend.newestKnownId;
      // final lastRead = await backend.getLastReadMessageId();
      // ignore: prefer_const_declarations
      final int? lastRead = null;

      final anchor = backend.resolveOpenAnchor(
        storedLastRead: lastRead,
        newestKnownId: newest,
        oldestKnownId: backend.oldestKnownId,
      );
      _pillLastSeenBaseline.value =
          lastRead != null && newest != null && lastRead < newest
          ? lastRead
          : null;
      final atTail = newest != null && anchor == newest;
      _controller.jumpTo(anchor, alignment: atTail ? 0.0 : .8);
    } on Object catch (error, stackTrace) {
      dev.log(
        'Error initializing chat screen',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _dataSource?.dispose();
      _dataSource = null;
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

  static const String _demoSender = 'Hixie';

  /// Demo "signed-in user" — same predicate for viewport follow-tail and FAB.
  static bool _isSelfMessage(IChatMessage message) =>
      message.sender == _demoSender;

  Future<void> _handleSendMessage(String text) async {
    final ds = _dataSource;
    if (ds is CommentsDataSource) {
      ds.sendMessage(sender: _demoSender, content: text);
      return;
    }
    if (ds is GeneratedChatDataSource) {
      ds.sendMessage(sender: _demoSender, content: text);
      return;
    }
    if (ds is BackendChatDataSource) {
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
    }
  }

  void _handleDeleteSelected(Iterable<int> ids) {
    final ds = _dataSource;
    if (ds is CommentsDataSource) {
      ds.removeMessages(ids);
      return;
    }
    if (ds is GeneratedChatDataSource) {
      ds.removeMessages(ids);
      return;
    }
    ds?.removeMessages(ids);
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
          content: text,
        ),
      );
    }
  }

  Future<void> _onIdleMessageTap(
    int id,
    Rect slotGlobal,
    Offset tapGlobal,
  ) async {
    final ds = _dataSource;
    if (ds == null || _menuOpen) return;
    _menuOpen = true;
    try {
      if (!mounted) return;
      await presentDemoMessageMenu(
        context: context,
        messageId: id,
        messageRect: slotGlobal,
        tapGlobal: tapGlobal,
        dataSource: ds,
        onDelete: (messageId) => _handleDeleteSelected([messageId]),
        onEdit: (messageId) => _composerKey.currentState?.beginEdit(messageId),
      );
    } finally {
      _menuOpen = false;
    }
  }

  Future<void> _openBubbleRadiusSettings() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showDialog<double>(
      context: context,
      requestFocus: false,
      builder: (dialogContext) {
        var value = _bubbleRadius;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Message corners'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('${value.round()}'),
                Slider(
                  value: value,
                  min: 0,
                  max: 17,
                  divisions: 17,
                  label: '${value.round()}',
                  onChanged: (next) => setDialogState(() => value = next),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(value),
                child: const Text('Apply'),
              ),
            ],
          ),
        );
      },
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
  ) {
    if (message == null) return const DemoShimmerBubble();
    return DemoMessageBubble(message: message, runLayout: runLayout);
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

  Widget _buildInitialSkeleton(BuildContext context) =>
      const DemoInitialSkeleton();

  ChatEnterEmojiIconState get _emojiIconState => resolveEmojiIconState(
    panelOpen: _emojiPanelOpen,
    textEmpty:
        _composerKey.currentState?.textController.text.trim().isEmpty ?? true,
    lastTab: _lastEmojiTab,
  );

  void _syncEmojiBackClaim() {
    if (_emojiPanelOpen) {
      _emojiBackClaim ??= ChatPreImeBackClaim.push(() async {
        final handled =
            await _emojiPanelKey.currentState?.handleBack() ?? false;
        return handled;
      });
    } else {
      _emojiBackClaim?.pop();
      _emojiBackClaim = null;
    }
  }

  void _toggleEmojiPanel() {
    if (_emojiPanelOpen) {
      chatChromeLog('toggle → close+keyboard');
      unawaited(_handoffEmojiToKeyboard());
      return;
    }
    _openEmojiPanel();
  }

  void _openEmojiPanel() {
    if (_emojiPanelOpen) return;

    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final replacing = bottomInsetController.isImeVisible;
    final target = bottomInsetController.openPanel(landscape: landscape);
    chatChromeLog(
      'toggle → open replacing=$replacing target=$target '
      'published=${bottomInsetController.height} '
      'ime=${bottomInsetController.imeHeight}',
    );

    // Set open first so composer enters IME-suppress mode (keyboard icon).
    setState(() => _emojiPanelOpen = true);
    _syncEmojiBackClaim();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_emojiPanelOpen) return;
      // After rebuild: hide soft IME, keep focus for cursor + hardware keys.
      _composerKey.currentState?.hideKeyboardRetainingFocus();
      unawaited(
        _emojiPanelKey.currentState?.open(replacingKeyboard: replacing),
      );
    });
  }

  /// Telegram: focus composer first (keep IME) → close search → panel handoff.
  Future<void> _handoffEmojiToKeyboard() async {
    final panel = _emojiPanelKey.currentState;
    // Steal focus before search/panel collapse so soft keyboard does not drop.
    // Field-tap races focus ahead of [onTap]; [prepareKeyboardHandoff] on
    // pointer-down arms IME-suppress bypass before this runs.
    _composerKey.currentState?.requestKeyboard();
    if (!mounted) return;
    if (panel != null && panel.isSearchOpen) {
      await panel.closeSearch(hideKeyboard: false);
    }
    if (!mounted) return;
    await panel?.close(waitForIme: true);
  }

  void _onInputTapWhileEmojiOpen() {
    if (!_emojiPanelOpen) return;
    chatChromeLog('input tap → close search/panel + keyboard');
    unawaited(_handoffEmojiToKeyboard());
  }

  void _copySelected() {
    final ids = _selection.selectedIds.toList()..sort();
    final buffer = StringBuffer();
    for (final id in ids) {
      final message = _dataSource?.getMessage(id);
      final text = switch (message) {
        UserChatMessage(:final content) => content,
        SystemChatMessage(:final content) => content,
        _ => null,
      };
      if (text == null) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write(text);
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    _selection.clear();
  }

  void _editSelectedFromBar() {
    if (_selection.count != 1) return;
    final id = _selection.selectedIds.first;
    _composerKey.currentState?.beginEdit(id);
  }

  void _onEmojiPanelOpenChanged(bool open) {
    if (_emojiPanelOpen == open) return;
    setState(() => _emojiPanelOpen = open);
    _syncEmojiBackClaim();
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
    final bottomPad = MediaQuery.viewPaddingOf(context).bottom;

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
          if (_menuOpen) return;
          final hasSelection = _selection.isSelectionMode;
          if (hasSelection) {
            _selection.clear();
            return;
          }
          if (_emojiPanelOpen) {
            unawaited(_emojiPanelKey.currentState?.handleBack());
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
                child: Stack(
                  children: <Widget>[
                    // Chat fills the screen; the composer is stacked over its bottom.
                    Positioned.fill(
                      child: ChatKeyboardShortcuts(
                        controller: _controller,
                        reverse: true,
                        preserveExternalFocus: true,
                        child: ChatScrollView(
                          reverse: true,
                          dataSource: _dataSource!,
                          controller: _controller,
                          selectionController: _selection,
                          onIdleMessageTap: _onIdleMessageTap,
                          isSelfMessage: _isSelfMessage,
                          bottomPadding: insets.bottomPadding,
                          topPadding: insets.topPadding,
                          messageBuilder: _buildMessage,
                          chunkErrorBuilder: _buildChunkError,
                          emptyBuilder: _buildEmpty,
                          loadingBuilder: _buildInitialSkeleton,
                          dateSeparatorBuilder: (context, bucket, date) =>
                              DateSeparator(date: date),
                        ),
                      ),
                    ),
                    // Side controls — page-down + search up/down share one stack
                    // (Telegram coordinated show/hide + vertical slide).
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
                        onChromeVisibleChanged: (visible) {
                          if (_pageDownChromeVisible == visible) return;
                          setState(() => _pageDownChromeVisible = visible);
                        },
                      ),
                    ),
                    // Soft fade under composer / keyboard (ChatActivityFadeView
                    // bottom zone). Over messages, under input chrome.
                    ValueListenableBuilder<double>(
                      valueListenable: insets.bottomPadding,
                      builder: (context, zoneHeight, _) {
                        if (zoneHeight <= 0) {
                          return const SizedBox.shrink();
                        }
                        final colors = ChatChromeTheme.of(context);
                        return Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: zoneHeight,
                          child: ChatContentBottomFade(
                            zoneHeight: zoneHeight,
                            color: colors.contentBottomFade,
                          ),
                        );
                      },
                    ),
                    // Bottom chrome. Insets math (master):
                    //   bottomPadding = composerHeight + keyboard
                    // Composer measure includes island + gap + safe-bottom.
                    // [keyboard] is IME height or emoji-panel target from the
                    // height store (Telegram kbd_height) — never live IME=0
                    // while the panel is open.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          ChatComposer(
                            key: _composerKey,
                            selection: _selection,
                            dataSource: _dataSource!,
                            onSend: _handleSendMessage,
                            onEditSelected: _handleEditSelected,
                            onSizeChanged: insets.setComposerHeight,
                            onEmojiPressed: _toggleEmojiPanel,
                            emojiIconState: _emojiIconState,
                            onFieldTapWhileEmojiOpen: _emojiPanelOpen
                                ? _onInputTapWhileEmojiOpen
                                : null,
                          ),
                          // Keyboard / emoji slot — one term only. Do not also
                          // pad the composer with the same inset (would double).
                          ValueListenableBuilder<double>(
                            valueListenable: insets.keyboard,
                            builder: (context, keyboard, child) => SizedBox(
                              height: keyboard + bottomPad,
                              child: child,
                            ),
                            child: RepaintBoundary(
                              child: EmojiPanel(
                                key: _emojiPanelKey,
                                open: _emojiPanelOpen,
                                controller: bottomInsetController,
                                store: keyboardHeightStore,
                                allow: _emojiAllow,
                                labels: EmojiPanelLabels.russian,
                                dataSource: _emojiDataSource,
                                onEmojiSelected: (glyph) {
                                  _composerKey.currentState?.insertText(glyph);
                                },
                                onBackspace: () {
                                  _composerKey.currentState?.backspace();
                                },
                                callbacks: EmojiPanelCallbacks(
                                  onStickerSettings: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Sticker settings'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  onSearchClosed: () {
                                    _composerKey.currentState
                                        ?.hideKeyboardRetainingFocus();
                                  },
                                ),
                                onTabChanged: (tab) {
                                  setState(() => _lastEmojiTab = tab);
                                },
                                onOpenChanged: _onEmojiPanelOpenChanged,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Contextual selection bar — overlays the top. [headerReserve]
                    // is driven every animation frame so the floating day header
                    // tracks the slide.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SelectionAppBar(
                        selection: _selection,
                        topInset: insets.headerReserve,
                        onCopy: _copySelected,
                        onEdit: _editSelectedFromBar,
                        onDelete: () =>
                            _handleDeleteSelected(_selection.selectedIds),
                      ),
                    ),
                    // Demo: search + bubble radius — top-right chrome.
                    // Position against [chromeTop] (not [topPadding]) so search
                    // reserve does not push this row further down.
                    // [Positioned] must be a *direct* Stack child; wrapping it in
                    // ValueListenableBuilder makes the builder expand and cover
                    // the chat.
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
                                  icon: const Icon(
                                    Icons.rounded_corner,
                                    size: 20,
                                  ),
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
                        builder: (context, chromeTop, _) =>
                            ValueListenableBuilder<bool>(
                              valueListenable: search.select(
                                (s) => s.maybeMap(
                                  closed: (_) => false,
                                  orElse: () => true,
                                ),
                              ),
                              builder: (context, isOpen, _) {
                                if (!isOpen) return const SizedBox.shrink();
                                // Position against chromeTop; measure only the
                                // local pad + field into searchReserve.
                                return Padding(
                                  padding: EdgeInsets.only(top: chromeTop),
                                  child: MeasureSize(
                                    onChange: (size) =>
                                        insets.setSearchReserve(size.height),
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
                ),
              ),
            ),
          ),
        ),
      ),
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
      insets.setSearchReserve(0);
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
