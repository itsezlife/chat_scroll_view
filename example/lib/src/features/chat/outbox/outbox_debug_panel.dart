import 'dart:async';

import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_server_script_sheet.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_transfers.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_upload_transport.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/outbox_debug_actions.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_view.dart';
import 'package:chat_scroll_view_example/src/features/logs/view/journal_page.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// The outbox debug panel (debug builds): what the outbox holds for the
/// open chat (`debugSnapshot(chatId)`) beside what the transfer engine
/// holds (`debugSnapshot()`), both read again every [refresh], with their
/// counters, and the actions a device check needs: kill the process in
/// 3 s, cut the engine's network, act out a system interruption, arm the
/// fake server's scripts and switch the in-process transport.
///
/// Shows no user content: the snapshots carry none (ids, states, counts),
/// and the panel adds none. A row of the tail opens the logs of its
/// message.
class OutboxDebugPanel extends StatefulWidget {
  /// The panel over [outbox]'s [chatId].
  const OutboxDebugPanel({
    required this.outbox,
    required this.chatId,
    required this.actions,
    required this.journal,
    this.transport,
    this.refresh = defaultRefresh,
    super.key,
  });

  /// The outbox and its fake server.
  final DemoOutbox outbox;

  /// The open chat.
  final String chatId;

  /// The actions, and the engine's snapshot.
  final OutboxDebugActions actions;

  /// The journal a row's logs are read from.
  final DiagnosticsJournal journal;

  /// The in-process upload transport, for its switches; null when the
  /// engine has none (a test's fake outbox).
  final DemoUploadTransport? transport;

  /// How often the snapshots are read again.
  final Duration refresh;

  /// The refresh period unless given.
  static const Duration defaultRefresh = Duration(milliseconds: 500);

  /// Key of the kill button.
  static const ValueKey<String> killKey = ValueKey('outbox-debug-kill');

  /// Key of the network cut switch.
  static const ValueKey<String> cutKey = ValueKey('outbox-debug-cut');

  /// Key of the system interruption button.
  static const ValueKey<String> interruptKey = ValueKey(
    'outbox-debug-interrupt',
  );

  /// Key of the button that fails the transport's next call.
  static const ValueKey<String> failNextKey = ValueKey(
    'outbox-debug-fail-next',
  );

  /// Key of the latency choice of [milliseconds].
  static ValueKey<String> latencyKey(int milliseconds) =>
      ValueKey('outbox-debug-latency-$milliseconds');

  /// Key of the tail row of [clientMessageId].
  static ValueKey<String> rowKey(String clientMessageId) =>
      ValueKey('outbox-debug-row-$clientMessageId');

  /// Key of the counter [name]'s row; its value is under [valueKey].
  static ValueKey<String> counterKey(String name) =>
      ValueKey('outbox-debug-counter-$name');

  /// Key of a counter row's value.
  static const ValueKey<String> valueKey = ValueKey('outbox-debug-value');

  /// Key of the chat chrome's button that opens the panel.
  static const ValueKey<String> openKey = ValueKey('outbox-debug-open');

  /// The panel as a route, under a chrome text root.
  static Route<void> route({
    required DemoOutbox outbox,
    required String chatId,
    required OutboxDebugActions actions,
    required DiagnosticsJournal journal,
    DemoUploadTransport? transport,
  }) => MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'outbox/debug'),
    builder: (_) => ChromeTextRoot(
      child: OutboxDebugPanel(
        outbox: outbox,
        chatId: chatId,
        actions: actions,
        journal: journal,
        transport: transport,
      ),
    ),
  );

  @override
  State<OutboxDebugPanel> createState() => _OutboxDebugPanelState();
}

class _OutboxDebugPanelState extends State<OutboxDebugPanel> {
  late OutboxDebugSnapshot _outbox = _readOutbox();
  late TransfersDebugSnapshot? _engine = widget.actions.engineSnapshot();
  late final Timer _$timer;
  int? _interrupted;

  static const List<int> _latencies = [0, 300, 1000, 3000];

  OutboxDebugSnapshot _readOutbox() =>
      widget.outbox.outbox.debugSnapshot(widget.chatId);

  @override
  void initState() {
    super.initState();
    _$timer = Timer.periodic(widget.refresh, (_) => _read());
  }

  void _read() {
    if (!mounted) return;
    setState(() {
      _outbox = _readOutbox();
      _engine = widget.actions.engineSnapshot();
    });
  }

  @override
  void dispose() {
    _$timer.cancel();
    super.dispose();
  }

