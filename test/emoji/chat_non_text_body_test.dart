import 'dart:ui';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeBody implements ChatNonTextBody {
  _FakeBody({this.hit, this.bounds});

  ChatInlineHit? hit;
  Rect? bounds;

  @override
  ChatInlineHit? inlineHitAt(Offset globalOffset) => hit;

  @override
  Rect? get globalBounds => bounds;
}

const _key = ContentKey.unicode('\u{1F44D}');
const _sticker = ChatInlineHit.sticker(messageId: 7, content: _key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatSelectionController selection;
  late List<ChatSelectionInteraction> heard;

  ChatSelectionController create({
    ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
    bool handlesEmbedHits = false,
  }) {
    selection = ChatSelectionController(
      policy: policy,
      onInteraction: heard.add,
      handlesEmbedHits: handlesEmbedHits,
    );
    addTearDown(selection.dispose);
    return selection;
  }

  setUp(() => heard = []);

  group('registration', () {
    test('a registered body answers the facade\'s inline hit query', () {
      create();
      selection.putNonTextBody(7, _FakeBody(hit: _sticker));

      expect(selection.resolveInlineHit(7, Offset.zero), _sticker);
      expect(selection.resolveInlineHit(8, Offset.zero), isNull);
    });

    test('it is no text body: nothing to select, no text surface', () {
      create();
      selection.putNonTextBody(7, _FakeBody(hit: _sticker));

      expect(selection.hasBody(7), isFalse);
      expect(selection.containsGlobal(7, Offset.zero), isFalse);
      expect(selection.exposesSelectionSurface(7), isFalse);
      expect(selection.enterTextSelection(7), isFalse);
    });

    test('removing the body takes the hit away', () {
      create();
      final token = selection.putNonTextBody(7, _FakeBody(hit: _sticker));

      selection.removeNonTextBody(7, token: token);

      expect(selection.resolveInlineHit(7, Offset.zero), isNull);
    });

    test('of two mounts the last answers, and the first when it leaves', () {
      create();
      final first = _FakeBody(hit: _sticker);
      final second = _FakeBody(
        hit: const ChatInlineHit.embed(messageId: 7, target: 'a:b', alt: ''),
      );
      selection.putNonTextBody(7, first);
      final token = selection.putNonTextBody(7, second);

      expect(selection.resolveInlineHit(7, Offset.zero), second.hit);
      selection.removeNonTextBody(7, token: token);
      expect(selection.resolveInlineHit(7, Offset.zero), _sticker);
    });

    test('the body\'s bounds count as the message surface when the host '
        'reported none', () {
      create();
      selection.putNonTextBody(
        7,
        _FakeBody(bounds: const Rect.fromLTWH(10, 10, 100, 100)),
      );

      expect(selection.containsMessageSurface(7, const Offset(50, 50)), isTrue);
      expect(
        selection.containsMessageSurface(7, const Offset(150, 50)),
        isFalse,
      );
    });
  });

  group('sticker hit', () {
    test('a tap reaches the host as a sticker activation, with no opt-in', () {
      create();

      expect(selection.handleInlineHit(_sticker), isTrue);

      expect(heard, [
        const ChatStickerActivated(
          messageId: 7,
          content: _key,
          gesture: ChatInlineGesture.tap,
        ),
      ]);
    });

    test('a long press is not claimed: it is message selection', () {
      create();

      expect(selection.handleInlineHitLongPress(_sticker), isFalse);
      expect(heard, isEmpty);
    });

    test('mobile message selection suppresses it, as it does every hit', () {
      create();
      selection.toggle(1);

      expect(selection.handleInlineHit(_sticker), isFalse);
      expect(heard, isEmpty);
    });

    test('value equality and toString', () {
      expect(
        const ChatInlineHit.sticker(messageId: 7, content: _key),
        _sticker,
      );
      expect(_sticker.contourPath, isNull);
      expect(_sticker.touchOrigin, isNull);
      expect(_sticker.toString(), contains('messageId: 7'));
    });
  });
}
