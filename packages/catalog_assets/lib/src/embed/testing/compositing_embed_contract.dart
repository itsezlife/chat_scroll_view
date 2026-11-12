import 'package:catalog_assets/src/embed/inline_embed.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a [CompositingEmbedContract] run needs besides the embed: a way to
/// make it play on a platform texture.
final class CompositingEmbedHarness {
  /// Creates a harness around [embed], which does not play yet; [play] makes
  /// it play with its frames on texture [textureId].
  const CompositingEmbedHarness({
    required this.embed,
    required this.play,
    required this.textureId,
  });

  /// The embed under test, live and not playing.
  final CompositingEmbed embed;

  /// Makes the embed play, its frames posted to texture [textureId] once it
  /// is advanced.
  final void Function() play;

  /// The texture the playing embed's frames go to.
  final int textureId;
}

/// The contract every [CompositingEmbed] meets; see its documentation.
abstract final class CompositingEmbedContract {
  /// Runs it as a test group. [create] builds a fresh harness for each test.
  static void run(CompositingEmbedHarness Function() create) {
    // A canvas of a painting context records through the renderer binding.
    TestWidgetsFlutterBinding.ensureInitialized();
    group('CompositingEmbed contract', () {
      late CompositingEmbedHarness h;
      const rect = Rect.fromLTWH(10, 20, 40, 40);

      setUp(() => h = create());
      tearDown(() => h.embed.dispose());

      test('needs compositing only while it plays', () {
        expect(h.embed.needsCompositing, isFalse);

        h.play();

        expect(h.embed.needsCompositing, isTrue);
      });

      test('signals its listeners when it starts to play', () {
        var heard = 0;
        h.embed.addListener(() => heard++);

        h.play();

        expect(heard, greaterThan(0));
      });

      test('a playing embed on a texture is one texture layer about its '
          'rectangle, and draws nothing on the canvas', () {
        h.play();

        final layers = _Composited.of(h.embed, rect);

        final texture = layers.whereType<TextureLayer>().single;
        expect(texture.textureId, h.textureId);
        expect(texture.rect.center, rect.center);
        expect(layers.whereType<PictureLayer>(), isEmpty);
      });

      test('an embed that does not play adds no texture layer', () {
        final layers = _Composited.of(h.embed, rect);

        expect(layers.whereType<TextureLayer>(), isEmpty);
      });

      test('needs no compositing and adds nothing once disposed', () {
        h.play();
        h.embed.dispose();

        expect(h.embed.needsCompositing, isFalse);
        expect(_Composited.of(h.embed, rect), isEmpty);
      });
    });
  }
}

// A painting context over a fresh container layer, so a test reads the
// layers an embed added.
final class _Composited extends PaintingContext {
  _Composited(super.containerLayer, super.estimatedBounds);

  // Every layer under the root after [embed] composited into [rect].
  static List<Layer> of(CompositingEmbed embed, Rect rect) {
    final root = ContainerLayer();
    final context = _Composited(root, Rect.largest);
    embed.composite(context, rect, const InlineEmbedPaintContext());
    context.stopRecordingIfNeeded();
    return _below(root);
  }

  static List<Layer> _below(ContainerLayer layer) => [
    for (
      Layer? child = layer.firstChild;
      child != null;
      child = child.nextSibling
    ) ...[child, if (child is ContainerLayer) ..._below(child)],
  ];
}
