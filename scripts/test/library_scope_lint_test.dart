import 'package:test/test.dart';
import 'package:workspace_check/workspace_check.dart';

import 'fixture_workspace.dart';

void main() {
  late FixtureWorkspace fixture;

  setUp(() => fixture = FixtureWorkspace());
  tearDown(() => fixture.dispose());

  List<Violation> lint() =>
      LibraryScopeLint.check(WorkspaceGraph.load(fixture.path));

  List<String> subjects() => [for (final v in lint()) v.subject];

  test('passes for types, private glue and platform entries', () {
    fixture.member(
      'alpha',
      files: {
        'lib/src/kinds.dart': '''
import 'dart:math' as math;

/// A type owns its operations.
@immutable
final class Box {
  const Box(this.side);

  static const double unit = 1;

  final double side;

  double get area => math.pow(side, 2).toDouble();
}

abstract interface class Store {}

sealed class Shape {}

enum Kind { a, b }

mixin Ordered {}

extension BoxArea on Box {
  double get half => area / 2;
}

extension type const BoxId(int value) {}

typedef Measure = double Function(Box box);

const _limit = 3;
final _cache = <String, Box>{};
late final Box _shared;
double _twice(double value) => value * 2;
bool get _ready => _limit > 0;

/* A block comment
fn() {}
*/
const _template = """
notAFunction() {}
final notAVariable = 1;
""";
''',
        'lib/src/environment_specific/store_vm.dart':
            r'Store $createStore(String path) => throw UnimplementedError();'
            '\n',
      },
    );

    expect(lint(), isEmpty);
  });

  test('reports public functions, accessors and variables', () {
    fixture.member(
      'alpha',
      files: {
        'lib/src/loose.dart': '''
const double kGap = 4;
final defaultBox = Box(1);
var counter = 0;
late final Box sharedBox;
Box makeBox(double side) => Box(side);
Future<List<Box>> loadBoxes() async => [];
double get gap => kGap;
set gap(double value) {}
@visibleForTesting
void Function(Box) onBox = (_) {};
final void Function(
  Box box, [
  int times,
])
onDrop = (_, [_]) {};
void Function(
  Box box,
)
_dropper(int level) => (_) {};
''',
      },
    );

    expect(lint().map((v) => v.rule).toSet(), {LintRule.publicLibraryScope});
    expect(subjects(), [
      for (final name in [
        'kGap',
        'defaultBox',
        'counter',
        'sharedBox',
        'makeBox',
        'loadBoxes',
        'gap',
        'gap',
        'onBox',
        'onDrop',
      ])
        'packages/alpha/lib/src/loose.dart declares $name',
    ]);
  });

  test(r'reports a $ entry outside environment_specific/', () {
    fixture.member(
      'alpha',
      files: {
        'lib/src/open.dart':
            r'Store $openStore() => Store();'
            '\n',
      },
    );

    expect(subjects(), [
      r'packages/alpha/lib/src/open.dart declares $openStore',
    ]);
  });

  test('checks the root package, not the example app or the tool', () {
    fixture
      ..write('lib/root_package.dart', 'int rootCount = 0;\n')
      ..member(
        'demo',
        at: 'example',
        files: {'lib/main.dart': 'void main() {}\n'},
      )
      ..member(
        'workspace_check',
        at: 'scripts',
        files: {'lib/src/gate.dart': 'int gates = 0;\n'},
      );

    expect(subjects(), ['lib/root_package.dart declares rootCount']);
  });
}
