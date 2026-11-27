import 'package:chat_scroll_view_example/src/features/logs/model/journal_export.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_record.dart';
import 'package:chat_scroll_view_example/src/features/logs/widget/journal_record_row.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The whole of one record: level, time, source, operation, ids, fields,
/// error and stack. Copy puts the record on the clipboard as indented JSON.
class JournalRecordDetailsDialog extends StatelessWidget {
  /// The dialog of [record].
  const JournalRecordDetailsDialog({required this.record, super.key});

  /// The record shown.
  final JournalRecord record;

  /// Opens the dialog of [record], its page under a chrome text root.
  static Future<void> show(BuildContext context, JournalRecord record) =>
      showDialog<void>(
        useRootNavigator: false,
        context: context,
        builder: (_) =>
            ChromeTextRoot(child: JournalRecordDetailsDialog(record: record)),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = ChromeTypography.of(context).copyWith(
      color: theme.colorScheme.onSurface,
      // Selectable text asks for a baseline of a style that does not
      // inherit.
      textBaseline: TextBaseline.alphabetic,
    );
    final small = base.copyWith(
      fontSize: 12,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final action = base.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    return AlertDialog(
      title: Text(
        '${record.category}.${record.op}',
        style: base.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          _Field(
            label: 'Level',
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: JournalLevelBadge(level: record.level),
            ),
          ),
          _Field(
            label: 'Time',
            child: Text(record.time.journalDateTime, style: base),
          ),
          _Field(
            label: 'Source',
            child: Text(record.source.name, style: base),
          ),
          if (!record.correlation.isEmpty)
            _Field(
              label: 'Ids',
              child: SelectableText(
                [
                  for (final (name, id) in record.correlation.entries)
                    '$name: $id',
                ].join('\n'),
                style: small,
              ),
            ),
          if (record.fields.isNotEmpty)
            _Field(
              label: 'Fields',
              child: SelectableText(
                [
                  for (final MapEntry(:key, :value) in record.fields.entries)
                    '$key: $value',
                ].join('\n'),
                style: small,
              ),
            ),
          if (record.error case final error?)
            _Field(
              label: 'Error',
              child: SelectableText(error, style: small),
            ),
          if (record.stackTrace case final trace?)
            _Field(
              label: 'Stack trace',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(trace, style: small),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: JournalExport.entryText(record)),
            );
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text('Copied', style: base)));
            }
          },
          child: Text('Copy', style: action),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: action),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(
          label,
          style: ChromeTypography.of(context).copyWith(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        child,
      ],
    );
  }
}