  void _openLogs(String clientMessageId) => unawaited(
    Navigator.of(context).push(
      JournalPage.route(
        journal: widget.journal,
        filter: JournalFilter.ofOutgoing(clientMessageId),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = ChromeTypography.of(context).copyWith(color: colors.onSurface);
    final small = base.copyWith(fontSize: 12);
    final heading = base.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colors.primary,
    );
    final actions = widget.actions;
    final chatId = widget.chatId;
    final outbox = _outbox;
    final engine = _engine;
    final uploads = engine?.uploads;
    final counters = outbox.counters;

    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Text(title, style: heading),
    );

    Widget rows(Map<String, String> rows) => Column(
      children: [
        for (final MapEntry(:key, :value) in rows.entries)
          _Row(label: key, value: value, style: small),
      ],
    );

    Widget counter(String name, String label, String value) => _Row(
      key: OutboxDebugPanel.counterKey(name),
      label: label,
      value: value,
      style: small,
    );

    final transport = widget.transport;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Outbox debug',
          style: base.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Logs',
            icon: const Icon(Icons.article_outlined),
            onPressed: () => unawaited(
              Navigator.of(
                context,
              ).push(JournalPage.route(journal: widget.journal)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // --- Actions -------------------------------------------------------
          section('Actions'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: actions.killPending,
                builder: (context, pending, _) => FilledButton.tonal(
                  key: OutboxDebugPanel.killKey,
                  onPressed: () =>
                      pending ? actions.cancelKill() : actions.killIn(chatId),
                  child: Text(
                    pending ? 'Killing in 3 s: cancel' : 'Kill in 3 s',
                    style: base,
                  ),
                ),
              ),
              FilledButton.tonal(
                key: OutboxDebugPanel.interruptKey,
                onPressed: actions.hasEngine
                    ? () => setState(
                        () => _interrupted = actions.simulateSystemInterruption(
                          chatId,
                        ),
                      )
                    : null,
                child: Text('Simulate system interruption', style: base),
              ),
              FilledButton.tonal(
                key: DemoServerScriptSheet.openKey,
                onPressed: () => unawaited(
                  DemoServerScriptSheet.show(
                    context,
                    server: widget.outbox.server,
                    chatId: chatId,
                  ),
                ),
                child: Text('Fake server scripts', style: base),
              ),
            ],
          ),
          if (_interrupted case final paused?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('The interruption paused $paused jobs', style: small),
            ),
          ValueListenableBuilder<bool>(
            valueListenable: actions.networkCut,
            builder: (context, cut, _) => SwitchListTile(
              key: OutboxDebugPanel.cutKey,
              contentPadding: EdgeInsets.zero,
              title: Text('Cut the network', style: base),
              subtitle: Text(
                "The engine's requests fail and it reads offline",
                style: small,
              ),
              value: cut,
              onChanged: actions.hasEngine
                  ? (cut) => cut
                        ? actions.cutNetwork(chatId)
                        : actions.restoreNetwork(chatId)
                  : null,
            ),
          ),

          // --- Transport -----------------------------------------------------
          section('Upload transport'),
          rows({
            'Default transport': switch (DemoTransfers.devServer) {
              final server? => 'tus to $server',
              null => 'in process',
            },
            if (transport != null) ...{
              'Offline': '${transport.offline}',
              'Calls to fail': '${transport.failNext}',
              'Latency': '${transport.latency.inMilliseconds} ms',
            },
          }),
          if (transport != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: OutboxDebugPanel.failNextKey,
                  onPressed: () => setState(() => transport.failNext++),
                  child: Text('Fail the next call', style: base),
                ),
                for (final ms in _latencies)
                  OutlinedButton(
                    key: OutboxDebugPanel.latencyKey(ms),
                    onPressed: () => setState(
                      () => transport.latency = Duration(milliseconds: ms),
                    ),
                    child: Text('$ms ms', style: base),
                  ),
              ],
            ),

          // --- Counters ------------------------------------------------------
          section('Counters'),
          counter(
            'partsInFlight',
            'Parts in flight',
            '${uploads?.partsInFlight ?? 0}',
          ),
          counter(
            'partRetries',
            'Part retries',
            '${uploads?.partRetries ?? 0}',
          ),
          counter(
            'restartsFromZero',
            'Restarts from zero',
            '${uploads?.restartsFromZero ?? 0}',
          ),
          counter('retries', 'Message retries', '${counters.retries}'),
          counter('rebases', 'Rebases', switch (counters.rebases) {
            final rebases when rebases.isEmpty => '0',
            final rebases => [
              for (final MapEntry(:key, :value) in rebases.entries)
                '$key $value',
            ].join(', '),
          }),
          counter('conflicts', 'Conflicts', '${counters.conflicts}'),
          counter('restores', 'Restores', '${counters.restores}'),
          counter('accepted', 'Accepted', '${counters.accepted}'),
          counter('cancels', 'Cancels', '${counters.cancels}'),

          // --- Outbox --------------------------------------------------------
          section('Outbox: chat $chatId'),
          rows({
            'Strategy': outbox.strategy ?? '-',
            'Tip': '${outbox.tip ?? '-'}',
            'Publisher registered': '${outbox.publisherRegistered ?? '-'}',
            'Send in flight': '${outbox.sendInFlight ?? '-'}',
            'Rows in the tail': '${outbox.tail.length}',
          }),
          for (final row in outbox.tail)
            _TailRow(
              key: OutboxDebugPanel.rowKey(row.clientMessageId),
              row: row,
              style: small,
              onTap: () => _openLogs(row.clientMessageId),
            ),

          // --- Engine --------------------------------------------------------
          section('Engine'),
          if (engine == null)
            Text('No engine (a fake outbox)', style: small)
          else
            ..._engineSections(engine, section, rows, small),
        ],
      ),
    );
  }

  List<Widget> _engineSections(
    TransfersDebugSnapshot engine,
    Widget Function(String) section,
    Widget Function(Map<String, String>) rows,
    TextStyle small,
  ) {
    final uploads = engine.uploads;
    final connections = engine.connections;
    final journal = engine.journal;
    final envelope = engine.envelope;
    final reuse = engine.reuse;
    final publish = engine.publish;
    return [
      rows({
        'Online': '${engine.online}',
        'Jobs': '${engine.jobs.length}',
        for (final MapEntry(key: lane, value: queue)
            in (uploads?.lanes ?? const <UploadLane, UploadLaneDebugSnapshot>{})
                .entries)
          'Lane ${lane.name}':
              '${queue.running ?? 'free'}, ${queue.queued} queued',
        if (connections != null)
          'Connections':
              '${connections.downloads} down / ${connections.uploads} up of '
              '${connections.cap}, ${connections.waiting} waiting',
      }),
      section('Journal'),
      rows({
        'Store': journal.store,
        'Bytes': '${journal.bytes}',
        'Records since compaction': '${journal.recordsSinceCompaction}',
        'Last state write': '${journal.lastStateWriteAt ?? '-'}',
        'Last progress flush': '${journal.lastProgressFlushAt ?? '-'}',
      }),
      section('Envelope'),
      rows(switch (envelope) {
        null => {'Envelope': 'none on this platform'},
        final envelope => {
          'State': envelope.state.name,
          'Rule': envelope.rule.name,
          'Kind': envelope.kind?.name ?? '-',
          'Jobs inside': '${envelope.jobs.length}',
          'Started': '${envelope.started}',
          'Ended by the system': '${envelope.endedBySystem}',
        },
      }),
      section('Reuse and publish'),
      rows({
        if (reuse != null) ...{
          'Reuse': reuse.enabled ? 'on' : 'off',
          'Reuse entries': '${reuse.entries}',
          'Reuse hits / misses': '${reuse.hits} / ${reuse.misses}',
        },
        if (publish != null) ...{
          'Publishers': publish.publishers.join(', '),
          'Publish jobs': '${publish.jobs.length}',
          'Awaiting publisher': '${publish.awaitingPublisher.length}',
          'Awaiting owner': '${publish.awaitingOwner.length}',
        },
      }),
      section('Jobs'),
      for (final job in engine.jobs)
        Text(
          '${job.id} ${job.direction.name} ${job.durability.name} '
          '${job.state.runtimeType}${switch (job.tag) {
            final tag? => ' $tag',
            null => '',
          }}',
          style: small,
        ),
      for (final job in publish?.jobs ?? const <PublishJobDebugSnapshot>[])
        Text(
          '${job.id} ${job.state.name}, attempts ${job.attempts}: '
          '${[for (final item in job.items) '${item.item.state.name}${item.reuseHit ? ' (reuse)' : ''}'].join(', ')}',
          style: small,
        ),
    ];
  }
}

