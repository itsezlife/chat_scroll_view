import 'package:meta/meta.dart';

/// Every rule the workspace lints can report, with the reason it exists.
///
/// Closed on purpose: [LegacyBaseline] and the tests name rules, and a new
/// lint must add its rule here so a violation always carries its rationale.
enum LintRule {
  /// Workspace members depend on each other in a loop.
  dependencyCycle(
    'Members must form a DAG; a cycle makes build and test order undefined '
    'and couples the packages into one.',
  ),

  /// A leaf package ([DependencyLint]) depends on another workspace member.
  leafDependsOnPackage(
    'content_model, chrome_foundation and composer_editable are leaves: '
    'every other package may depend on the first two, and the editable fork '
    'is a copy of Flutter sources that must stay free of workspace code, so '
    'they depend on no workspace package.',
  ),

  /// An edge the package topology forbids outright.
  forbiddenDependency(
    'The package topology forbids this edge: panel_shell / panel_pages / '
    'panel_presentation stay independent of data payloads, codecs and '
    'fetchers, and panel_catalog stays independent of chrome_foundation '
    '(pages adapt tokens).',
  ),

  /// A member declares a platform-plugin dependency reserved for an adapter.
  pluginDependencyOutsideAdapter(
    'Platform plugins stay behind the seams of content_model: '
    'shared_preferences is declared only by kv_shared_preferences, so logic '
    'packages depend on KeyValueStore and one adapter owns the plugin.',
  ),

  /// A package depends on an adapter that only a host wires.
  hostAdapterOutsideHost(
    'rich_clipboard holds platform code and is wired by the host: packages '
    'take the RichClipboard seam from content_model instead, so no package '
    'but the host reaches a platform channel (ADR 031, ADR 032).',
  ),

  /// A member other than the composer depends on the editable fork.
  composerEditableOutsideComposer(
    'composer_editable is the composer\'s editable and chat_composer is its '
    'only dependent: hosts reach the field through the composer view, so the '
    'fork\'s selection types and defaults stay behind one seam.',
  ),

  /// A library re-exports another workspace package.
  crossPackageReexport(
    'No package re-exports another workspace package; hosts import what they '
    'use, so each package owns exactly its own API.',
  ),

  /// Fake code is exported from somewhere other than `testing.dart`.
  fakeExportedOutsideTesting(
    'Fakes are exported only from a package\'s lib/testing.dart, so the '
    'production entry points never hand them to hosts.',
  ),

  /// Production code imports fakes.
  fakeImportedByProduction(
    'Production code under lib/ must not import fakes: neither its own fake '
    'sources nor another package\'s testing.dart. Only testing code may.',
  ),

  /// A pure-Dart package depends on or imports Flutter.
  flutterInPureDartPackage(
    'content_model, emoji_data and emoji_catalog_pack are pure Dart '
    '(content_model because every package depends on it; the emoji logic '
    'because it runs without an engine and takes bytes and strings from the '
    'host), so they must not depend on the Flutter SDK or import '
    'package:flutter, a Flutter library or dart:ui.',
  ),

  /// A test file the member's test entrypoint does not run.
  testOutsideEntrypoint(
    'scripts/check runs each member\'s tests through test/unit_test.dart '
    '(one process per member), so every *_test.dart under test/ is imported '
    'there and its main called in a group of its own; one left out never '
    'runs in CI.',
  ),

  /// A [LegacyException] no longer matches any violation.
  staleLegacyException(
    'The legacy exception no longer matches a violation; delete it from '
    'LegacyBaseline.current so the gate cannot regress silently.',
  );

  const LintRule(this.explanation);

  /// Why the rule exists; printed under every violation of it.
  final String explanation;
}

/// One breach of a [LintRule].
///
/// [subject] is a stable, human-readable identity of the offending edge or
/// directive (`panel_catalog -> chrome_foundation`,
/// `packages/x/lib/x.dart exports package:y/y.dart`). [LegacyBaseline] matches
/// exceptions on `(rule, subject)`, so subjects must not embed anything that
/// changes between runs.
@immutable
final class Violation {
  /// Creates a violation of [rule] about [subject].
  const Violation(this.rule, this.subject);

  /// The rule that was breached.
  final LintRule rule;

  /// What breached it.
  final String subject;

  @override
  String toString() => '${rule.name}: $subject\n    ${rule.explanation}';
}
