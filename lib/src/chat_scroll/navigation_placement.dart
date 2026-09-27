import 'package:meta/meta.dart';

/// Where the latest navigation asked its target row to sit, and how far that
/// request has advanced.
///
/// ## Kinds
///
/// - [AlignmentPlacement] — band alignment from `jumpTo` / `animateTo`.
/// - [CenterBandPlacement] — paint-band ray offset from `jumpToCenterBand`.
///
/// A controller holds at most one placement; arming a new one replaces the
/// previous one of either kind.
///
/// ## Lifecycle
///
/// **Pending** ([isHeld] `false`) — armed, not yet applied to a loaded target
/// row. The viewport snaps the target on every layout so a skeleton that
/// loads with a new height is re-seated.
///
/// **Held** ([isHeld] `true`) — applied to the loaded target. The viewport
/// re-applies it only when the scroll band's top edge moves or the target
/// row's row chrome changes; every other layout leaves the anchor to its
/// usual owners (bottom inset compensation, clamps, height changes
/// elsewhere).
///
/// **Released** — no placement. Reached by user scroll, `scrollBy`, the next
/// navigation, or the viewport (target no longer the anchor, tail pin takes
/// over, placement cannot apply).
///
/// Immutable: phase and target changes produce a new value via [hold] and
/// [retarget].
@immutable
sealed class NavigationPlacement {
  const NavigationPlacement({required this.messageId, required this.isHeld});

  /// Alignment placement for [messageId]; [alignment] is clamped to `0..1`.
  factory NavigationPlacement.alignment(int messageId, double alignment) =>
      AlignmentPlacement(
        messageId: messageId,
        alignment: alignment.clamp(0.0, 1.0),
      );

  /// Center Band placement for [messageId]; [offsetFromMessageTop] is
  /// clamped into the row by the viewport at apply time.
  factory NavigationPlacement.centerBand(
    int messageId,
    double offsetFromMessageTop,
  ) => CenterBandPlacement(
    messageId: messageId,
    offsetFromMessageTop: offsetFromMessageTop,
  );

  /// Target message id — the row the placement seats.
  final int messageId;

  /// Whether the placement has landed on its loaded target and is held.
  final bool isHeld;

  /// This placement in the held phase. Idempotent.
  NavigationPlacement hold();

  /// This placement seated on [messageId] instead, phase unchanged — used
  /// when the viewport clamps a jump target onto a known id.
  NavigationPlacement retarget(int messageId);
}

/// Band alignment placement: the target's top sits at
/// `topPad + alignment * (band height - row height)`.
@immutable
final class AlignmentPlacement extends NavigationPlacement {
  /// Creates an alignment placement; [alignment] MUST be in `0..1`.
  const AlignmentPlacement({
    required super.messageId,
    required this.alignment,
    super.isHeld = false,
  }) : assert(alignment >= 0 && alignment <= 1, 'alignment outside 0..1');

  /// Fraction of the free band space above the target, `0..1`.
  final double alignment;

  @override
  AlignmentPlacement hold() => isHeld
      ? this
      : AlignmentPlacement(
          messageId: messageId,
          alignment: alignment,
          isHeld: true,
        );

  @override
  AlignmentPlacement retarget(int messageId) => AlignmentPlacement(
    messageId: messageId,
    alignment: alignment,
    isHeld: isHeld,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlignmentPlacement &&
        other.messageId == messageId &&
        other.alignment == alignment &&
        other.isHeld == isHeld;
  }

  @override
  int get hashCode => Object.hash(messageId, alignment, isHeld);

  @override
  String toString() =>
      'AlignmentPlacement(messageId: $messageId, alignment: $alignment, '
      'isHeld: $isHeld)';
}

/// Center Band placement: the fixed 50% paint-band ray hits
/// `target top + offsetFromMessageTop`.
@immutable
final class CenterBandPlacement extends NavigationPlacement {
  /// Creates a Center Band placement.
  const CenterBandPlacement({
    required super.messageId,
    required this.offsetFromMessageTop,
    super.isHeld = false,
  });

  /// Pixels from the target's top edge to the point the band ray hits.
  final double offsetFromMessageTop;

  @override
  CenterBandPlacement hold() => isHeld
      ? this
      : CenterBandPlacement(
          messageId: messageId,
          offsetFromMessageTop: offsetFromMessageTop,
          isHeld: true,
        );

  @override
  CenterBandPlacement retarget(int messageId) => CenterBandPlacement(
    messageId: messageId,
    offsetFromMessageTop: offsetFromMessageTop,
    isHeld: isHeld,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CenterBandPlacement &&
        other.messageId == messageId &&
        other.offsetFromMessageTop == offsetFromMessageTop &&
        other.isHeld == isHeld;
  }

  @override
  int get hashCode => Object.hash(messageId, offsetFromMessageTop, isHeld);

  @override
  String toString() =>
      'CenterBandPlacement(messageId: $messageId, '
      'offsetFromMessageTop: $offsetFromMessageTop, isHeld: $isHeld)';
}
