import 'package:emoji_data/src/catalog/emoji_platform_filter.dart';
import 'package:emoji_data/src/emoji_item.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(NativeEmojiPlatformFilter.resetCacheForTests);

  test('native filter caches supported glyphs from platform channel', () async {
    const cat = UnicodeEmojiItem(glyph: '🐱', keywords: ['cat']);
    const dog = UnicodeEmojiItem(glyph: '🐶', keywords: ['dog']);

    final filter = NativeEmojiPlatformFilter(
      channel: _FakeChannel(
        (source) => source.map((glyph) => glyph == '🐱').toList(),
      ),
    );

    final first = await filter.filter([cat, dog]);
    expect(first.map((e) => e.glyph), ['🐱']);

    final second = await filter.filter([cat, dog]);
    expect(second.map((e) => e.glyph), ['🐱']);
  });

  test('missing plugin returns all items unchanged', () async {
    const cat = UnicodeEmojiItem(glyph: '🐱', keywords: ['cat']);
    final filter = NativeEmojiPlatformFilter(
      channel: const MethodChannel('emoji_data_missing_test'),
    );

    final result = await filter.filter([cat]);
    expect(result, [cat]);
  });
}

final class _FakeChannel extends MethodChannel {
  _FakeChannel(this._resolve)
    : super('emoji_data_test', const StandardMethodCodec());

  final List<bool> Function(List<String> source) _resolve;

  @override
  Future<List<T>?> invokeListMethod<T>(String method, [arguments]) async {
    if (method != 'getSupportedEmojis') return null;
    final args = arguments! as Map<Object?, Object?>;
    final source = (args['source'] as List<Object?>).cast<String>();
    return _resolve(source) as List<T>;
  }
}
