import 'dart:async';
import 'dart:convert';

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view_example/src/common/widgets/listen_value_builder.dart';
import 'package:chat_scroll_view_example/src/features/logs/controller/journal_view_controller.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_view.dart';
import 'package:chat_scroll_view_example/src/features/logs/widget/journal_record_details_dialog.dart';
import 'package:chat_scroll_view_example/src/features/logs/widget/journal_record_row.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:listen/listen.dart' as listen;
import 'package:share_plus/share_plus.dart';

/// The Logs screen: the journal's records under a filter of level, category
/// and correlation ids, newest first, with pause, details and export.
///
/// Opened from a chat with [capabilities], it shows the chat's capabilities
/// at the top, so a log of a denial reads beside the rights that caused it.
class JournalPage extends StatefulWidget {
  /// The screen over [journal], starting at [filter] (everything when null).
  const JournalPage({
    required this.journal,
    this.filter,
    this.capabilities,
    this.share = shareSheet,
    super.key,
  });

  /// The records.
  final DiagnosticsJournal journal;

  /// The filter the screen opens with.
  final JournalFilter? filter;

  /// The capabilities of the chat the screen was opened from.
  final listen.ValueListenable<ChatCapabilities>? capabilities;

  /// Where an export goes; the platform's share sheet unless a test
  /// replaces it.
  final JournalShare share;

  /// The page as a route, under a chrome text root.
  static Route<void> route({
    required DiagnosticsJournal journal,
    JournalFilter? filter,
    listen.ValueListenable<ChatCapabilities>? capabilities,
    JournalShare share = shareSheet,
  }) => MaterialPageRoute<void>(
    builder: (_) => ChromeTextRoot(
      child: JournalPage(
        journal: journal,
        filter: filter,
        capabilities: capabilities,
        share: share,
      ),
    ),
  );

