import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';

Duration _ms(int ms) => Duration(milliseconds: ms);

void main() {
  AssetPlaybackContract.run(() {
    final fake = FakeAssetPaintable(
      frameDurations: [_ms(40), _ms(60), _ms(80)],
    );
    return AssetPlaybackHarness(
      paintable: fake,
      frameDurations: fake.frameDurations,
      frameAt:
          (
            time, {
            animate = true,
            loop = false,
            rest = AssetRestFrame.first,
          }) async {
            paintOnce(fake, time, animate: animate, loop: loop, rest: rest);
            return fake.frameShown;
          },
    );
  });
}
