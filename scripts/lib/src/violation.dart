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
    'content_model and chrome_foundation are leaves: every other package may '
    'depend on them, so they depend on no workspace package.',
  ),

  /// An edge the package topology forbids outright.
  forbiddenDependency(
    'The package topology forbids this edge: panel_shell / panel_pages / '
    'panel_presentation stay independent of data payloads, codecs and '
    'fetchers, and panel_catalog stays independent of chrome_foundation '
    '(pages adapt tokens).',
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
    'content_model is pure Dart: every package depends on it, so it must not '
    'depend on the Flutter SDK or import package:flutter, a Flutter library '
    'or dart:ui.',
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
