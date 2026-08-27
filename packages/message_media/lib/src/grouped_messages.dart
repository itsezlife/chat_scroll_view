import 'dart:math' as math;

import 'package:message_media/src/grouped_message_position.dart';
import 'package:message_media/src/media_kind.dart';
import 'package:message_media/src/media_layout_metrics.dart';

/// One member’s layout input for [GroupedMessages.calculate].
///
/// Owns: aspect, optional [kind], and caption / invert flags consumed during
/// calculate. Does not own: Message ID, bytes, or image-receiver state.
///
/// [aspectRatio] MUST be `> 0`; non-positive values are coerced to `1.0`
/// inside calculate so a bad thumb does not abort the whole mosaic.
final class GroupedMediaMember {
  /// Creates a member with [aspectRatio] (width / height).
  const GroupedMediaMember({
    required this.aspectRatio,
    this.kind = MediaKind.photo,
    this.hasCaption = false,
    this.invertMedia = false,
  });

  /// Width / height of the photo or video thumb used for proportions.
  final double aspectRatio;

  /// Photo vs video — ignored for mosaic geometry (shared box).
  final MediaKind kind;

  /// When true, participates in [GroupedMessages.hasCaption] /
  /// [GroupedMessages.captionIndex] selection (first caption wins; a second
  /// clears the index on the photo/video path).
  final bool hasCaption;

  /// When true on any member, [GroupedMessages.captionAbove] becomes true
  /// (`invert_media`).
  final bool invertMedia;
}

/// Result of Telegram `MessageObject.GroupedMessages.calculate` for N≥2
/// photo/video members (documents / `isDocuments` path is out of scope).
///
/// Owns: ordered [positions], sibling / caption summary flags. Does not own:
/// per-chat map lifecycle, single-media size ([computeSingleMediaSize]), or
/// pixel rect projection ([MosaicLayout]).
///
/// ## Layout model
///
/// Abstract span width is [MediaLayoutMetrics.groupedMaxSizeWidth] (800);
/// height fractions use [MediaLayoutMetrics.groupedMaxSizeHeight] (814).
/// [displayMinSide] rescales Java `dp(120)` / `dp(40)` into that span space
/// (default [MediaLayoutMetrics.referenceDisplayMinSide]).
///
/// Count 1 is rejected — use [computeSingleMediaSize]. Empty input yields an
/// empty result. Aspects > 2 force the multi-attempt line solver used for
/// awkward albums.
///
/// ## Fixed-count paths (2 / 3 / 4)
///
/// When no aspect exceeds 2.0, Java uses closed-form “ww” / “qq” / mixed /
/// first-narrow sibling layouts. `ph` is a fraction of 814; some Java lines
/// subtract an already-normalized `firstHeight` from `maxSizeHeight` — that
/// quirk is preserved so TRACE tables match.
///
/// ## Attempt solver (forceCalc / N>4)
///
/// Crops aspect ratios into `[0.66667, 1.7]`, enumerates 2–4 line partitions,
/// and picks the attempt whose total height is closest to
/// `maxSizeWidth/3*4`, with penalties for descending line counts and short
/// lines.
///
/// ## Edge / span finish
///
/// After positions are set, outgoing vs incoming flips which cells receive
/// [MediaLayoutMetrics.firstSpanAdditionalSize] on `spanSize` and which get
/// [GroupedMessagePosition.edge] (avatar / outer edge).
///
/// ## Caption summary
///
/// Photo/video path: the first captioning member wins [captionIndex]; a second
/// caption clears it (Java `captionMessage = null`). [captionAbove] is true if
/// any member has [GroupedMediaMember.invertMedia].
final class GroupedMessages {
  GroupedMessages._({
    required this.positions,
    required this.hasSibling,
    required this.hasCaption,
    required this.captionAbove,
    required this.captionIndex,
    required this.maxSizeWidth,
  });

  /// Empty result for count &lt; 2 (no positions, caption flags false).
  factory GroupedMessages.empty() => GroupedMessages._(
    positions: const [],
    hasSibling: false,
    hasCaption: false,
    captionAbove: false,
    captionIndex: null,
    maxSizeWidth: MediaLayoutMetrics.groupedMaxSizeWidth.round(),
  );

