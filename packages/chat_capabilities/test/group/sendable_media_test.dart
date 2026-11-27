// Values are built at run time on purpose: equality must hold without
// const canonicalisation.
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:test/test.dart';

void main() {
  const everyone = DenialReason.everyone();
  final until = DateTime.utc(2026, 12);

  test('the default allows every kind and denies none', () {
    const media = SendableMedia();
    expect(media.allowed, MediaKindSet.all);
    expect(media.denials, isEmpty);
    for (final kind in MediaKind.values) {
      expect(media.reasonFor(kind), isNull);
    }
    expect(const SendingCapabilities().media, media);
  });

  test("reasonFor returns each denied kind's reason", () {
    final media = SendableMedia(
      allowed: MediaKindSet.of([MediaKind.photo, MediaKind.file]),
      denials: {
        MediaKind.video: DenialReason.restricted(until: until),
        MediaKind.voice: DenialReason.unlockable('premium'),
        MediaKind.roundVideo: DenialReason.other('hostTag'),
      },
    );
    expect(media.reasonFor(MediaKind.photo), isNull);
    expect(media.reasonFor(MediaKind.file), isNull);
    expect(
      media.reasonFor(MediaKind.video),
      DenialReason.restricted(until: until),
    );
    expect(
      media.reasonFor(MediaKind.voice),
      DenialReason.unlockable('premium'),
    );
    expect(
      media.reasonFor(MediaKind.roundVideo),
      DenialReason.other('hostTag'),
    );
  });

  test('a denied kind with no entry reads as everyone', () {
    final media = SendableMedia(allowed: MediaKindSet.none);
    expect(media.reasonFor(MediaKind.animation), everyone);
    expect(media.reasonFor(MediaKind.audio), everyone);
  });

  test('is value-equal, denials by entries', () {
    SendableMedia build(List<MediaKind> order) => SendableMedia(
      allowed: MediaKindSet.of([MediaKind.photo]),
      denials: {for (final kind in order) kind: everyone},
    );
    final a = build([MediaKind.audio, MediaKind.video]);
    final b = build([MediaKind.video, MediaKind.audio]);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(build([MediaKind.audio])));
    expect(SendableMedia(), const SendableMedia());
  });

  test('denials cannot be changed through the value', () {
    final media = SendableMedia(
      allowed: MediaKindSet.none,
      denials: {MediaKind.photo: everyone},
    );
    expect(
      () => media.denials[MediaKind.video] = everyone,
      throwsUnsupportedError,
    );
  });

  test('copyWith replaces allowed and denials', () {
    final media = const SendableMedia().copyWith(
      allowed: MediaKindSet.all.without(MediaKindSet.of([MediaKind.voice])),
      denials: {MediaKind.voice: everyone},
    );
    expect(media.reasonFor(MediaKind.voice), everyone);
    expect(media.copyWith(), media);
    expect(const SendingCapabilities().copyWith(media: media).media, media);
  });
}
