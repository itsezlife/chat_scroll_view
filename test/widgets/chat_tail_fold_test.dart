import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

class _Source extends ChatDataSource {
  _Source(int count) {
    for (var i = 0; i < count; i++) {
      upsertMessage(_msg(i));
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

const _textKey = Key('text-part');
const _cardsKey = Key('cards-part');

void main() {
  const count = 40;
  late ChatScrollController controller;
  late ValueNotifier<double> textH;
  late ValueNotifier<double> cardsH;
  late ValueNotifier<bool> hasFold;

  Future<void> mount(
    WidgetTester tester, {
    bool fold = true,
    double text = 300,
    double cards = 0,
  }) async {
    final ds = _Source(count);
    controller = ChatScrollController()..jumpTo(count - 1);
    textH = ValueNotifier<double>(text);
    cardsH = ValueNotifier<double>(cards);
    hasFold = ValueNotifier<bool>(fold);
    addTearDown(controller.dispose);
    addTearDown(ds.dispose);
    addTearDown(textH.dispose);
    addTearDown(cardsH.dispose);
    addTearDown(hasFold.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 400,
              height: 600,
              child: ChatScrollView(
                dataSource: ds,
                controller: controller,
                messageBuilder: (context, id, message, status, runLayout) {
                  if (id != count - 1) {
                    return SizedBox(height: 60, child: Text('msg-$id'));
                  }
                  return ListenableBuilder(
                    listenable: Listenable.merge([textH, cardsH, hasFold]),
                    builder: (_, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(key: _textKey, height: textH.value),
                        if (hasFold.value) const ChatTailFold(),
                        SizedBox(key: _cardsKey, height: cardsH.value),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(controller.isAtTail.value, isTrue);
  }

  double bandBottom(WidgetTester tester) =>
      tester.getBottomLeft(find.byType(ChatScrollView)).dy;
  double textBottom(WidgetTester tester) =>
      tester.getBottomLeft(find.byKey(_textKey)).dy;
  double cardsBottom(WidgetTester tester) =>
      tester.getBottomLeft(find.byKey(_cardsKey)).dy;

  /// Takes scroll control like a reader (a drag clears the pending tail
  /// settle), then seats the end of the text exactly on the band bottom.
  Future<void> seatOnFold(WidgetTester tester) async {
    final gesture = await tester.startGesture(const Offset(200, 300));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump(const Duration(seconds: 2));
    controller.scrollBy(bandBottom(tester) - textBottom(tester));
    await tester.pump();
    await tester.pump();
    expect(textBottom(tester), closeTo(bandBottom(tester), 0.5));
  }

  group('ChatTailFold', () {
    testWidgets('continuation appended below the fold keeps the text end', (
      tester,
    ) async {
      await mount(tester);
      expect(textBottom(tester), closeTo(bandBottom(tester), 0.5));

      cardsH.value = 500;
      await tester.pump();
      await tester.pump();
      expect(textBottom(tester), closeTo(bandBottom(tester), 0.5));
      expect(
        controller.isAtTail.value,
        isFalse,
        reason: 'the real end is still below',
      );

      cardsH.value = 900;
      await tester.pump();
      expect(textBottom(tester), closeTo(bandBottom(tester), 0.5));
    });

    testWidgets('fold and continuation arriving in one frame stay on the text', (
      tester,
    ) async {
      await mount(tester, fold: false);
      hasFold.value = true;
      cardsH.value = 500;
      await tester.pump();
      await tester.pump();
      expect(textBottom(tester), closeTo(bandBottom(tester), 0.5));
    });

    testWidgets('text growing above the fold keeps following it', (
      tester,
    ) async {
      await mount(tester, cards: 500);
      // Settle on the fold: scroll so the text end sits on the band bottom.
      await seatOnFold(tester);

      for (var i = 0; i < 10; i++) {
        textH.value += 25;
        await tester.pump();
        expect(
          textBottom(tester),
          closeTo(bandBottom(tester), 0.5),
          reason: 'step $i',
        );
      }
      expect(cardsBottom(tester), greaterThan(bandBottom(tester)));
    });

    testWidgets('reader inside the continuation is not yanked back', (
      tester,
    ) async {
      await mount(tester, cards: 600);
      await seatOnFold(tester);

      // Read on into the cards.
      controller.scrollBy(-200);
      await tester.pump();
      await tester.pump();
      final read = textBottom(tester);
      expect(read, closeTo(bandBottom(tester) - 200, 0.5));

      final rowTop = tester.getTopLeft(find.byKey(_textKey)).dy;
      cardsH.value += 150;
      await tester.pump();
      expect(textBottom(tester), closeTo(read, 0.5));
      textH.value += 40;
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(_textKey)).dy,
        closeTo(rowTop, 0.5),
        reason: 'the viewport did not move',
      );
    });

    testWidgets('at the real end the continuation is followed again', (
      tester,
    ) async {
      await mount(tester, cards: 600);
      controller.jumpTo(count - 1);
      await tester.pump();
      await tester.pump();
      expect(cardsBottom(tester), closeTo(bandBottom(tester), 0.5));
      expect(controller.isAtTail.value, isTrue);

      cardsH.value += 120;
      await tester.pump();
      expect(cardsBottom(tester), closeTo(bandBottom(tester), 0.5));
    });

    testWidgets('scroll limits still reach the real end and the text', (
      tester,
    ) async {
      await mount(tester, cards: 500);
      await seatOnFold(tester);
      cardsH.value = 900;
      await tester.pump();

      // Reading on reaches the real bottom and stops there.
      controller.scrollBy(-1500);
      await tester.pump();
      await tester.pump();
      expect(cardsBottom(tester), closeTo(bandBottom(tester), 0.5));
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('without a marker the row bottom is followed as before', (
      tester,
    ) async {
      await mount(tester, fold: false);
      cardsH.value = 500;
      await tester.pump();
      await tester.pump();
      expect(cardsBottom(tester), closeTo(bandBottom(tester), 0.5));
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('fold removed: back to following the real bottom', (
      tester,
    ) async {
      await mount(tester, cards: 500);
      await seatOnFold(tester);
      hasFold.value = false;
      cardsH.value += 100;
      await tester.pump();
      await tester.pump();
      expect(cardsBottom(tester), closeTo(bandBottom(tester), 0.5));
    });
  });
}
