/// Captions in the attach selection: the shared caption (the sheet's field)
/// and each item's own, under each family's rule.
library;

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

RichText _t(String text) => RichText.plain(text);

void main() {
  final a = AttachItems.photo('a');
  final b = AttachItems.photo('b');
  final c = AttachItems.photo('c');

  AttachSelection of(AttachPolicy policy, [List<AttachItem> items = const []]) {
    final selection = AttachSelection(
      policy: policy,
      limits: const AttachLimits(),
    );
    items.forEach(selection.toggle);
    return selection;
  }

  test('the stock families: Android the first item, iOS forced, desktop '
      'and web shared only', () {
    expect(const AttachPolicy.android().itemCaptions, ItemCaptions.firstItem);
    expect(const AttachPolicy.ios().itemCaptions, ItemCaptions.forced);
    expect(const AttachPolicy.desktop().itemCaptions, ItemCaptions.sharedOnly);
    expect(const AttachPolicy.web().itemCaptions, ItemCaptions.sharedOnly);
  });

  group('Android: the shared caption is the first item\'s', () {
    const policy = AttachPolicy.android();

    test('the first item edits the shared caption', () {
      final s = of(policy, [a, b]);
      s.setCaptionOf(a, _t('hi'));
      expect(s.caption, _t('hi'));
      expect(s.captionOf(a.id), _t('hi'));
    });

    test('for all media while no other item has its own: every item shows '
        'the shared caption, and the same text keeps it so', () {
      final s = of(policy, [a, b, c])..caption = _t('all');
      expect(s.captionOf(b.id), _t('all'));
      expect(s.captionOf(c.id), _t('all'));
      s.setCaptionOf(b, _t('all'));
      expect(s.ownCaptionOf(b.id), isNull);
      expect(s.captionsPerItem, isFalse);
    });

    test('another item given a different text leaves it: every item keeps '
        'its own, the first the shared one', () {
      final s = of(policy, [a, b, c])..caption = _t('all');
      s.setCaptionOf(b, _t('bee'));
      expect(s.captionsPerItem, isTrue);
      expect(s.captionOf(a.id), _t('all'));
      expect(s.captionOf(b.id), _t('bee'));
      expect(s.captionOf(c.id), RichText.empty);
    });

    test('typing a caption on an item not selected selects it', () {
      final s = of(policy, [a]);
      s.setCaptionOf(b, _t('bee'));
      expect(s.contains(b.id), isTrue);
      expect(s.captionOf(b.id), _t('bee'));
    });

    test('deselect clears an item\'s caption; selecting it again starts '
        'with none', () {
      final s = of(policy, [a, b]);
      s.setCaptionOf(b, _t('bee'));
      s
        ..toggle(b)
        ..toggle(b);
      expect(s.ownCaptionOf(b.id), isNull);
    });

    test('a reorder keeps each caption with its item: the new first item\'s '
        'becomes the shared caption', () {
      final s = of(policy, [a, b])..caption = _t('aye');
      s.setCaptionOf(b, _t('bee'));
      s.reorder(1, 0);
      expect(s.caption, _t('bee'));
      expect(s.captionOf(a.id), _t('aye'));
      expect(s.captionOf(b.id), _t('bee'));
    });

    test('the first item deselected: the next one\'s caption, if it has '
        'one, becomes the shared caption', () {
      final s = of(policy, [a, b, c])..caption = _t('aye');
      s.setCaptionOf(b, _t('bee'));
      s.toggle(a);
      expect(s.caption, _t('bee'));
      expect(s.ownCaptionOf(b.id), isNull);
    });

    test('the items sent carry their own captions', () {
      final s = of(policy, [a, b])..caption = _t('aye');
      s.setCaptionOf(b, _t('bee'));
      expect(
        [for (final item in s.itemsToSend) item.caption],
        [null, _t('bee')],
      );
    });
  });

  group('iOS: the shared caption is forced over every item', () {
    const policy = AttachPolicy.ios();

    test('while it is set every item shows it and an edit edits it', () {
      final s = of(policy, [a, b])..caption = _t('all');
      expect(s.captionOf(b.id), _t('all'));
      s.setCaptionOf(b, _t('all!'));
      expect(s.caption, _t('all!'));
      expect(s.ownCaptionOf(b.id), isNull);
    });

    test('while it is empty each item keeps its own, selected or not', () {
      final s = of(policy, [a]);
      s.setCaptionOf(b, _t('bee'));
      expect(s.contains(b.id), isFalse);
      expect(s.captionOf(b.id), _t('bee'));
      s.toggle(b);
      expect(s.captionOf(b.id), _t('bee'));
      s.toggle(b);
      expect(s.captionOf(b.id), _t('bee'));
    });

    test('a reorder moves nothing between captions', () {
      final s = of(policy, [a, b]);
      s
        ..setCaptionOf(a, _t('aye'))
        ..setCaptionOf(b, _t('bee'))
        ..reorder(1, 0);
      expect(s.caption, RichText.empty);
      expect(s.captionOf(a.id), _t('aye'));
    });
  });

  group('desktop and web: one shared caption', () {
    for (final policy in const [AttachPolicy.desktop(), AttachPolicy.web()]) {
      test('every item edits it (${policy.runtimeType})', () {
        final s = of(policy, [a, b]);
        s.setCaptionOf(b, _t('x'));
        expect(s.caption, _t('x'));
        expect(s.ownCaptionOf(b.id), isNull);
        expect(s.itemsToSend.map((i) => i.caption), [null, null]);
      });
    }
  });

  test('a caption change signals captionChanges, not changes', () {
    final s = of(const AttachPolicy.android(), [a, b]);
    var items = 0, captions = 0;
    s.changes.addListener(() => items++);
    s.captionChanges.addListener(() => captions++);
    s.caption = _t('x');
    s.setCaptionOf(b, _t('y'));
    expect(items, 0);
    expect(captions, 2);
  });
}
