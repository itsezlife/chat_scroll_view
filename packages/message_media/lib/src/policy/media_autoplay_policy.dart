import 'package:content_model/content_model.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:meta/meta.dart';

/// Which videos play inline, muted, in their box.
enum MediaVideoAutoplay {
  /// None: a video shows its still and the status control.
  never,

  /// A video alone in its block, or one whose cell spans the block's whole
  /// width.
  singleOrFullWidth,

  /// Every video.
  always,
}

/// Which boxes play inline, muted, while they show.
///
/// A host flag: a host turns it off (or down) for an energy setting or its
/// own preference with [copyWith]. Playing still waits for the content,
/// which the scope's auto-download rules fetch.
///
/// | | Android | iOS | Desktop |
/// | --- | --- | --- | --- |
/// | [animations] | yes | yes | yes |
/// | [video] | single or full width | always (the host maps its energy setting) | never |
@immutable
final class MediaAutoplayPolicy {
  /// Autoplay of [animations] and [video].
  const MediaAutoplayPolicy({required this.animations, required this.video});

  /// The Android family.
  const MediaAutoplayPolicy.android()
    : this(animations: true, video: MediaVideoAutoplay.singleOrFullWidth);

  /// The iOS family.
  const MediaAutoplayPolicy.ios()
    : this(animations: true, video: MediaVideoAutoplay.always);

  /// The desktop family.
  const MediaAutoplayPolicy.desktop()
    : this(animations: true, video: MediaVideoAutoplay.never);

  /// Nothing plays inline.
  static const off = MediaAutoplayPolicy(
    animations: false,
    video: MediaVideoAutoplay.never,
  );

  /// Whether animations (GIFs) play.
  final bool animations;

  /// Which videos play.
  final MediaVideoAutoplay video;

  /// Whether [cell] plays inline in [block].
  bool plays(MediaCell cell, MediaBlock block) => switch (cell.kind) {
    MediaItemKind.animation => animations,
    MediaItemKind.video => switch (video) {
      MediaVideoAutoplay.never => false,
      MediaVideoAutoplay.always => true,
      MediaVideoAutoplay.singleOrFullWidth =>
        block.cells.length == 1 ||
            (cell.neighbours.left == MediaNeighbour.bubbleEdge &&
                cell.neighbours.right == MediaNeighbour.bubbleEdge),
    },
    _ => false,
  };

  /// A copy with the given values replaced.
  MediaAutoplayPolicy copyWith({bool? animations, MediaVideoAutoplay? video}) =>
      MediaAutoplayPolicy(
        animations: animations ?? this.animations,
        video: video ?? this.video,
      );

  @override
  bool operator ==(Object other) =>
      other is MediaAutoplayPolicy &&
      other.animations == animations &&
      other.video == video;

  @override
  int get hashCode => Object.hash(animations, video);
}