/// One row of the provisional tail: its position, identity, status and
/// job, then its items; a tap opens its logs.
class _TailRow extends StatelessWidget {
  const _TailRow({
    required this.row,
    required this.style,
    required this.onTap,
    super.key,
  });

  final OutboxDebugRow row;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '#${row.position} ${row.clientMessageId} ${row.status}'
            '${switch (row.failure) {
              final failure? => ' ($failure)',
              null => '',
            }}${row.fresh ? ', fresh' : ''}, ${row.payloadBytes} bytes',
            style: style.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            'job ${row.jobId ?? '-'} ${row.jobState ?? '-'}'
            ' stage ${row.stage ?? '-'}, attempts ${row.attempts ?? 0}',
            style: style,
          ),
          for (final item in row.items)
            Text(
              '  ${item.mediaItemId} ${item.localKey}'
              ' media ${item.mediaKey ?? '-'}'
              ' transfer ${item.transfer ?? '-'}'
              '${item.sendOriginHeld ?? false ? ', origin held' : ''}',
              style: style,
            ),
        ],
      ),
    ),
  );
}

/// A label and its value on one line.
class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.style,
    super.key,
  });

  final String label;
  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: style)),
        Expanded(
          child: Text(
            value,
            key: OutboxDebugPanel.valueKey,
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
      ],
    ),
  );
}
