import 'dart:io';

import 'package:chat_scroll_view_example/src/common/pointer_tape.dart';
import 'package:chat_scroll_view_example/src/common/tape_system_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PointerRow _pointer(int t) => PointerRow([
  t, 1, 0, 0, 1, 0, 10.0, 20.0, 0.0, 0.0, 0, 1.0, 1.0, 0.0, 3.0, 3.0, //
  0.0, 0.0, 0, 0, 0,
]);

void main() {
  group('TapeCodec', () {
    test('decodes a tape of pointer rows only, as recorded before system '
        'events existed', () {
      final rows = TapeCodec.decode(
        '[[1000,1,0,0,1,0,1.5,2.5,0.0,0.0,0,1.0,1.0,0.0,3.0,3.0,0.0,0.0,0,0,1]]',
      );
      expect(rows, hasLength(1));
      expect(rows.single, isA<PointerRow>());
      expect(rows.single.time, 1000);
    });

    test('round trips mixed rows', () {
      final rows = [
        _pointer(100),
        const SystemRow(150, TapeSystemEvent.back),
        const SystemRow(160, TapeSystemEvent.imeHidden),
      ];
      final back = TapeCodec.decode(TapeCodec.encode(rows));
      expect(back.map((r) => r.time), [100, 150, 160]);
      expect(back[1], isA<SystemRow>());
      expect((back[1] as SystemRow).event, TapeSystemEvent.back);
      expect((back[2] as SystemRow).event, TapeSystemEvent.imeHidden);
      expect((back[0] as PointerRow).values, _pointer(100).values);
    });

    test('orders rows by time, keeping the order of one instant', () {
      final text = TapeCodec.encode([
        const SystemRow(300, TapeSystemEvent.imeHidden),
        _pointer(100),
        const SystemRow(200, TapeSystemEvent.back),
        const SystemRow(200, TapeSystemEvent.backPreIme),
      ]);
      final rows = TapeCodec.decode(text);
      expect(rows.map((r) => r.time), [100, 200, 200, 300]);
      expect((rows[1] as SystemRow).event, TapeSystemEvent.back);
      expect((rows[2] as SystemRow).event, TapeSystemEvent.backPreIme);
    });
  });

  group('PointerTape.play', () {
    test('dispatches system rows between pointer rows in timeline order, '
        'skipping the diagnostic ime-shown', () async {
      final log = <String>[];
      final n = await PointerTape.play(
        [
          _pointer(0),
          _pointer(1000),
          const SystemRow(2000, TapeSystemEvent.back),
          const SystemRow(2500, TapeSystemEvent.imeShown),
          const SystemRow(3000, TapeSystemEvent.imeHidden),
          _pointer(4000),
        ],
        forward: (p) => log.add('pointers:${p.data.length}'),
        system: (e) async => log.add(e.wire),
      );
      expect(n, 6);
      expect(log.join(' '), contains('back ime-hidden pointers:'));
      expect(log.indexOf('back'), lessThan(log.indexOf('ime-hidden')));
      expect(log, isNot(contains('ime-shown')));
      expect(log.last, 'pointers:1');
      expect(log.first, startsWith('pointers:'));
    });
  });

  group('PointerTape recording', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('tape'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('notes events only while recording, and saves them', () async {
      PointerTape.note(TapeSystemEvent.back);
      expect(PointerTape.recording, isFalse);
      PointerTape.start();
      PointerTape.note(TapeSystemEvent.back, at: 50);
      PointerTape.note(TapeSystemEvent.imeHidden, at: 40);
      final n = await PointerTape.stop(dir.path, 't');
      expect(n, 2);
      final rows = TapeCodec.decode(
        File('${dir.path}/t.json').readAsStringSync(),
      );
      expect(rows.map((r) => r.time), [40, 50]);
    });
  });

  group('TapeSystemRecorder', () {
    testWidgets('notes a popRoute and lets the navigators handle it', (
      tester,
    ) async {
      TapeSystemRecorder.install();
      final dir = Directory.systemTemp.createTempSync('tape');
      addTearDown(() => dir.deleteSync(recursive: true));
      PointerTape.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const Text('second')),
              ),
              child: const Text('first'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('second'), findsNothing);
      final rows = (await tester.runAsync(() async {
        await PointerTape.stop(dir.path, 't');
        return TapeCodec.decode(File('${dir.path}/t.json').readAsStringSync());
      }))!;
      expect(rows.whereType<SystemRow>().map((r) => r.event), [
        TapeSystemEvent.back,
      ]);
    });

    testWidgets('replayed back pops the route and the recorder does not '
        're-record it', (tester) async {
      TapeSystemRecorder.install();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const Text('second')),
              ),
              child: const Text('first'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('first'));
      await tester.pumpAndSettle();
      await TapeSystemRecorder.dispatch(TapeSystemEvent.back);
      await tester.pumpAndSettle();
      expect(find.text('second'), findsNothing);
    });

    testWidgets('replayed ime-hidden hides the input and drops focus', (
      tester,
    ) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.textInput,
          null,
        ),
      );
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(child: TextField(focusNode: node)),
        ),
      );
      node.requestFocus();
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue);
      await TapeSystemRecorder.dispatch(TapeSystemEvent.imeHidden);
      await tester.pump();
      expect(calls, contains('TextInput.hide'));
      expect(node.hasFocus, isFalse);
    });
  });

  group('ImeHideDetector', () {
    const idle = 10000000;

    test('reports a hide where it began, once the inset reaches zero', () {
      final d = ImeHideDetector();
      expect(
        d.onInset(300, 0, sinceInputMicros: idle)?.$1,
        TapeSystemEvent.imeShown,
      );
      expect(d.onInset(300, 100, sinceInputMicros: idle), isNull);
      expect(d.onInset(200, 1000, sinceInputMicros: idle), isNull);
      expect(d.onInset(80, 1100, sinceInputMicros: idle), isNull);
      expect(d.onInset(0, 1200, sinceInputMicros: idle), (
        TapeSystemEvent.imeHidden,
        1000,
      ));
      expect(d.onInset(0, 1300, sinceInputMicros: idle), isNull);
    });

    test('a hide right after the app\'s own input is its consequence', () {
      final d = ImeHideDetector();
      d.onInset(300, 0, sinceInputMicros: idle);
      expect(d.onInset(0, 1000, sinceInputMicros: 50000), isNull);
    });

    test('a fall that turns back up is not a hide', () {
      final d = ImeHideDetector();
      d.onInset(300, 0, sinceInputMicros: idle);
      d.onInset(250, 10, sinceInputMicros: idle);
      expect(d.onInset(300, 20, sinceInputMicros: idle), isNull);
      expect(d.onInset(0, 30, sinceInputMicros: idle), (
        TapeSystemEvent.imeHidden,
        30,
      ));
    });
  });
}