  /// Positions in member order (length equals input when count ≥ 2).
  final List<GroupedMessagePosition> positions;

  /// True when any position carries [GroupedMessagePosition.siblingHeights]
  /// (narrow-first / tall-sibling layouts).
  final bool hasSibling;

  /// True if at least one member had [GroupedMediaMember.hasCaption].
  final bool hasCaption;

  /// Caption sits above the mosaic when any member had
  /// [GroupedMediaMember.invertMedia].
  final bool captionAbove;

  /// Index of the sole caption-owning member; `null` when none or when
  /// multiple captions cancel on the photo/video path.
  final int? captionIndex;

  /// Abstract width for this pass (800, or 750 when [needShare] was true).
  final int maxSizeWidth;

  /// Ports `MessageObject.GroupedMessages.calculate` for photo/video mosaics.
  ///
  /// Returns [GroupedMessages.empty] when [members.length] &lt; 2 — N=1 MUST use
  /// [computeSingleMediaSize] instead.
  ///
  /// [isOut] flips which cells receive [MediaLayoutMetrics.firstSpanAdditionalSize]
  /// and [GroupedMessagePosition.edge]. [needShare] shrinks the abstract width
  /// by 50 (share-button gutter). [displayMinSide] freezes the
  /// `minWidth` / `paddingsWidth` rescale (default
  /// [MediaLayoutMetrics.referenceDisplayMinSide]).
  static GroupedMessages calculate({
    required List<GroupedMediaMember> members,
    bool isOut = false,
    bool needShare = false,
    double displayMinSide = MediaLayoutMetrics.referenceDisplayMinSide,
  }) {
    final count = members.length;
    if (count < 2) {
      return GroupedMessages.empty();
    }

    // --- Inputs / proportions -----------------------------------------------
    var maxSizeWidth = MediaLayoutMetrics.groupedMaxSizeWidth.round();
    var firstSpanAdditionalSize = MediaLayoutMetrics.firstSpanAdditionalSize;
    const maxSizeHeight = MediaLayoutMetrics.groupedMaxSizeHeight;

    final proportions = StringBuffer();
    var averageAspectRatio = 1.0;
    var maxX = 0;
    var forceCalc = false;
    var hasSibling = false;
    var hasCaption = false;
    var checkCaption = true;
    var captionAbove = false;
    int? captionIndex;

    final posArray = <GroupedMessagePosition>[
      for (var a = 0; a < count; a++)
        GroupedMessagePosition(
          last: a == count - 1,
          aspectRatio: members[a].aspectRatio <= 0
              ? 1.0
              : members[a].aspectRatio,
        ),
    ];

    for (var a = 0; a < count; a++) {
      final member = members[a];
      final position = posArray[a];
      if (member.invertMedia) {
        captionAbove = true;
      }
      final ar = position.aspectRatio;
      if (ar > 1.2) {
        proportions.write('w');
      } else if (ar < 0.8) {
        proportions.write('n');
      } else {
        proportions.write('q');
      }
      averageAspectRatio += ar;
      if (ar > 2.0) {
        forceCalc = true;
      }
      if (member.hasCaption) {
        if (checkCaption && captionIndex == null) {
          captionIndex = a;
          checkCaption = false;
        } else {
          // Multiple captions on photo/video path cancel captionMessage.
          captionIndex = null;
        }
        hasCaption = true;
      }
    }

    if (needShare) {
      maxSizeWidth -= 50;
      firstSpanAdditionalSize += 50;
    }

    final minHeight = MediaLayoutMetrics.minMediaHeight;
    final minWidth =
        (MediaLayoutMetrics.minMediaHeight / (displayMinSide / maxSizeWidth))
            .truncate();
    final paddingsWidth = (40.0 / (displayMinSide / maxSizeWidth)).truncate();
    final maxAspectRatio = maxSizeWidth / maxSizeHeight;
    averageAspectRatio /= count;
    final minH = MediaLayoutMetrics.minGroupedLineHeight / maxSizeHeight;
    final pString = proportions.toString();

    const left = GroupedPositionFlags.left;
    const right = GroupedPositionFlags.right;
    const top = GroupedPositionFlags.top;
    const bottom = GroupedPositionFlags.bottom;

    // --- Fixed-count paths (2 / 3 / 4) ---------------------------------------
    if (!forceCalc && (count == 2 || count == 3 || count == 4)) {
      if (count == 2) {
        final position1 = posArray[0];
        final position2 = posArray[1];
        if (pString == 'ww' &&
            averageAspectRatio > 1.4 * maxAspectRatio &&
            position1.aspectRatio - position2.aspectRatio < 0.2) {
          final height =
              _round(
                math.min(
                  maxSizeWidth / position1.aspectRatio,
                  math.min(
                    maxSizeWidth / position2.aspectRatio,
                    maxSizeHeight / 2.0,
                  ),
                ),
              ) /
              maxSizeHeight;
          position1.set(0, 0, 0, 0, maxSizeWidth, height, left | right | top);
          position2.set(
            0,
            0,
            1,
            1,
            maxSizeWidth,
            height,
            left | right | bottom,
          );
        } else if (pString == 'ww' || pString == 'qq') {
          final width = maxSizeWidth ~/ 2;
          final height =
              _round(
                math.min(
                  width / position1.aspectRatio,
                  math.min(width / position2.aspectRatio, maxSizeHeight),
                ),
              ) /
              maxSizeHeight;
          position1.set(0, 0, 0, 0, width, height, left | bottom | top);
          position2.set(1, 1, 0, 0, width, height, right | bottom | top);
          maxX = 1;
        } else {
          var secondWidth = math
              .max(
                0.4 * maxSizeWidth,
                _round(
                  maxSizeWidth /
                      position1.aspectRatio /
                      (1.0 / position1.aspectRatio +
                          1.0 / position2.aspectRatio),
                ).toDouble(),
              )
              .truncate();
          var firstWidth = maxSizeWidth - secondWidth;
          if (firstWidth < minWidth) {
            final diff = minWidth - firstWidth;
            firstWidth = minWidth;
            secondWidth -= diff;
          }
          final height =
              math.min(
                maxSizeHeight,
                _round(
                  math.min(
                    firstWidth / position1.aspectRatio,
                    secondWidth / position2.aspectRatio,
                  ),
                ).toDouble(),
              ) /
              maxSizeHeight;
          position1.set(0, 0, 0, 0, firstWidth, height, left | bottom | top);
          position2.set(1, 1, 0, 0, secondWidth, height, right | bottom | top);
          maxX = 1;
        }
      } else if (count == 3) {
        final position1 = posArray[0];
        final position2 = posArray[1];
        final position3 = posArray[2];
        if (pString[0] == 'n') {
          final thirdHeight = math.min(
            maxSizeHeight * 0.5,
            _round(
              position2.aspectRatio *
                  maxSizeWidth /
                  (position3.aspectRatio + position2.aspectRatio),
            ).toDouble(),
          );
          final secondHeight = maxSizeHeight - thirdHeight;
          final rightWidth = math
              .max(
                minWidth,
                math.min(
                  maxSizeWidth * 0.5,
                  _round(
                    math.min(
                      thirdHeight * position3.aspectRatio,
                      secondHeight * position2.aspectRatio,
                    ),
                  ).toDouble(),
                ),
              )
              .truncate();
          final leftWidth = _round(
            math.min(
              maxSizeHeight * position1.aspectRatio + paddingsWidth,
              maxSizeWidth - rightWidth,
            ),
          );
          position1.set(0, 0, 0, 1, leftWidth, 1.0, left | bottom | top);
          position2.set(
            1,
            1,
            0,
            0,
            rightWidth,
            secondHeight / maxSizeHeight,
            right | top,
          );
          position3.set(
            0,
            1,
            1,
            1,
            rightWidth,
            thirdHeight / maxSizeHeight,
            right | bottom,
          );
          position3.spanSize = maxSizeWidth;
          position1.siblingHeights = <double>[
            thirdHeight / maxSizeHeight,
            secondHeight / maxSizeHeight,
          ];
          if (isOut) {
            position1.spanSize = maxSizeWidth - rightWidth;
          } else {
            position2.spanSize = maxSizeWidth - leftWidth;
            position3.leftSpanOffset = leftWidth;
          }
          hasSibling = true;
          maxX = 1;
        } else {
          final firstHeight =
              _round(
                math.min(
                  maxSizeWidth / position1.aspectRatio,
                  maxSizeHeight * 0.66,
                ),
              ) /
              maxSizeHeight;
          position1.set(
            0,
            1,
            0,
            0,
            maxSizeWidth,
            firstHeight,
            left | right | top,
          );
          final width = maxSizeWidth ~/ 2;
          // Java subtracts the already-normalized [firstHeight] from
          // maxSizeHeight (814 - fraction), not from the pixel remainder.
          var secondHeight =
              math.min(
                maxSizeHeight - firstHeight,
                _round(
                  math.min(
                    width / position2.aspectRatio,
                    width / position3.aspectRatio,
                  ),
                ).toDouble(),
              ) /
              maxSizeHeight;
          if (secondHeight < minH) {
            secondHeight = minH;
          }
          position2.set(0, 0, 1, 1, width, secondHeight, left | bottom);
          position3.set(1, 1, 1, 1, width, secondHeight, right | bottom);
          maxX = 1;
        }
      } else {
        // count == 4
        final position1 = posArray[0];
        final position2 = posArray[1];
        final position3 = posArray[2];
        final position4 = posArray[3];
        if (pString[0] == 'w') {
          final h0 =
              _round(
                math.min(
                  maxSizeWidth / position1.aspectRatio,
                  maxSizeHeight * 0.66,
                ),
              ) /
              maxSizeHeight;
          position1.set(0, 2, 0, 0, maxSizeWidth, h0, left | right | top);
          var h = _round(
            maxSizeWidth /
                (position2.aspectRatio +
                    position3.aspectRatio +
                    position4.aspectRatio),
          ).toDouble();
          var w0 = math
              .max(
                minWidth,
                math.min(maxSizeWidth * 0.4, h * position2.aspectRatio),
              )
              .truncate();
          var w2 = math
              .max(
                math.max(minWidth, maxSizeWidth * 0.33),
                h * position4.aspectRatio,
              )
              .truncate();
          var w1 = maxSizeWidth - w0 - w2;
          if (w1 < 58) {
            final diff = 58 - w1;
            w1 = 58;
            w0 -= diff ~/ 2;
            w2 -= diff - diff ~/ 2;
          }
          h = math.min(maxSizeHeight - h0, h);
          h /= maxSizeHeight;
          if (h < minH) {
            h = minH;
          }
          position2.set(0, 0, 1, 1, w0, h, left | bottom);
          position3.set(1, 1, 1, 1, w1, h, bottom);
          position4.set(2, 2, 1, 1, w2, h, right | bottom);
          maxX = 2;
        } else {
          final w = math.max(
            minWidth,
            _round(
              maxSizeHeight /
                  (1.0 / position2.aspectRatio +
                      1.0 / position3.aspectRatio +
                      1.0 / position4.aspectRatio),
            ),
          );
          final h0 = math.min(
            0.33,
            math.max(minHeight, w / position2.aspectRatio) / maxSizeHeight,
          );
          final h1 = math.min(
            0.33,
            math.max(minHeight, w / position3.aspectRatio) / maxSizeHeight,
          );
          final h2 = 1.0 - h0 - h1;
          final w0 = _round(
            math.min(
              maxSizeHeight * position1.aspectRatio + paddingsWidth,
              maxSizeWidth - w,
            ),
          );
          position1.set(0, 0, 0, 2, w0, h0 + h1 + h2, left | top | bottom);
          position2.set(1, 1, 0, 0, w, h0, right | top);
          position3.set(0, 1, 1, 1, w, h1, right);
          position3.spanSize = maxSizeWidth;
          position4.set(0, 1, 2, 2, w, h2, right | bottom);
          position4.spanSize = maxSizeWidth;
          if (isOut) {
            position1.spanSize = maxSizeWidth - w;
          } else {
            position2.spanSize = maxSizeWidth - w0;
            position3.leftSpanOffset = w0;
            position4.leftSpanOffset = w0;
          }
          position1.siblingHeights = <double>[h0, h1, h2];
          hasSibling = true;
          maxX = 1;
        }
      }
    } else {
      // --- Attempt solver (forceCalc / N>4) ---------------------------------
      final croppedRatios = List<double>.generate(count, (a) {
        var r = averageAspectRatio > 1.1
            ? math.max(1.0, posArray[a].aspectRatio)
            : math.min(1.0, posArray[a].aspectRatio);
        return math.max(0.66667, math.min(1.7, r));
      });

      final attempts = <_LayoutAttempt>[];
      for (var firstLine = 1; firstLine < croppedRatios.length; firstLine++) {
        final secondLine = croppedRatios.length - firstLine;
        if (firstLine > 3 || secondLine > 3) {
          continue;
        }
        attempts.add(
          _LayoutAttempt(
            lineCounts: [firstLine, secondLine],
            heights: [
              _multiHeight(croppedRatios, 0, firstLine, maxSizeWidth),
              _multiHeight(
                croppedRatios,
                firstLine,
                croppedRatios.length,
                maxSizeWidth,
              ),
            ],
          ),
        );
      }
      for (
        var firstLine = 1;
        firstLine < croppedRatios.length - 1;
        firstLine++
      ) {
        for (
          var secondLine = 1;
          secondLine < croppedRatios.length - firstLine;
          secondLine++
        ) {
          final thirdLine = croppedRatios.length - firstLine - secondLine;
          if (firstLine > 3 ||
              secondLine > (averageAspectRatio < 0.85 ? 4 : 3) ||
              thirdLine > 3) {
            continue;
          }
          attempts.add(
            _LayoutAttempt(
              lineCounts: [firstLine, secondLine, thirdLine],
              heights: [
                _multiHeight(croppedRatios, 0, firstLine, maxSizeWidth),
                _multiHeight(
                  croppedRatios,
                  firstLine,
                  firstLine + secondLine,
                  maxSizeWidth,
                ),
                _multiHeight(
                  croppedRatios,
                  firstLine + secondLine,
                  croppedRatios.length,
                  maxSizeWidth,
                ),
              ],
            ),
          );
        }
      }
      for (
        var firstLine = 1;
        firstLine < croppedRatios.length - 2;
        firstLine++
      ) {
        for (
          var secondLine = 1;
          secondLine < croppedRatios.length - firstLine;
          secondLine++
        ) {
          for (
            var thirdLine = 1;
            thirdLine < croppedRatios.length - firstLine - secondLine;
            thirdLine++
          ) {
            final fourthLine =
                croppedRatios.length - firstLine - secondLine - thirdLine;
            if (firstLine > 3 ||
                secondLine > 3 ||
                thirdLine > 3 ||
                fourthLine > 3) {
              continue;
            }
            attempts.add(
              _LayoutAttempt(
                lineCounts: [firstLine, secondLine, thirdLine, fourthLine],
                heights: [
                  _multiHeight(croppedRatios, 0, firstLine, maxSizeWidth),
                  _multiHeight(
                    croppedRatios,
                    firstLine,
                    firstLine + secondLine,
                    maxSizeWidth,
                  ),
                  _multiHeight(
                    croppedRatios,
                    firstLine + secondLine,
                    firstLine + secondLine + thirdLine,
                    maxSizeWidth,
                  ),
                  _multiHeight(
                    croppedRatios,
                    firstLine + secondLine + thirdLine,
                    croppedRatios.length,
                    maxSizeWidth,
                  ),
                ],
              ),
            );
          }
        }
      }

      _LayoutAttempt? optimal;
      var optimalDiff = 0.0;
      final maxHeight = maxSizeWidth / 3 * 4;
      for (final attempt in attempts) {
        var height = 0.0;
        var minLineHeight = double.maxFinite;
        for (final h in attempt.heights) {
          height += h;
          if (h < minLineHeight) {
            minLineHeight = h;
          }
        }
        var diff = (height - maxHeight).abs();
        if (attempt.lineCounts.length > 1) {
          final lc = attempt.lineCounts;
          if (lc[0] > lc[1] ||
              (lc.length > 2 && lc[1] > lc[2]) ||
              (lc.length > 3 && lc[2] > lc[3])) {
            diff *= 1.2;
          }
        }
        if (minLineHeight < minWidth) {
          diff *= 1.5;
        }
        if (optimal == null || diff < optimalDiff) {
          optimal = attempt;
          optimalDiff = diff;
        }
      }
      if (optimal == null) {
        return GroupedMessages.empty();
      }

      var index = 0;
      for (var i = 0; i < optimal.lineCounts.length; i++) {
        final c = optimal.lineCounts[i];
        final lineHeight = optimal.heights[i];
        var spanLeft = maxSizeWidth;
        GroupedMessagePosition? posToFix;
        maxX = math.max(maxX, c - 1);
        for (var k = 0; k < c; k++) {
          final ratio = croppedRatios[index];
          final width = (ratio * lineHeight).truncate();
          spanLeft -= width;
          final pos = posArray[index];
          var flags = GroupedPositionFlags.none;
          if (i == 0) {
            flags = flags | top;
          }
          if (i == optimal.lineCounts.length - 1) {
            flags = flags | bottom;
          }
          if (k == 0) {
            flags = flags | left;
            if (isOut) {
              posToFix = pos;
            }
          }
          if (k == c - 1) {
            flags = flags | right;
            if (!isOut) {
              posToFix = pos;
            }
          }
          pos.set(
            k,
            k,
            i,
            i,
            width,
            math.max(minH, lineHeight / maxSizeHeight),
            flags,
          );
          index++;
        }
        if (posToFix case final fix?) {
          fix.pw += spanLeft;
          fix.spanSize += spanLeft;
        }
      }
    }

    // --- Edge / span finish -------------------------------------------------
    for (var a = 0; a < count; a++) {
      final pos = posArray[a];
      if (isOut) {
        if (pos.minX == 0) {
          pos.spanSize += firstSpanAdditionalSize;
        }
        if (pos.hasRight) {
          pos.edge = true;
        }
      } else {
        if (pos.maxX == maxX || pos.hasRight) {
          pos.spanSize += firstSpanAdditionalSize;
        }
        if (pos.hasLeft) {
          pos.edge = true;
        }
      }
    }

    return GroupedMessages._(
      positions: posArray,
      hasSibling: hasSibling,
      hasCaption: hasCaption,
      captionAbove: captionAbove,
      captionIndex: captionIndex,
      maxSizeWidth: maxSizeWidth,
    );
  }

  // --- Helpers --------------------------------------------------------------

  /// Java `Math.round` for non-negative values (`floor(x + 0.5)`).
  static int _round(num value) => (value + 0.5).floor();

  /// Line height = `maxSizeWidth / sum(croppedRatios[start:end])`.
  static double _multiHeight(
    List<double> array,
    int start,
    int end,
    int maxSizeWidth,
  ) {
    var sum = 0.0;
    for (var a = start; a < end; a++) {
      sum += array[a];
    }
    return maxSizeWidth / sum;
  }
}

final class _LayoutAttempt {
  /// One candidate line partition from the forceCalc attempt solver.
  ///
  /// [lineCounts] is cells-per-line; [heights] is absolute line height in the
  /// same units as `maxSizeWidth / sum(croppedRatios)` before ph normalize.
  /// The solver keeps the attempt whose summed heights are closest to
  /// `maxSizeWidth / 3 * 4`, with penalties for descending line counts and
  /// lines shorter than `minWidth`.
  _LayoutAttempt({required this.lineCounts, required this.heights});

  /// Cell counts per mosaic line (length 2–4).
  final List<int> lineCounts;

  /// Absolute heights per line (same length as [lineCounts]).
  final List<double> heights;
}
