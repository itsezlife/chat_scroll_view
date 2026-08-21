import 'dart:async';
import 'dart:developer' as dev;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
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

/// Demo screen for the widget-based [ChatScrollView] — the chat viewport,
/// a bottom composer, and a contextual selection bar, wired together.
class WidgetChatScreen extends StatefulWidget {
  /// Demo route wiring [ChatScrollView], composer, and selection chrome.
  const WidgetChatScreen({super.key});

  @override
  State<WidgetChatScreen> createState() => _WidgetChatScreenState();
}

class _WidgetChatScreenState extends State<WidgetChatScreen>
    with ChatViewportInsetsBinding {
  ChatDataSource? _dataSource;
  late final ChatScrollController _controller;
  late final ChatSelectionController _selection;
  final GlobalKey<ChatComposerState> _composerKey =
      GlobalKey<ChatComposerState>();

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
  void initState() {
    super.initState();
    _controller = ChatScrollController();
    _selection = ChatSelectionController()..selectionCap = 100;
    _pillLastSeenBaseline.addListener(_onPillBaselineChanged);
    _init();
  }

  @override
  void dispose() {
    _pillLastSeenBaseline.removeListener(_onPillBaselineChanged);
    _flushPendingLastRead();
    _persistLastReadTimer?.cancel();
    _pillLastSeenBaseline.dispose();
    _search?.dispose();
    _controller.dispose();
    _selection.dispose();
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
      // final backend = GeneratedChatDataSource(messageCount: 5);

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
          // No-op, since no navigation is supported in this demo.
        },
        child: ChatScrollTheme(
          data: chatScrollTheme.copyWith(message: newMessageTheme),
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
                  // Bottom composer — overlaid, not a column sibling. Measured
                  // height is reserved inset; overlay chrome reads the same
                  // bottomPadding and does not add to it.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ChatComposer(
                      key: _composerKey,
                      bottomInset: insets.keyboard,
                      selection: _selection,
                      dataSource: _dataSource!,
                      onSend: _handleSendMessage,
                      onDeleteSelected: _handleDeleteSelected,
                      onEditSelected: _handleEditSelected,
                      onSizeChanged: insets.setComposerHeight,
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
                    ),
                  ),
                  // Demo: search + bubble radius — top-right chrome.
                  // [Positioned] must be a *direct* Stack child; wrapping it in
                  // ValueListenableBuilder makes the builder expand and cover
                  // the chat.
                  Positioned(
                    top: 0,
                    right: 12,
                    child: ValueListenableBuilder<double>(
                      valueListenable: insets.topPadding,
                      builder: (context, topPadding, child) => Padding(
                        padding: EdgeInsets.only(top: topPadding + 8),
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
                      valueListenable: insets.topPadding,
                      builder: (context, topPadding, _) =>
                          ValueListenableBuilder<bool>(
                            valueListenable: search.select(
                              (s) => s.maybeMap(
                                closed: (_) => false,
                                orElse: () => true,
                              ),
                            ),
                            builder: (context, isOpen, _) {
                              if (!isOpen) return const SizedBox.shrink();
                              return Padding(
                                padding: EdgeInsets.only(top: topPadding + 8),
                                child: const ChatSearchBar(),
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
    );
  }

  void _onSearchStateChanged(
    BuildContext context,
    ChatSearchController controller,
    ChatSearchState previous,
    ChatSearchState current,
  ) {
    final prevHit = previous.maybeMap(
      populated: (s) =>
          (id: s.hits[s.index], index: s.index, len: s.hits.length),
      orElse: () => null,
    );
    final nextHit = current.maybeMap(
      populated: (s) =>
          (id: s.hits[s.index], index: s.index, len: s.hits.length),
      orElse: () => null,
    );
    if (nextHit == null) return;
    if (prevHit != null &&
        prevHit.id == nextHit.id &&
        prevHit.index == nextHit.index &&
        prevHit.len == nextHit.len) {
      return;
    }
    unawaited(
      _controller.animateTo(
        nextHit.id,
        highlight: true,
        loadPolicy: AnimateToLoadPolicy.immediate,
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
  });

  final bool pageDownChromeVisible;
  final ValueListenable<double> bottomInset;
  final Widget pageDown;

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
        onSearchUp: search.goOlder,
        onSearchDown: search.goNewer,
        searchHitCount: slice.hitCount,
        searchUpEnabled: slice.index > 0,
        searchDownEnabled:
            slice.hitCount > 0 && slice.index < slice.hitCount - 1,
        pageDown: pageDown,
      ),
    );
  }
}
