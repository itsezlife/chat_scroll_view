import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  const debounce = Duration(milliseconds: 300);
  const busyDelay = Duration(milliseconds: 65);

  late List<String> searched;
  late List<(String, String)> results;
  late int cleared;
  late Map<String, Completer<String>> pending;

  DebouncedSearch<String> build() {
    final search = DebouncedSearch<String>(
      search: (query) {
        searched.add(query);
        return (pending[query] = Completer<String>()).future;
      },
      onResult: (query, result) => results.add((query, result)),
      onCleared: () => cleared++,
    );
    addTearDown(search.dispose);
    return search;
  }

  setUp(() {
    searched = [];
    results = [];
    cleared = 0;
    pending = {};
  });

  testWidgets('searches once after the debounce, with the trimmed query', (
    tester,
  ) async {
    final search = build()
      ..update('c')
      ..update('ca')
      ..update(' cat ');

    await tester.pump(debounce - const Duration(milliseconds: 1));
    expect(searched, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    expect(searched, ['cat']);
    pending['cat']!.complete('hits');
    await tester.pump();
    expect(results, [('cat', 'hits')]);
    expect(search.busy.value, isFalse);
  });

  testWidgets('replies arriving out of order publish only the newest', (
    tester,
  ) async {
    final search = build()..update('cat');
    await tester.pump(debounce);
    search.update('dog');
    await tester.pump(debounce);
    expect(searched, ['cat', 'dog']);

    pending['dog']!.complete('dog hits');
    pending['cat']!.complete('cat hits');
    await tester.pump();

    expect(results, [('dog', 'dog hits')]);
  });

  testWidgets('a stale reply arriving late is not published', (tester) async {
    final search = build()..update('cat');
    await tester.pump(debounce);

    search.update('catn');
    pending['cat']!.complete('late');
    await tester.pump();
    expect(results, isEmpty);

    await tester.pump(debounce);
    pending['catn']!.complete('fresh');
    await tester.pump();
    expect(results, [('catn', 'fresh')]);
  });

  testWidgets('is busy from the busy delay until the result lands', (
    tester,
  ) async {
    final search = build()..update('cat');

    await tester.pump(busyDelay - const Duration(milliseconds: 1));
    expect(search.busy.value, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(search.busy.value, isTrue);

    await tester.pump(debounce);
    pending['cat']!.complete('hits');
    await tester.pump();
    expect(search.busy.value, isFalse);
  });

  testWidgets('an empty query clears at once and cancels the pending search', (
    tester,
  ) async {
    final search = build()..update('cat');
    await tester.pump(busyDelay);
    expect(search.busy.value, isTrue);

    search.update('   ');

    expect(cleared, 1);
    expect(search.busy.value, isFalse);
    await tester.pump(debounce);
    expect(searched, isEmpty);
  });

  testWidgets('clearing drops the reply of a search already in flight', (
    tester,
  ) async {
    final search = build()..update('cat');
    await tester.pump(debounce);

    search.update('');
    pending['cat']!.complete('late');
    await tester.pump();

    expect(results, isEmpty);
    expect(search.busy.value, isFalse);
  });

  testWidgets('the same query again does not restart the debounce', (
    tester,
  ) async {
    final search = build()..update('cat');
    await tester.pump(const Duration(milliseconds: 200));
    search.update('cat ');
    await tester.pump(const Duration(milliseconds: 100));

    expect(searched, ['cat']);
  });

  testWidgets('reports a failing search to the zone and stops being busy', (
    tester,
  ) async {
    final errors = <Object>[];
    late DebouncedSearch<String> search;
    await runZonedGuarded(() async {
      search = build()..update('cat');
      await tester.pump(debounce);
      pending['cat']!.completeError(StateError('offline'));
      await tester.pump();
    }, (error, _) => errors.add(error));

    expect(errors, [isStateError]);
    expect(search.busy.value, isFalse);
    expect(results, isEmpty);
  });

  testWidgets('dispose cancels timers and drops late replies', (tester) async {
    final search = build()..update('cat');
    await tester.pump(debounce);

    search.dispose();
    pending['cat']!.complete('late');
    await tester.pump();

    expect(results, isEmpty);
  });
}
