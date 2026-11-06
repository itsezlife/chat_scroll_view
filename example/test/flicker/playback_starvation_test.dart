/// Ticket 55, symptoms 2 and 3: a clip the user can see stops playing.
///
/// (2) "GIFs in the panel might occasionally just stop playing: after it
/// loaded it can play some and just stop." (3) "When opening the panel the
/// same GIFs in the messages are not playing."
///
/// **Seam:** the real `VideoFrameScheduler` + `VideoAnimationPaintable` + frame
/// pool over a scripted engine and a manual clock (`test/support/flicker/video_rig.dart`),
/// one scheduler for the chat and the panel as the example builds it. Every
/// surface paints each of its visible clips every frame, which is what a
/// viewport does for a visible animated cell. The probe is the renderer's log:
/// the frames copied into a page, per clip, per span of clock time.
///
/// **Run** (red on purpose; not part of `test/unit_test.dart`):
/// `cd example && flutter test test_diagnostic/flicker/playback_starvation_diagnosis_test.dart`
///
/// The `control:` tests are the same scenes with the cap lifted. They are the
/// proof the probe can go green; they fix nothing.
library;

import 'package:flutter_test/flutter_test.dart';

import '../../test/support/flicker/video_rig.dart';

const _second = Duration(seconds: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A clip that is painted every frame and "plays" renders about 30 frames a
  // second; stalled it renders none. Anything near 15 is advancing.
  const advancing = 15;

  group('symptom 3: the chat stops when the panel opens', () {
    for (final (name, cap) in [
      ('cap 6 (shipped)', 6),
      ('control: cap 99', 99),
    ]) {
      test(
        '3 chat clips, then 8 panel clips: all 11 keep advancing ($name)',
        () async {
          final rig = VideoRig(maxAdvancing: cap);
          addTearDown(rig.dispose);
          final chat = [for (var i = 1; i <= 3; i++) await rig.clip(i)];
          final panel = [for (var i = 11; i <= 18; i++) await rig.clip(i)];

          // The chat alone for a second: everything plays.
          for (var i = 0; i < 62; i++) {
            await rig.step(painted: chat);
          }
          final opened = rig.now;
          for (final tag in [1, 2, 3]) {
            expect(
              rig.framesOf(tag, Duration.zero, opened),
              greaterThan(advancing),
              reason: 'chat clip $tag plays before the panel opens',
            );
          }

          // The panel opens: 8 GIF cells lease and paint, the chat goes on
          // painting its 3 (nothing covers it).
          for (var i = 0; i < 200; i++) {
            await rig.step(painted: [...chat, ...panel]);
          }
          final end = rig.now;
          final stalled = <String>[
            for (final tag in [1, 2, 3, ...List.generate(8, (i) => 11 + i)])
              if (rig.framesOf(tag, end - _second * 2, end) < advancing * 2)
                '${tag < 10 ? 'chat' : 'panel'}#$tag '
                    '${rig.framesOf(tag, end - _second * 2, end)} frames in 2 s',
          ];
          expect(
            stalled,
            isEmpty,
            reason: 'visible clips frozen while painted every frame',
          );
        },
      );
    }
  });

  group('symptom 2: a panel clip plays, then stops', () {
    for (final (name, cap, clips) in [
      ('cap 6 (shipped), 7 clips', 6, 7),
      ('minimal: cap 1, 2 clips', 1, 2),
      ('control: cap 99, 7 clips', 99, 7),
    ]) {
      test('clips load one after another and none stops ($name)', () async {
        final rig = VideoRig(maxAdvancing: cap);
        addTearDown(rig.dispose);
        final all = [for (var i = 1; i <= clips; i++) await rig.clip(i)];

        // Clip i starts painting at i * 0.5 s (its load finished then) and
        // paints every frame from there on; all stay visible.
        final live = <Object>[];
        for (var i = 0; i < 40 * clips + 120; i++) {
          final startedBy = (rig.now.inMilliseconds / 500).floor();
          await rig.step(painted: all.take(startedBy.clamp(0, clips)));
          live.add(startedBy);
        }
        final end = rig.now;
        final stopped = <String>[
          for (var tag = 1; tag <= clips; tag++)
            if (end - (rig.lastFrameAt(tag) ?? Duration.zero) >
                const Duration(milliseconds: 500))
              'clip #$tag: last frame at ${rig.lastFrameAt(tag)}, '
                  'now $end, ${rig.framesOf(tag, Duration.zero, end)} frames '
                  'in total',
        ];
        expect(
          stopped,
          isEmpty,
          reason: 'clips that played and then froze while still painted',
        );
      });
    }
  });
}
