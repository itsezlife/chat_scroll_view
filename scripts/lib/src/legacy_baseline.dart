import 'package:meta/meta.dart';
import 'package:workspace_check/src/violation.dart';

/// A violation that exists in the tree today and is excused until the code
/// causing it is removed.
@immutable
final class LegacyException {
  /// Excuses the violation of [rule] about [subject] until [removedBy] lands.
  const LegacyException(this.rule, this.subject, {required this.removedBy});

  /// The rule the excused violation breaches.
  final LintRule rule;

  /// The excused violation's [Violation.subject], verbatim.
  final String subject;

  /// What deletes the offending code (and so this exception).
  final String removedBy;
}

/// Known violations of the current tree, excused until the code causing them
/// is removed.
///
/// A ratchet: the list can only shrink. [apply] reports every violation that
/// is not on it, and every entry that no longer matches a violation, so the
/// gate fails on new violations and an excuse cannot outlive its code. The
/// change that removes the offending code deletes its entry in the same edit.
abstract final class LegacyBaseline {
  /// The excused violations of the current tree.
  static const List<LegacyException> current = <LegacyException>[
    LegacyException(
      LintRule.pluginDependencyOutsideAdapter,
      'chat_chrome -> shared_preferences',
      removedBy: 'issue 32 (chat_chrome is deleted)',
    ),
    LegacyException(
      LintRule.pluginDependencyOutsideAdapter,
      'chat_scroll_view_example -> shared_preferences',
      removedBy:
          'the example host\'s own persisted settings move onto '
          'kv_shared_preferences (no issue owns this yet)',
    ),
    LegacyException(
      LintRule.fakeExportedOutsideTesting,
      'packages/panel_catalog/lib/panel_catalog.dart exports '
      'src/data/fake_catalog_data_source.dart',
      removedBy:
          'issue 16 (FakeCatalogDataSource becomes a snapshot fake in '
          'testing.dart)',
    ),
  ];

  /// [found] without the violations [legacy] excuses, plus a
  /// [LintRule.staleLegacyException] for every exception that excused nothing.
  ///
  /// An exception excuses exactly one matching violation, so a second identical
  /// violation is still reported.
  static List<Violation> apply(
    List<Violation> found, {
    List<LegacyException> legacy = current,
  }) {
    final unused = List<LegacyException>.of(legacy);
    final remaining = <Violation>[];
    for (final violation in found) {
      final at = unused.indexWhere(
        (e) => e.rule == violation.rule && e.subject == violation.subject,
      );
      if (at >= 0) {
        unused.removeAt(at);
      } else {
        remaining.add(violation);
      }
    }
    return <Violation>[
      ...remaining,
      for (final stale in unused)
        Violation(
          LintRule.staleLegacyException,
          '${stale.rule.name}: ${stale.subject} (removed by ${stale.removedBy})',
        ),
    ];
  }
}
