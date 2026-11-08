import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_texture_warmer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFrameTextureHost host;
  late FrameTexturePool pool;

  setUp(() {
    host = FakeFrameTextureHost();
    pool = FrameTexturePool(host: host);
    addTearDown(pool.dispose);
  });

  test('warms a handful of textures of the class the chat\'s stickers are '
      'drawn in', () async {
    // A sticker or GIF message is 112 points square: 336 px at 3x, in the
    // 384 class.
    ChatTextureWarmer.warm(pool, stickerExtent: 112, devicePixelRatio: 3);
    await pumpEventQueue();

    expect(host.created, hasLength(6));
    expect(host.created.toSet(), {(width: 384, height: 384)});
  });

  test('warms nothing for a sticker larger than the largest class', () async {
    ChatTextureWarmer.warm(pool, stickerExtent: 4000, devicePixelRatio: 3);
    await pumpEventQueue();

    expect(host.created, isEmpty);
  });
}
