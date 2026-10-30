import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/registry.dart';

Scenario _s(String id, int version, [List<String> windows = const ['w']]) =>
    Scenario(id: id, version: version, windows: windows, run: (_) async {});

void main() {
  final registry = ScenarioRegistry([
    _s('scroll.drag_slow', 1, ['drag']),
    _s('scroll.drag_fast', 2),
    _s('nav.jump_near', 1),
  ]);

  test('lists scenarios by id@version', () {
    expect(registry.keys, [
      'scroll.drag_slow@1',
      'scroll.drag_fast@2',
      'nav.jump_near@1',
    ]);
  });

  test('a scenario declares its named windows', () {
    expect(registry.all.first.windows, ['drag']);
  });

  test('an empty filter selects everything', () {
    expect(registry.where('').length, 3);
  });

  test('a glob filter matches ids, * crossing nothing but the name', () {
    expect(registry.where('scroll.*').map((s) => s.id), [
      'scroll.drag_slow',
      'scroll.drag_fast',
    ]);
    expect(registry.where('scroll.drag_slow').length, 1);
    expect(registry.where('nav.*,scroll.drag_fast').length, 2);
    expect(registry.where('scroll').length, 0);
  });

  test('rejects a duplicate id', () {
    expect(
      () => ScenarioRegistry([_s('a.b', 1), _s('a.b', 2)]),
      throwsArgumentError,
    );
  });

  test('rejects a malformed id', () {
    expect(() => ScenarioRegistry([_s('nodot', 1)]), throwsArgumentError);
  });
}
