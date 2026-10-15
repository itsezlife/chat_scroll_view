import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:workspace_check/src/workspace.dart';

/// One external command of the check: what to run and where.
@immutable
final class CommandStep {
  /// Creates a step that runs [executable] with [arguments] in
  /// [workingDirectory].
  const CommandStep({
    required this.label,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  /// `member: what` heading printed before the step and in the failure summary.
  final String label;

  /// Program to start.
  final String executable;

  /// Arguments passed to [executable].
  final List<String> arguments;

  /// Absolute directory the command runs in.
  final String workingDirectory;

  /// The command as a developer would type it, for logs.
  String get commandLine => <String>[executable, ...arguments].join(' ');
}

/// The commands `scripts/check` runs for every member, in dependency order.
///
/// A plan is data: building it touches nothing, and the driver runs the steps
/// and decides what a failure means. For each member, dependencies first:
///
/// 1. `dart analyze --fatal-infos` over the member's layout directories
///    ([WorkspaceMember.analysisTargets]);
/// 2. its tests, `flutter test` for a member that needs the Flutter SDK and
///    `dart test` otherwise, skipped when it has no test files;
/// 3. its `tool/check` hook when it ships one, from the member directory.
///
/// The hook is how a package contributes a gate that only it can express (for
/// example a generator proving its committed output regenerates
/// byte-for-byte). It is a convention, not a registry: adding the executable
/// file is the whole registration. A non-zero exit fails the gate.
///
/// Order is for diagnosis, not correctness: a failure in a leaf is printed
/// before the failures it causes in dependents. The driver still runs every
/// step after a failure so one run reports everything.
abstract final class CheckPlan {
  /// Steps for all members of [graph].
  static List<CommandStep> forWorkspace(WorkspaceGraph graph) {
    final steps = <CommandStep>[];
    for (final member in graph.inDependencyOrder()) {
      final directory = graph.directoryOf(member);

      if (member.analysisTargets.isNotEmpty) {
        steps.add(
          CommandStep(
            label: '${member.name}: analyze',
            executable: 'dart',
            arguments: <String>[
              'analyze',
              '--fatal-infos',
              ...member.analysisTargets,
            ],
            workingDirectory: directory,
          ),
        );
      }

      if (member.hasTests) {
        steps.add(
          CommandStep(
            label: '${member.name}: test',
            executable: member.usesFlutter ? 'flutter' : 'dart',
            // --no-pub: scripts/check resolves the whole workspace once up
            // front; letting every `flutter test` re-resolve it would be slow
            // and could rewrite the lockfile mid-run.
            arguments: member.usesFlutter
                ? const <String>['test', '--no-pub']
                : const <String>['test'],
            workingDirectory: directory,
          ),
        );
      }

      if (member.hasCheckHook) {
        steps.add(
          CommandStep(
            label: '${member.name}: tool/check',
            // Absolute: a relative executable is resolved against the parent's
            // directory on some platforms, not against workingDirectory.
            executable: p.join(directory, 'tool', 'check'),
            arguments: const <String>[],
            workingDirectory: directory,
          ),
        );
      }
    }
    return steps;
  }
}
