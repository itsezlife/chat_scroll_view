import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/src/viewport/catalog_paragraph_cache.dart';

ui.Paragraph _paragraph(String text) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle())..addText(text);
  return builder.build()..layout(const ui.ParagraphConstraints(width: 100));
}

void main() {
  late CatalogParagraphCache<String> cache;
  late List<ui.Paragraph> made;

  ui.Paragraph obtain(String key) => cache.obtain(key, () {
    final paragraph = _paragraph(key);
    made.add(paragraph);
    return paragraph;
  });

  setUp(() {
    cache = CatalogParagraphCache<String>(limit: 3);
    made = <ui.Paragraph>[];
  });

  test('lays a paragraph out once per key', () {
    final first = obtain('a');

    expect(obtain('a'), same(first));
    expect(made, hasLength(1));
  });

  test('never holds more than its limit', () {
    for (var i = 0; i < 10; i++) {
      obtain('k$i');
      expect(cache.length, lessThanOrEqualTo(3));
    }
    expect(cache.length, 3);
  });

  test('releases the paragraph it evicts, and only that one', () {
    ['a', 'b', 'c'].forEach(obtain);

    obtain('d');

    expect(made[0].debugDisposed, isTrue, reason: 'a was the oldest');
    expect(made.sublist(1).map((p) => p.debugDisposed), everyElement(isFalse));
  });

  test('a lookup keeps its entry alive: the least recently used goes', () {
    ['a', 'b', 'c'].forEach(obtain);
    obtain('a');

    obtain('d');

    expect(made[1].debugDisposed, isTrue, reason: 'b is now the oldest');
    expect(made[0].debugDisposed, isFalse);
  });

  test('clear releases every paragraph', () {
    ['a', 'b'].forEach(obtain);

    cache.clear();

    expect(cache.length, 0);
    expect(made.map((p) => p.debugDisposed), everyElement(isTrue));
  });
}
