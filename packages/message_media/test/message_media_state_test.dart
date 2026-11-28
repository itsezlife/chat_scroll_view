import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

import 'support/media_scopes.dart';

void main() {
  const a = MediaItemId('a');
  const b = MediaItemId('b');

  group('MessageMediaState', () {
    test('a new state starts hidden', () {
      final state = MessageMediaState();
      addTearDown(state.dispose);
      expect(state.isSpoilerRevealed(a), isFalse);
      expect(state.of(a).value.spoilerRevealed, isFalse);
    });

    test('reveal notifies the listeners of that id only', () {
      final state = MessageMediaState();
      addTearDown(state.dispose);
      var forA = 0;
      var forB = 0;
      state.of(a).addListener(() => forA++);
      state.of(b).addListener(() => forB++);

      state.revealSpoiler(a);

      expect(forA, 1);
      expect(forB, 0);
      expect(state.isSpoilerRevealed(a), isTrue);
      expect(state.isSpoilerRevealed(b), isFalse);

      state.revealSpoiler(a);
      expect(forA, 1);
    });

    test('sendOrigin is stored and handed out through the function', () {
      const origin = Rect.fromLTWH(1, 2, 3, 4);
      final taken = <MediaItemId>[];
      final state = MessageMediaState(
        sendOrigin: (id) {
          taken.add(id);
          return id == a ? origin : null;
        },
      );
      addTearDown(state.dispose);
      expect(state.takeSendOrigin(a), origin);
      expect(state.takeSendOrigin(b), isNull);
      expect(taken, [a, b]);
      final none = MessageMediaState();
      addTearDown(none.dispose);
      expect(none.takeSendOrigin(a), isNull);
    });

    test('a disposed state asserts on use', () {
      final state = MessageMediaState()..dispose();
      expect(() => state.revealSpoiler(a), throwsAssertionError);
      expect(() => state.of(a), throwsAssertionError);
      expect(() => state.isSpoilerRevealed(a), throwsAssertionError);
      expect(() => state.takeSendOrigin(a), throwsAssertionError);
    });
  });

  group('MessageMediaStateScope', () {
    testWidgets('provides the state; maybeOf is null without one', (
      tester,
    ) async {
      final state = MessageMediaState();
      addTearDown(state.dispose);
      MessageMediaState? inside;
      MessageMediaState? outside = state;
      await tester.pumpWidget(
        MediaScopes.wrap(
          Column(
            textDirection: TextDirection.ltr,
            children: [
              Builder(
                builder: (context) {
                  outside = MessageMediaStateScope.maybeOf(context);
                  return const SizedBox();
                },
              ),
              MessageMediaStateScope(
                state: state,
                child: Builder(
                  builder: (context) {
                    inside = MessageMediaStateScope.of(context);
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        ),
      );
      expect(inside, same(state));
      expect(outside, isNull);
    });
  });

  group('MessageMediaStateBuilder', () {
    late RecordingDiagnostics diagnostics;
    setUp(() => diagnostics = RecordingDiagnostics.install());

    testWidgets('uses the scope and reports nothing', (tester) async {
      final state = MessageMediaState();
      addTearDown(state.dispose);
      MessageMediaState? got;
      await tester.pumpWidget(
        MediaScopes.wrap(
          MessageMediaStateScope(
            state: state,
            child: MessageMediaStateBuilder(
              scrollId: 's1',
              builder: (_, s) {
                got = s;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(got, same(state));
      expect(diagnostics.events, isEmpty);
    });

    testWidgets(
      'without a scope keeps state per cell and loses it on dispose',
      (tester) async {
        MessageMediaState? first;
        MessageMediaState? second;
        Widget cell(String id, void Function(MessageMediaState) take) =>
            MessageMediaStateBuilder(
              scrollId: id,
              builder: (_, s) {
                take(s);
                return const SizedBox();
              },
            );
        await tester.pumpWidget(
          MediaScopes.wrap(
            Column(
              textDirection: TextDirection.ltr,
              children: [
                cell('s1', (s) => first = s),
                cell('s2', (s) => second = s),
              ],
            ),
          ),
        );
        expect(first, isNot(same(second)));
        first!.revealSpoiler(a);
        await tester.pump();
        expect(first!.isSpoilerRevealed(a), isTrue);
        expect(second!.isSpoilerRevealed(a), isFalse);
        // Rebuilding keeps the cell's state.
        final kept = first;
        await tester.pumpWidget(
          MediaScopes.wrap(
            Column(
              textDirection: TextDirection.ltr,
              children: [
                cell('s1', (s) => first = s),
                cell('s2', (s) => second = s),
              ],
            ),
          ),
        );
        expect(first, same(kept));

        expect(diagnostics.events, hasLength(2));
        expect(
          diagnostics.events.first,
          isChatEvent(
            level: ChatEventLevel.debug,
            category: ChatEventCategory.media,
            op: MediaStateOp.stateScopeMissing,
            correlation: const ChatCorrelation(scrollId: 's1'),
          ),
        );

        await tester.pumpWidget(MediaScopes.wrap(const SizedBox()));
        expect(() => kept!.isSpoilerRevealed(a), throwsAssertionError);
      },
    );
  });
}
