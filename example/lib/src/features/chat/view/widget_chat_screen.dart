import 'dart:async';
import 'dart:developer' as dev;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/backend_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/chat_data_source_extension.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/comments_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets_binding.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_composer.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/date_separator.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_backend_error.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/new_messages_pill.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/selection_app_bar.dart';
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

  bool _loading = true;
  String? _errorMessage;

  /// Highest message id counted as read for [NewMessagesPill]. Seeded to
  /// stored last-read on off-tail open; advanced by the pill while scrolling.
  final ValueNotifier<int?> _pillLastSeenBaseline = ValueNotifier<int?>(null);

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
    return DemoMessageBubble(
      message: message,
      isLastInRun: runLayout.isLastInSenderRun,
      isFirstInRun: runLayout.isFirstInSenderRun,
    );
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
    if (_loading || _dataSource == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final hasSelection = _selection.isSelectionMode;
        if (hasSelection) {
          _selection.clear();
          return;
        }
        // No-op, since no navigation is supported in this demo.
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
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
            // Bottom composer — overlaid, not a column sibling. Measured
            // height is reserved inset; overlay chrome reads the same
            // bottomPadding and does not add to it.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ChatComposer(
                bottomInset: insets.keyboard,
                selection: _selection,
                dataSource: _dataSource!,
                onSend: _handleSendMessage,
                onDeleteSelected: _handleDeleteSelected,
                onEditSelected: _handleEditSelected,
                onSizeChanged: insets.setComposerHeight,
              ),
            ),
            // New-messages pill — surfaces above the composer when the user
            // is scrolled away and newer messages have arrived.
            NewMessagesPill(
              controller: _controller,
              dataSource: _dataSource!,
              bottomInset: insets.bottomPadding,
              lastSeenNewestId: _pillLastSeenBaseline,
            ),
            // Scroll shortcuts — stacked above the composer, clearing its inset.
            Positioned(
              right: 16,
              bottom: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: insets.bottomPadding,
                builder: (context, bottomInset, child) => Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: child,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filled(
                      onPressed: () {
                        _controller.animateTo(6002, alignment: .5);
                      },
                      tooltip: 'Scroll to top',
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_upward, size: 18),
                    ),
                    IconButton.filled(
                      onPressed: () {
                        if (_dataSource?.newestKnownId
                            case final newestKnownId?) {
                          _controller.animateTo(
                            newestKnownId,
                            highlight: false,
                          );
                        }
                      },
                      tooltip: 'Scroll to bottom',
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_downward, size: 18),
                    ),
                  ],
                ),
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
          ],
        ),
      ),
    );
  }
}
