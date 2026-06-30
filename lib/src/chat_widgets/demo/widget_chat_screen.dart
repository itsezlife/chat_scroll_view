import 'dart:async';
import 'dart:developer' as dev;

import 'package:chatscrollview/src/backend_chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_scroll/chat_selection_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_keyboard_shortcuts.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/demo/chat_composer.dart';
import 'package:chatscrollview/src/chat_widgets/demo/chat_data_source_extension.dart';
import 'package:chatscrollview/src/chat_widgets/demo/date_separator.dart';
import 'package:chatscrollview/src/chat_widgets/demo/demo_backend_error.dart';
import 'package:chatscrollview/src/chat_widgets/demo/demo_message.dart';
import 'package:chatscrollview/src/chat_widgets/demo/measure_size.dart';
import 'package:chatscrollview/src/chat_widgets/demo/new_messages_pill.dart';
import 'package:chatscrollview/src/chat_widgets/demo/selection_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Demo screen for the widget-based [ChatScrollView] — the chat viewport,
/// a bottom composer, and a contextual selection bar, wired together.
class WidgetChatScreen extends StatefulWidget {
  /// Demo route wiring [ChatScrollView], composer, and selection chrome.
  const WidgetChatScreen({super.key});

  @override
  State<WidgetChatScreen> createState() => _WidgetChatScreenState();
}

class _WidgetChatScreenState extends State<WidgetChatScreen> {
  ChatDataSource? _dataSource;
  late final ChatScrollController _controller;
  late final ChatSelectionController _selection;

  /// Bottom inset reserved inside the viewport — kept in sync with the
  /// composer's measured height so the newest message clears it.
  final ValueNotifier<double> _bottomInset = ValueNotifier<double>(96);

  /// Top inset reserved inside the viewport — kept in sync with the
  /// selection app bar's measured height so the floating day header clears it.
  final ValueNotifier<double> _topInset = ValueNotifier<double>(0);
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
    _selection = ChatSelectionController();
    _pillLastSeenBaseline.addListener(_onPillBaselineChanged);
    _init();
  }

  @override
  void dispose() {
    _pillLastSeenBaseline.removeListener(_onPillBaselineChanged);
    _flushPendingLastRead();
    _persistLastReadTimer?.cancel();
    _pillLastSeenBaseline.dispose();
    _bottomInset.dispose();
    _topInset.dispose();
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
      final backend = await BackendChatDataSource.connect(
        client: Supabase.instance.client,
      );

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
      final lastRead = await backend.getLastReadMessageId();

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

  Future<void> _handleSendMessage(String text) async {
    final backend = _dataSource;
    if (backend is! BackendChatDataSource) return;
    try {
      await backend.sendMessage(text);
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

  /// Stable per-state tear-off — same reference for the widget's lifetime,
  /// so the viewport's skip-rebuild cache stays warm across parent rebuilds.
  /// Consults the previous message via the data source to suppress repeated
  /// sender/avatar for messages in the same run.
  Widget _buildMessage(
    BuildContext context,
    int id,
    IChatMessage? message,
    ChatMessageStatus status,
  ) {
    if (status.isAbsent) return const SizedBox.shrink();
    if (message == null) return const DemoShimmerBubble();
    final prev = _dataSource?.getMessage(id - 1);
    final isFirstInRun = prev?.sender != message.sender;
    return DemoMessageBubble(message: message, isFirstInRun: isFirstInRun);
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
        Navigator.pop(context);
      },
      child: Scaffold(
        floatingActionButtonLocation: .endFloat,
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 96),
          child: Align(
            alignment: .bottomRight,
            child: Column(
              mainAxisAlignment: .end,
              mainAxisSize: .min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fab-up',
                  onPressed: () {
                    _controller.animateTo(6003, alignment: .5);
                  },
                  tooltip: 'Scroll to top',
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  child: const Icon(Icons.arrow_upward, size: 18),
                ),
                FloatingActionButton.small(
                  heroTag: 'fab-down',
                  onPressed: () {
                    if (_dataSource?.newestKnownId case final newestKnownId?) {
                      _controller.animateTo(newestKnownId, highlight: false);
                    }
                  },
                  tooltip: 'Scroll to bottom',
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  child: const Icon(Icons.arrow_downward, size: 18),
                ),
              ],
            ),
          ),
        ),
        body: Stack(
          children: <Widget>[
            // Chat fills the screen; the composer is stacked over its bottom.
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: ChatKeyboardShortcuts(
                  controller: _controller,
                  reverse: true,
                  preserveExternalFocus: true,
                  child: ChatScrollView(
                    reverse: true,
                    dataSource: _dataSource!,
                    controller: _controller,
                    selectionController: _selection,
                    bottomPadding: _bottomInset,
                    topPadding: _topInset,
                    messageBuilder: _buildMessage,
                    chunkErrorBuilder: _buildChunkError,
                    emptyBuilder: _buildEmpty,
                    loadingBuilder: _buildInitialSkeleton,
                    dateSeparatorBuilder: (context, bucket, date) =>
                        DateSeparator(date: date),
                  ),
                ),
              ),
            ),
            // Bottom composer — overlaid, not a column sibling. Its measured
            // height feeds the viewport's bottom inset so the newest message
            // always clears it (and any future attachment previews).
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MeasureSize(
                onChange: (size) => _bottomInset.value = size.height,
                child: ChatComposer(
                  selection: _selection,
                  dataSource: _dataSource!,
                  onSend: _handleSendMessage,
                ),
              ),
            ),
            // New-messages pill — surfaces above the composer when the user
            // is scrolled away and newer messages have arrived.
            NewMessagesPill(
              controller: _controller,
              dataSource: _dataSource!,
              bottomInset: _bottomInset,
              lastSeenNewestId: _pillLastSeenBaseline,
            ),
            // Contextual selection bar — overlays the top. [topInset] is driven
            // every animation frame so the floating day header tracks the slide.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SelectionAppBar(
                selection: _selection,
                topInset: _topInset,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
