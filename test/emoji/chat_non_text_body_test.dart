import 'dart:ui';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeStickerBody extends _FakeBody implements ChatStickerBody {
  _FakeStickerBody({this.rect});

  Rect? rect;

  int replays = 0;
  bool replayResult = true;

  @override
  Rect? get stickerGlobalRect => rect;

  @override
  bool replay() {
    replays++;
    return replayResult;
  }
}

class _FakeBody implements ChatNonTextBody {
  _FakeBody({this.hit, this.bounds});

  ChatInlineHit? hit;
  Rect? bounds;

  @override
  ChatInlineHit? inlineHitAt(Offset globalOffset) => hit;

  @override
  Rect? get globalBounds => bounds;
}

const _key = ContentKey.unicode('\u{1F44D}');
const _rect = Rect.fromLTWH(10, 20, 100, 100);
const _sticker = ChatInlineHit.sticker(messageId: 7, content: _key, stickerRect: _rect);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatSelectionController selection;
  late List<ChatSelectionInteraction> heard;

  var now = const Duration(seconds: 5);

  ChatSelectionController create({
    ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
    bool handlesEmbedHits = false,
  }) {
    selection = ChatSelectionController(
      policy: policy,
      onInteraction: heard.add,
      handlesEmbedHits: handlesEmbedHits,
      monotonicClock: () => now,
    );
    addTearDown(selection.dispose);
    return selection;
  }

  setUp(() {
    heard = [];
    now = const Duration(seconds: 5);
  });

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
      selection.putNonTextBody(7, _FakeBody(bounds: const Rect.fromLTWH(10, 10, 100, 100)));

      expect(selection.containsMessageSurface(7, const Offset(50, 50)), isTrue);
      expect(selection.containsMessageSurface(7, const Offset(150, 50)), isFalse);
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
          stickerRect: _rect,
          tapTime: Duration(seconds: 5),
        ),
      ]);
    });

    test('the tap is stamped by the facade\'s monotonic clock, as it '
        'happens', () {
      create();
      selection.handleInlineHit(_sticker);
      now += const Duration(milliseconds: 250);
      selection.handleInlineHit(_sticker);

      final times = heard.cast<ChatStickerActivated>().map((a) => a.tapTime);
      expect(times, [const Duration(seconds: 5), const Duration(seconds: 5, milliseconds: 250)]);
    });

    test('the activation names the emoji, the message and the sticker rect '
        'a host needs to broadcast and to draw over', () {
      create();
      selection.handleInlineHit(_sticker);

      final tap = heard.single as ChatStickerActivated;
      expect(tap.messageId, 7);
      expect(tap.content, _key);
      expect(tap.isCustomEmoji, isFalse);
      expect(tap.stickerRect, _rect);
    });

    test('a custom emoji says so', () {
      create();
      selection.handleInlineHit(
        const ChatInlineHit.sticker(messageId: 7, content: ContentKey.document('d'), stickerRect: _rect),
      );

      expect((heard.single as ChatStickerActivated).isCustomEmoji, isTrue);
    });

    test('a long press is told to the host and not claimed: it is still '
        'message selection', () {
      create();

      expect(selection.handleInlineHitLongPress(_sticker), isFalse);

      expect(heard, [
        const ChatStickerActivated(
          messageId: 7,
          content: _key,
          gesture: ChatInlineGesture.longPress,
          stickerRect: _rect,
          tapTime: Duration(seconds: 5),
        ),
      ]);
    });

    test('a long press in message selection is told to no one', () {
      create();
      selection.toggle(1);

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
      expect(const ChatInlineHit.sticker(messageId: 7, content: _key, stickerRect: _rect), _sticker);
      expect(
        const ChatInlineHit.sticker(messageId: 7, content: _key, stickerRect: Rect.fromLTWH(0, 0, 1, 1)),
        isNot(_sticker),
      );
      expect(_sticker.contourPath, isNull);
      expect(_sticker.touchOrigin, isNull);
      expect(_sticker.toString(), contains('messageId: 7'));
    });
  });

  group('sticker commands', () {
    test('the facade reads a sticker body\'s rectangle', () {
      create();
      selection.putNonTextBody(7, _FakeStickerBody(rect: _rect));

      expect(selection.stickerRectOf(7), _rect);
      expect(selection.stickerRectOf(8), isNull);
    });

    test('a body that is no sticker has no rectangle and no replay', () {
      create();
      selection.putNonTextBody(7, _FakeBody());

      expect(selection.stickerRectOf(7), isNull);
      expect(selection.replaySticker(7), isFalse);
    });

    test('replay goes to the last mounted sticker body and answers with its '
        'result', () {
      create();
      final first = _FakeStickerBody(rect: _rect);
      final second = _FakeStickerBody(rect: _rect)..replayResult = false;
      selection
        ..putNonTextBody(7, first)
        ..putNonTextBody(7, second);

      expect(selection.replaySticker(7), isFalse);

      expect(second.replays, 1);
      expect(first.replays, 0);
    });

    test('a remote interaction on a shown sticker restarts it and hands the '
        'host where to draw', () {
      create();
      final body = _FakeStickerBody(rect: _rect);
      selection.putNonTextBody(7, body);

      final play = selection.playRemoteInteraction(7);

      expect(play, isNotNull);
      expect(play!.stickerRect, _rect);
      expect(play.restarted, isTrue);
      expect(body.replays, 1);
    });

    test('a remote interaction on a sticker that is already playing still '
        'gets its rectangle, with no restart', () {
      create();
      final body = _FakeStickerBody(rect: _rect)..replayResult = false;
      selection.putNonTextBody(7, body);

      final play = selection.playRemoteInteraction(7);

      expect(play!.restarted, isFalse);
      expect(play.stickerRect, _rect);
    });

    test('a remote interaction on a row that shows no sticker is dropped: '
        'null, and nothing restarts', () {
      create();
      final hidden = _FakeStickerBody();
      selection.putNonTextBody(7, hidden);

      expect(selection.playRemoteInteraction(7), isNull);
      expect(selection.playRemoteInteraction(99), isNull);
      expect(hidden.replays, 0);
    });

    test('nothing plays after the facade is disposed', () {
      create();
      selection.putNonTextBody(7, _FakeStickerBody(rect: _rect));
      selection.dispose();

      expect(selection.playRemoteInteraction(7), isNull);
      expect(selection.stickerRectOf(7), isNull);
    });
  });
}
