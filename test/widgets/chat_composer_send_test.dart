import 'dart:async';

import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_selection_controller.dart';
import 'package:chatscrollview/src/chat_widgets/demo/chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource() {
    seedBoundaries(reachedOldest: true, reachedNewest: true);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Widget _composerHarness({
  required ChatSelectionController selection,
  required ChatDataSource dataSource,
  required Future<void> Function(String text) onSend,
}) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: <Widget>[
        const Expanded(child: SizedBox()),
        ChatComposer(
          selection: selection,
          dataSource: dataSource,
          onSend: onSend,
        ),
      ],
    ),
  ),
);

void main() {
  group('ChatComposer send', () {
    testWidgets('invokes onSend with trimmed text and clears on success', (
      tester,
    ) async {
      final selection = ChatSelectionController();
      final dataSource = _PreloadedDataSource();
      String? sent;
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      await tester.pumpWidget(
        _composerHarness(
          selection: selection,
          dataSource: dataSource,
          onSend: (text) async {
            sent = text;
          },
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '  hello world  ');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(sent, 'hello world');
      expect(find.byType(TextField), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('whitespace-only send does not invoke onSend', (tester) async {
      final selection = ChatSelectionController();
      final dataSource = _PreloadedDataSource();
      var invoked = false;
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      await tester.pumpWidget(
        _composerHarness(
          selection: selection,
          dataSource: dataSource,
          onSend: (_) async {
            invoked = true;
          },
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '   \n  ');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(invoked, isFalse);
    });

    testWidgets('retains text and re-enables send after onSend throws', (
      tester,
    ) async {
      final selection = ChatSelectionController();
      final dataSource = _PreloadedDataSource();
      var attempts = 0;
      Object? asyncError;
      addTearDown(selection.dispose);
      addTearDown(dataSource.dispose);

      await runZonedGuarded(() async {
        await tester.pumpWidget(
          _composerHarness(
            selection: selection,
            dataSource: dataSource,
            onSend: (text) async {
              attempts++;
              if (attempts == 1) {
                throw Exception('network');
              }
            },
          ),
        );
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'retry me');
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pump();
        await tester.pump();

        expect(attempts, 1);
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, 'retry me');

        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();

        expect(attempts, 2);
        expect(field.controller!.text, isEmpty);
      }, (error, stack) => asyncError = error);

      expect(asyncError, isA<Exception>());
    });
  });
}
