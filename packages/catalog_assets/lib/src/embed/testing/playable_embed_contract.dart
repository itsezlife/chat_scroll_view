import 'package:catalog_assets/src/asset/asset_playback.dart';
import 'package:catalog_assets/src/embed/inline_embed.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a [PlayableEmbedContract] run needs besides the embed: a way to end
/// the pass it plays.
final class PlayableEmbedHarness {
  /// Creates a harness around [embed], which starts playing a pass that does
  /// not loop; [endPass] makes that pass finish so the embed reports it.
  const PlayableEmbedHarness({required this.embed, required this.endPass});

  /// The embed under test, live and playing its first pass.
  final PlayableEmbed embed;

  /// Plays the running pass to its end and delivers whatever the embed needs
  /// to notice (a clock tick).
  final void Function() endPass;
}

/// The contract every [PlayableEmbed] meets; see its documentation.
abstract final class PlayableEmbedContract {
  /// Runs it as a test group. [create] builds a fresh harness for each test.
  static void run(PlayableEmbedHarness Function() create) {
    group('PlayableEmbed contract', () {
      late PlayableEmbedHarness h;

      setUp(() => h = create());
      tearDown(() => h.embed.dispose());

      test('plays its first pass and refuses to replay it', () {
        expect(h.embed.playback, AssetPlayback.playing);
        expect(h.embed.replay(), isFalse);
        expect(h.embed.playback, AssetPlayback.playing);
      });

      test('reports the end of a pass and replays it once', () {
        h.endPass();
        expect(h.embed.playback, AssetPlayback.ended);

        expect(h.embed.replay(), isTrue);

        expect(h.embed.playback, AssetPlayback.playing);
        expect(h.embed.replay(), isFalse, reason: 'it is running again');
      });

      test('signals its listeners when the playback changes', () {
        var heard = 0;
        h.embed.addListener(() => heard++);
        h.endPass();
        heard = 0;

        h.embed.replay();

        expect(heard, greaterThan(0));
      });

      test('is idle while hidden mid-pass, and replays nothing hidden', () {
        h.embed.visible = false;
        expect(h.embed.playback, AssetPlayback.idle);

        h.embed.visible = true;
        h.endPass();
        h.embed.visible = false;
        expect(h.embed.replay(), isFalse);
      });

      test('is idle and replays nothing once disposed', () {
        h.endPass();
        h.embed.dispose();

        expect(h.embed.playback, AssetPlayback.idle);
        expect(h.embed.replay(), isFalse);
      });
    });
  }
}
