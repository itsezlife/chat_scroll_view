import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _gif = ContentKey.document('gif-1');
// The panel cell's decode and the chat's: the same content at two sizes.
const _cell = AssetSpec(pixelWidth: 300, pixelHeight: 200);
const _chat = AssetSpec(pixelWidth: 480, pixelHeight: 480);
const _profile = AssetProfile();
const _rect = Rect.fromLTWH(0, 0, 160, 160);

void main() {
  late FakeAssetProducer producer;
  late AssetCacheScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
  });
  tearDown(() => scope.dispose());

  group('a sibling stage before the first', () {
    test('a new spec shows what another spec of the content has', () {
      scope.attach(_gif, _cell, _profile);
      final cell = producer.last.advance(AssetStage.full);

      final chat = scope.attach(_gif, _chat, _profile);

      expect(chat.paintable, same(cell));
      expect(chat.readiness, const AssetReadiness(AssetStage.full));
    });

    test('the sibling is placed by the binding\'s own profile', () {
      scope.attach(_gif, _cell, const AssetProfile(fit: AssetFit.cover));
      final cell = producer.last.advance(AssetStage.firstFrame);

      scope
          .attach(_gif, _chat, _profile)
          .paint(Canvas(PictureRecorder()), _rect);

      expect(cell.paints.single.rect, _rect);
      expect(cell.paints.single.context.fit, AssetFit.contain);
    });

    test('the entry\'s own first frame replaces it, at once, signalled', () {
      scope.attach(_gif, _cell, _profile);
      producer.last.advance(AssetStage.full);
      final chat = scope.attach(_gif, _chat, _profile);
      var signals = 0;
      chat.addListener(() => signals++);

      final own = producer.last.advance(AssetStage.firstFrame);

      expect(chat.paintable, same(own));
      expect(chat.readiness, const AssetReadiness(AssetStage.firstFrame));
      expect(signals, 1);
    });

    test('a better sibling than the entry\'s thumbnail is shown over it', () {
      scope.attach(_gif, _cell, _profile);
      final cell = producer.last.advance(AssetStage.full);
      final chat = scope.attach(_gif, _chat, _profile);

      producer.last.advance(AssetStage.placeholder);

      expect(chat.paintable, same(cell));
    });

    test('content after a borrowed stage has no thumbnail to fade over', () {
      scope.attach(_gif, _cell, _profile);
      producer.last.advance(AssetStage.full);
      final chat = scope.attach(_gif, _chat, _profile);
      final thumbnail = producer.last.advance(AssetStage.placeholder);

      producer.last.advance(AssetStage.firstFrame);

      expect(chat.paintStandIn(Canvas(PictureRecorder()), _rect), isFalse);
      expect(thumbnail.isDisposed, isTrue);
    });

    test('a sibling that arrives later is shown, signalled', () {
      final chat = scope.attach(_gif, _chat, _profile);
      scope.attach(_gif, _cell, _profile);
      var signals = 0;
      chat.addListener(() => signals++);

      final cell = producer.last.advance(AssetStage.firstFrame);

      expect(chat.paintable, same(cell));
      expect(signals, 1);
    });

    test('the borrowed sibling\'s better stage follows, signalled', () {
      scope.attach(_gif, _cell, _profile);
      final cellAttempt = producer.last;
      cellAttempt.advance(AssetStage.firstFrame);
      final chat = scope.attach(_gif, _chat, _profile);
      var signals = 0;
      chat.addListener(() => signals++);

      final full = cellAttempt.advance(AssetStage.full);

      expect(chat.paintable, same(full));
      expect(signals, 1);
    });

    test('the best stage wins, then the larger decode', () {
      const small = AssetSpec(pixelWidth: 100, pixelHeight: 100);
      scope.attach(_gif, small, _profile);
      final smallFull = producer.last.advance(AssetStage.full);
      scope.attach(_gif, _cell, _profile);
      producer.last.advance(AssetStage.firstFrame);

      expect(scope.attach(_gif, _chat, _profile).paintable, same(smallFull));

      final cellFull = producer
          .attemptsFor(const AssetRequest(_gif, _cell))
          .single
          .advance(AssetStage.full);

      expect(
        scope
            .attach(
              _gif,
              const AssetSpec(pixelWidth: 9, pixelHeight: 9),
              _profile,
            )
            .paintable,
        same(cellFull),
      );
    });

    test('a playing sibling lends its first frame, never its live frame', () {
      scope.attach(_gif, _cell, _profile).visible = false;
      final cell = producer.last.advance(AssetStage.full, animated: true);

      final chat = scope.attach(_gif, _chat, const AssetProfile(animate: true));

      expect(chat.paintable, same(cell.firstFrame));
      expect(chat.paintable, isNot(same(cell)));
      expect(chat.readiness, const AssetReadiness(AssetStage.firstFrame));
      expect(chat.isPlaying, isFalse);
    });

    test('a playing sibling with no still is not borrowed', () {
      scope.attach(_gif, _cell, _profile).visible = false;
      producer.last.advance(
        AssetStage.full,
        animated: true,
        firstFrameStill: false,
      );

      final chat = scope.attach(_gif, _chat, const AssetProfile(animate: true));

      expect(chat.paintable, same(scope.mediaPlaceholder));
      expect(chat.readiness, const AssetReadiness(AssetStage.none));
    });

    test('the borrowed still stays until the entry has its own frame', () {
      scope.attach(_gif, _cell, _profile).visible = false;
      final cell = producer.last.advance(AssetStage.full, animated: true);
      final chat = scope.attach(_gif, _chat, const AssetProfile(animate: true));
      final chatAttempt = producer.last;
      chatAttempt.advance(AssetStage.placeholder);
      expect(chat.paintable, same(cell.firstFrame));

      final own = chatAttempt.advance(AssetStage.firstFrame);

      expect(chat.paintable, same(own));
    });

    test('another decode mode or another content is not a sibling', () {
      scope.attach(
        _gif,
        const AssetSpec(
          pixelWidth: 300,
          pixelHeight: 200,
          decodeMode: AssetDecodeMode.template,
        ),
        _profile,
      );
      producer.last.advance(AssetStage.full);
      scope.attach(const ContentKey.document('gif-2'), _cell, _profile);
      producer.last.advance(AssetStage.full);

      final chat = scope.attach(_gif, _chat, _profile);

      expect(chat.paintable, same(scope.mediaPlaceholder));
      expect(chat.readiness, const AssetReadiness(AssetStage.none));
    });
  });

  group('a borrowed sibling', () {
    test('stays while it is shown, though nobody is bound to it', () {
      final cellBinding = scope.attach(_gif, _cell, _profile);
      final cell = producer.last.advance(AssetStage.full);
      final chat = scope.attach(_gif, _chat, _profile);

      cellBinding.detach();
      scope.clearAll();

      expect(cell.isDisposed, isFalse);
      expect(chat.paintable, same(cell));
    });

    test('is pinned when the panel let go of it before the attach', () {
      final cellBinding = scope.attach(_gif, _cell, _profile);
      final cell = producer.last.advance(AssetStage.full);
      cellBinding.detach();

      final chat = scope.attach(_gif, _chat, _profile);
      scope.clearAll();

      expect(cell.isDisposed, isFalse);
      expect(chat.paintable, same(cell));
    });

    test('goes back to the budget when the entry has its own stage', () {
      final cellBinding = scope.attach(_gif, _cell, _profile);
      final cell = producer.last.advance(AssetStage.full);
      final chat = scope.attach(_gif, _chat, _profile);
      cellBinding.detach();

      producer.last.advance(AssetStage.firstFrame);
      expect(chat.paintable, isNot(same(cell)));
      scope.clearAll();

      expect(cell.isDisposed, isTrue);
    });

    test('goes back to the budget when the binding detaches', () {
      final cellBinding = scope.attach(_gif, _cell, _profile);
      final cell = producer.last.advance(AssetStage.full);
      final chat = scope.attach(_gif, _chat, _profile);
      cellBinding.detach();

      chat.detach();
      scope.clearAll();

      expect(cell.isDisposed, isTrue);
      expect(scope.entryCount, 0);
    });
  });
}
