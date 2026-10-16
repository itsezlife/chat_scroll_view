import 'package:chat_composer/chat_composer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerHeader.prioritised', () {
    final reply = ComposerHeader.reply(name: 'Ada', preview: 'hi');
    final edit = ComposerHeader.edit(preview: 'draft');
    final forward = ComposerHeader.forward(title: 'Forward', preview: '2');
    final link = ComposerHeader.linkPreview(title: 'site', preview: 'url');
    final suggestion = ComposerHeader.suggestion(
      builder: (context) => const SizedBox(),
    );

    test('is null when there is no candidate', () {
      expect(ComposerHeader.prioritised(const []), isNull);
      expect(ComposerHeader.prioritised([null, null]), isNull);
    });

    test('picks edit over reply over forward over link over suggestion', () {
      expect(
        ComposerHeader.prioritised([suggestion, link, forward, reply, edit]),
        same(edit),
      );
      expect(
        ComposerHeader.prioritised([suggestion, link, forward, reply]),
        same(reply),
      );
      expect(
        ComposerHeader.prioritised([suggestion, link, forward]),
        same(forward),
      );
      expect(ComposerHeader.prioritised([suggestion, link]), same(link));
      expect(ComposerHeader.prioritised([suggestion]), same(suggestion));
    });

    test('keeps the first of two equal priorities', () {
      final other = ComposerHeader.reply(name: 'Bo', preview: 'yo');

      expect(ComposerHeader.prioritised([reply, other]), same(reply));
      expect(ComposerHeader.prioritised([other, reply]), same(other));
    });

    test('skips null candidates', () {
      expect(ComposerHeader.prioritised([null, link, null]), same(link));
    });
  });

  group('ComposerHeader.priority', () {
    test('orders the kinds strictly', () {
      final ordered = [
        ComposerHeader.edit(preview: ''),
        ComposerHeader.reply(name: '', preview: ''),
        ComposerHeader.forward(title: '', preview: ''),
        ComposerHeader.linkPreview(title: '', preview: ''),
        ComposerHeader.suggestion(builder: (context) => const SizedBox()),
      ].map((header) => header.priority).toList();

      expect(ordered, [...ordered]..sort((a, b) => b.compareTo(a)));
      expect(ordered.toSet(), hasLength(5));
    });
  });
}
