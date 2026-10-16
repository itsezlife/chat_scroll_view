import 'package:content_model/content_model.dart';
import 'package:emoji_data/src/search/keyword_index.dart';
import 'package:test/test.dart';

void main() {
  group('fold', () {
    test('lower-cases and collapses separators to single spaces', () {
      expect(KeywordIndex.fold('  Flag:   Germany! '), 'flag germany');
    });

    test('keeps letters of every script and combining marks', () {
      expect(KeywordIndex.fold('Флаг: Германия'), 'флаг германия');
      expect(KeywordIndex.fold('झंडा: जर्मनी'), 'झंडा जर्मनी');
      expect(KeywordIndex.fold('café'), 'café');
    });

    test('treats full-width and general punctuation as separators', () {
      expect(KeywordIndex.fold('旗、ドイツ'), '旗 ドイツ');
      expect(KeywordIndex.fold('one two—three'), 'one two three');
    });

    test('keeps digits and is empty for nothing but separators', () {
      expect(KeywordIndex.fold('1st place'), '1st place');
      expect(KeywordIndex.fold(' !? '), isEmpty);
    });
  });

  test('indexing a large non-Latin pack stays fast', () {
    final keywords = {
      for (var i = 0; i < 2000; i++)
        ContentKey.unicode(String.fromCharCode(0x1F300 + i)): [
          'флаг: Германия $i',
          'очень длинное русское ключевое слово',
          'ещё одно',
        ],
    };
    final stopwatch = Stopwatch()..start();

    KeywordIndex(KeywordPack(language: 'ru', version: 0, keywords: keywords));

    expect(stopwatch.elapsedMilliseconds, lessThan(200));
  });
}