  /// Shares [file] through the platform's share sheet.
  static Future<void> shareSheet(JournalExportFile file, {Rect? origin}) =>
      SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              file.bytes,
              mimeType: file.mimeType,
              name: file.name,
            ),
          ],
          fileNameOverrides: [file.name],
          sharePositionOrigin: origin,
        ),
      );

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  late final JournalViewController _controller = JournalViewController(
    journal: widget.journal,
    share: widget.share,
    filter: widget.filter,
  );

  /// Distance from the live edge past which the list holds still: about one
  /// row.
  static const double _pauseOffset = 56;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  // Offset 0 is the live edge, where new records arrive. Away from it the
  // list holds still, so rows stay under the finger.
  void _onScroll() => _scroll.offset > _pauseOffset
      ? _controller.pause()
      : _controller.resume();

  void _showNew() {
    _controller.resume();
    if (!_scroll.hasClients) return;
    unawaited(
      _scroll.animateTo(
        0,
        duration: Durations.medium2,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _export(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject();
    unawaited(
      _controller.export(
        origin: switch (box) {
          final RenderBox box when box.hasSize =>
            box.localToGlobal(Offset.zero) & box.size,
          _ => null,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = ChromeTypography.of(context).copyWith(
      color: theme.colorScheme.onSurface,
      // An editable (the id field) asks for a baseline of a style that does
      // not inherit.
      textBaseline: TextBaseline.alphabetic,
    );
    final count = base.copyWith(
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Logs',
          style: base.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        actions: [
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _controller.isPaused ? 'Resume' : 'Pause',
                  onPressed: _controller.isPaused
                      ? _showNew
                      : _controller.pause,
                  icon: Icon(
                    _controller.isPaused ? Icons.play_arrow : Icons.pause,
                  ),
                ),
                Builder(
                  builder: (buttonContext) => IconButton(
                    key: const ValueKey('journal-export'),
                    tooltip: 'Export',
                    onPressed:
                        _controller.isExporting ||
                            _controller.snapshot.visible.isEmpty
                        ? null
                        : () => _export(buttonContext),
                    icon: const Icon(Icons.ios_share),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _NewRecordsButton(
        controller: _controller,
        onPressed: _showNew,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.capabilities case final capabilities?)
            _CapabilitiesHeader(capabilities: capabilities),
          _IdFilterBar(controller: _controller),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LevelFilterBar(controller: _controller),
                _CategoryFilterBar(controller: _controller),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                final snapshot = _controller.snapshot;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Text(
                        'Showing ${snapshot.visible.length} of '
                        '${snapshot.total}',
                        style: count,
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _RecordList(snapshot: snapshot, scroll: _scroll),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({required this.snapshot, required this.scroll});

  final JournalSnapshot snapshot;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    if (snapshot.visible.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            snapshot.total == 0
                ? 'No events yet. What the chat reports shows up here.'
                : 'No matches. Turn more levels or categories on, or clear '
                      'the id.',
            textAlign: TextAlign.center,
            style: ChromeTypography.of(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scroll,
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 64,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: snapshot.visible.length,
      itemBuilder: (context, index) {
        final record = snapshot.visible[index];
        return JournalRecordRow(
          record: record,
          onTap: () => JournalRecordDetailsDialog.show(context, record),
        );
      },
    );
  }
}

/// The chat's capabilities, as `ChatCapabilities.debugDescribe` puts them,
/// one group per line.
class _CapabilitiesHeader extends StatelessWidget {
  const _CapabilitiesHeader({required this.capabilities});

  final listen.ValueListenable<ChatCapabilities> capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ChromeTypography.of(context).copyWith(
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
      textBaseline: TextBaseline.alphabetic,
    );
    return ListenValueBuilder(
      listenable: capabilities,
      builder: (context, value) => Container(
        key: const ValueKey('journal-capabilities'),
        color: theme.colorScheme.surfaceContainerHigh,
        constraints: const BoxConstraints(maxHeight: 112),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SelectableText(
            [
              for (final MapEntry(:key, :value)
                  in value.debugDescribe().entries)
                '$key: ${switch (value) {
                  final String text => text,
                  _ => jsonEncode(value),
                }}',
            ].join('\n'),
            style: style,
          ),
        ),
      ),
    );
  }
}

/// The correlation id filter: a kind, an id, and the ids already set.
class _IdFilterBar extends StatefulWidget {
  const _IdFilterBar({required this.controller});

  final JournalViewController controller;

  @override
  State<_IdFilterBar> createState() => _IdFilterBarState();
}

class _IdFilterBarState extends State<_IdFilterBar> {
  JournalIdKind _kind = JournalIdKind.scrollId;
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _apply() {
    widget.controller.filterById(_kind, _text.text);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = ChromeTypography.of(context).copyWith(
      color: theme.colorScheme.onSurface,
      // An editable (the id field) asks for a baseline of a style that does
      // not inherit.
      textBaseline: TextBaseline.alphabetic,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 8,
            children: [
              DropdownButton<JournalIdKind>(
                value: _kind,
                style: base,
                onChanged: (kind) => setState(() => _kind = kind ?? _kind),
                items: [
                  for (final kind in JournalIdKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(kind.name, style: base),
                    ),
                ],
              ),
              Expanded(
                child: TextField(
                  key: const ValueKey('journal-id'),
                  controller: _text,
                  style: base,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Filter by id',
                    hintStyle: base.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) => Wrap(
              spacing: 8,
              children: [
                for (final MapEntry(:key, :value)
                    in widget.controller.filter.ids.entries)
                  InputChip(
                    label: Text('${key.name}=$value', style: base),
                    onDeleted: () => widget.controller.filterById(key, ''),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One chip per level: tap toggles a level, long-press shows that level
/// alone. Counts are of the records the rest of the filter passes.
class _LevelFilterBar extends StatelessWidget {
  const _LevelFilterBar({required this.controller});

  final JournalViewController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = controller.filter;
    final snapshot = controller.snapshot;
    final base = ChromeTypography.of(context).copyWith(fontSize: 12);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        spacing: 8,
        children: [
          for (final level in ChatEventLevel.values)
            GestureDetector(
              onLongPress: () => controller.soloLevel(level),
              child: FilterChip(
                selected: filter.levels.contains(level),
                showCheckmark: false,
                onSelected: (_) => controller.toggleLevel(level),
                label: Text(
                  '${level.name} ${snapshot.countOf(level)}',
                  style: base.copyWith(color: theme.colorScheme.onSurface),
                ),
                selectedColor: theme
                    .journalLevelColor(level)
                    .withValues(alpha: .16),
                side: BorderSide(
                  color: filter.levels.contains(level)
                      ? theme.journalLevelColor(level)
                      : theme.colorScheme.outlineVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One chip per category present: tap shows that category alone, tap again
/// shows every one.
class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({required this.controller});

  final JournalViewController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final only = controller.filter.categories;
    final categories = {...controller.snapshot.categories, ...?only}.toList()
      ..sort();
    final base = ChromeTypography.of(
      context,
    ).copyWith(fontSize: 12, color: theme.colorScheme.onSurface);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        spacing: 8,
        children: [
          for (final category in categories)
            ChoiceChip(
              selected: only?.contains(category) ?? false,
              showCheckmark: false,
              onSelected: (_) => controller.soloCategory(category),
              label: Text(category, style: base),
            ),
        ],
      ),
    );
  }
}

/// A floating pill with the count of records held back while the list is
/// paused; hidden while there are none.
class _NewRecordsButton extends StatelessWidget {
  const _NewRecordsButton({required this.controller, required this.onPressed});

  final JournalViewController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => AnimatedSwitcher(
      duration: Durations.short4,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: switch (controller.newCount) {
        0 => const SizedBox.shrink(),
        final count => FilledButton.icon(
          key: const ValueKey('journal-new'),
          onPressed: onPressed,
          icon: const Icon(Icons.arrow_upward, size: 18),
          label: Text(
            '$count new',
            style: ChromeTypography.of(context).copyWith(
              color: Theme.of(context).colorScheme.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      },
    ),
  );
}
