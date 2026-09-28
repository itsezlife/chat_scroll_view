import 'package:meta/meta.dart';

/// Where the latest navigation asked its target row to sit, and how far that
/// request has advanced.
///
/// ## Kinds
///
/// - [AlignmentPlacement] — band alignment from `jumpTo` / `animateTo`.
/// - [CenterBandPlacement] — paint-band ray offset from `jumpToCenterBand`.
/// - [FractionalPlacement] — band top a fraction into the target row, from
///   `jumpToFraction` (the scrollbar grab).
///
/// A controller holds at most one placement; arming a new one replaces the
/// previous one of any kind.
///
/// Center Band and fractional placements are **in-row**: they seat a point
/// inside the target row, so they are seated on a known-newest target too,
/// and the jump-to-tail pin stays off while one is pending. An alignment
/// target that is the known newest yields to the tail pin instead.
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

  /// Alignment placement for [messageId]; [alignment] and [tailFitFraction]
  /// are clamped to `0..1`. [pixelOffset] is additive after the alignment
  /// seat (positive moves the target down the band).
  factory NavigationPlacement.alignment(
    int messageId,
    double alignment, {
    double? tailFitFraction,
    double pixelOffset = 0,
  }) => AlignmentPlacement(
    messageId: messageId,
    alignment: alignment.clamp(0.0, 1.0),
    tailFitFraction: tailFitFraction?.clamp(0.0, 1.0),
    pixelOffset: pixelOffset,
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

  /// Fractional placement for [messageId]; [fraction] is clamped to `0..1`.
  factory NavigationPlacement.fractional(int messageId, double fraction) =>
      FractionalPlacement(
        messageId: messageId,
        fraction: fraction.clamp(0.0, 1.0),
      );

  /// Target message id — the row the placement seats.
  final int messageId;

  /// Whether the placement has landed on its loaded target and is held.
  final bool isHeld;

  /// Whether the placement seats a point inside the target row — see the
  /// in-row rule above.
  bool get isInRow => switch (this) {
    AlignmentPlacement() => false,
    CenterBandPlacement() || FractionalPlacement() => true,
  };

  /// This placement in the held phase. Idempotent.
  NavigationPlacement hold();

  /// This placement seated on [messageId] instead, phase unchanged — used
  /// when the viewport clamps a jump target onto a known id.
  NavigationPlacement retarget(int messageId);
}

/// Band alignment placement: the target's top sits at
/// `topPad + alignment * (band height - row height) + pixelOffset`.
///
/// ## Tail-or-target decision
///
/// A non-null [tailFitFraction] is an undecided tail-or-target jump. The
/// viewport decides in the first layout that lays out the target as a loaded
/// row, before it applies the placement: a tail outcome releases the
/// placement and pins the tail, a target outcome continues with
/// [withoutTailFit] and the usual pending → held lifecycle. The decision
/// rides the placement so every release — user scroll, `scrollBy`, the next
/// navigation — also cancels it, and a cancelled decision reports nothing.
///
/// ## Pixel offset
///
/// [pixelOffset] is added after the alignment seat and re-applied with it by
/// the hold. Contract: `ChatScrollController.jumpTo`.
@immutable
final class AlignmentPlacement extends NavigationPlacement {
  /// Creates an alignment placement; [alignment] and [tailFitFraction] MUST
  /// be in `0..1`.
  const AlignmentPlacement({
    required super.messageId,
    required this.alignment,
    this.tailFitFraction,
    this.pixelOffset = 0,
    super.isHeld = false,
  }) : assert(alignment >= 0 && alignment <= 1, 'alignment outside 0..1'),
       assert(
         tailFitFraction == null ||
             (tailFitFraction >= 0 && tailFitFraction <= 1),
         'tailFitFraction outside 0..1',
       );

  /// Fraction of the free band space above the target, `0..1`.
  final double alignment;

  /// Fraction of the viewport height the span from the target's body top to
  /// the newest message's bottom must fit in for a tail outcome; `null` once
  /// decided, or for a plain alignment jump.
  final double? tailFitFraction;

  /// Logical pixels added after the alignment seat. Positive moves the
  /// target down the scroll band (away from the band top).
  final double pixelOffset;

  /// This placement with the tail-or-target decision made for the target:
  /// same target, alignment, [pixelOffset], and phase, no [tailFitFraction].
  AlignmentPlacement withoutTailFit() => switch (tailFitFraction) {
    null => this,
    _ => AlignmentPlacement(
      messageId: messageId,
      alignment: alignment,
      pixelOffset: pixelOffset,
      isHeld: isHeld,
    ),
  };

  /// This placement in the held phase. Idempotent. The tail-or-target
  /// decision MUST already be made: an undecided placement is never held.
  @override
  AlignmentPlacement hold() {
    assert(
      tailFitFraction == null,
      'a tail-or-target placement is decided before it is held',
    );
    return isHeld
        ? this
        : AlignmentPlacement(
            messageId: messageId,
            alignment: alignment,
            pixelOffset: pixelOffset,
            isHeld: true,
          );
  }

  @override
  AlignmentPlacement retarget(int messageId) => AlignmentPlacement(
    messageId: messageId,
    alignment: alignment,
    tailFitFraction: tailFitFraction,
    pixelOffset: pixelOffset,
    isHeld: isHeld,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlignmentPlacement &&
        other.messageId == messageId &&
        other.alignment == alignment &&
        other.tailFitFraction == tailFitFraction &&
        other.pixelOffset == pixelOffset &&
        other.isHeld == isHeld;
  }

  @override
  int get hashCode => Object.hash(
    messageId,
    alignment,
    tailFitFraction,
    pixelOffset,
    isHeld,
  );

  @override
  String toString() =>
      'AlignmentPlacement(messageId: $messageId, alignment: $alignment, '
      'tailFitFraction: $tailFitFraction, pixelOffset: $pixelOffset, '
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

/// Fractional placement: the scroll band's top edge sits [fraction] of the
/// way into the target row, so the row's top is at
/// `topPad - fraction * row height`.
///
/// The fraction, not a pixel offset, is what rides the lifecycle: while
/// pending, every layout re-seats it against the row's current height, so a
/// skeleton that loads with its real height lands at the same fraction.
@immutable
final class FractionalPlacement extends NavigationPlacement {
  /// Creates a fractional placement; [fraction] MUST be in `0..1`.
  const FractionalPlacement({
    required super.messageId,
    required this.fraction,
    super.isHeld = false,
  }) : assert(fraction >= 0 && fraction <= 1, 'fraction outside 0..1');

  /// How far into the target row the band top sits: `0` at its top edge,
  /// `1` at its bottom edge.
  final double fraction;

  @override
  FractionalPlacement hold() => isHeld
      ? this
      : FractionalPlacement(
          messageId: messageId,
          fraction: fraction,
          isHeld: true,
        );

  @override
  FractionalPlacement retarget(int messageId) => FractionalPlacement(
    messageId: messageId,
    fraction: fraction,
    isHeld: isHeld,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FractionalPlacement &&
        other.messageId == messageId &&
        other.fraction == fraction &&
        other.isHeld == isHeld;
  }

  @override
  int get hashCode => Object.hash(messageId, fraction, isHeld);

  @override
  String toString() =>
      'FractionalPlacement(messageId: $messageId, fraction: $fraction, '
      'isHeld: $isHeld)';
}
