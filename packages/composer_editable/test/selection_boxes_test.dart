import 'dart:ui' as ui;

import 'package:composer_editable/src/widget/selection_boxes.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeHybridSelectionBoxes', () {
    TextSelection softLineAt(int offset) {
      if (offset < 10) {
        return const TextSelection(baseOffset: 0, extentOffset: 10);
      }
      return const TextSelection(baseOffset: 10, extentOffset: 20);
    }

    TextSelection hardLineAt(int offset) {
      if (offset < 10) {
        return const TextSelection(baseOffset: 0, extentOffset: 10);
      }
      if (offset < 11) {
        return const TextSelection(baseOffset: 10, extentOffset: 11);
      }
      return const TextSelection(baseOffset: 11, extentOffset: 20);
    }

    List<ui.TextBox> boxesFor(TextSelection range, ui.BoxWidthStyle style) {
      final double left = style == ui.BoxWidthStyle.max ? 100 : 0;
      return <ui.TextBox>[
        ui.TextBox.fromLTRBD(
          left,
          range.start.toDouble(),
          left + range.end - range.start,
          range.end.toDouble(),
          ui.TextDirection.ltr,
        ),
      ];
    }

    test('multi-line: prior lines max, last selected line tight', () {
      final boxes = computeHybridSelectionBoxes(
        selection: const TextSelection(baseOffset: 0, extentOffset: 15),
        lineAtOffset: hardLineAt,
        boxesFor: boxesFor,
      );
      expect(boxes, hasLength(2));
      expect(boxes[0].left, 100);
      expect(boxes[1].left, 0);
    });

    test('single-line selection: only tight', () {
      final boxes = computeHybridSelectionBoxes(
        selection: const TextSelection(baseOffset: 2, extentOffset: 8),
        lineAtOffset: softLineAt,
        boxesFor: boxesFor,
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.left, 0);
    });

    test('soft-wrap exclusive upstream: content line tight', () {
      final boxes = computeHybridSelectionBoxes(
        selection: const TextSelection(
          baseOffset: 0,
          extentOffset: 10,
          affinity: TextAffinity.upstream,
        ),
        lineAtOffset: softLineAt,
        boxesFor: boxesFor,
        exclusiveEndKind: (int offset) =>
            offset == 10 ? ExclusiveLineEndKind.softWrap : null,
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.left, 0);
      expect(boxes.single.bottom, 10);
    });

    test('soft-wrap exclusive downstream: content line max', () {
      final boxes = computeHybridSelectionBoxes(
        selection: const TextSelection(
          baseOffset: 0,
          extentOffset: 10,
          affinity: TextAffinity.downstream,
        ),
        lineAtOffset: softLineAt,
        boxesFor: boxesFor,
        exclusiveEndKind: (int offset) =>
            offset == 10 ? ExclusiveLineEndKind.softWrap : null,
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.left, 100);
      expect(boxes.single.bottom, 10);
    });

    test(
      'hard-break exclusive upstream: content line tight, omits newline',
      () {
        final boxes = computeHybridSelectionBoxes(
          selection: const TextSelection(
            baseOffset: 0,
            extentOffset: 11,
            affinity: TextAffinity.upstream,
          ),
          lineAtOffset: hardLineAt,
          boxesFor: boxesFor,
          exclusiveEndKind: (int offset) =>
              offset == 11 ? ExclusiveLineEndKind.hardBreak : null,
        );
        expect(boxes, hasLength(1));
        expect(boxes.single.left, 0);
        expect(boxes.single.bottom, 10);
      },
    );

    test(
      'hard-break exclusive downstream: content line max, omits newline',
      () {
        final boxes = computeHybridSelectionBoxes(
          selection: const TextSelection(
            baseOffset: 0,
            extentOffset: 11,
            affinity: TextAffinity.downstream,
          ),
          lineAtOffset: hardLineAt,
          boxesFor: boxesFor,
          exclusiveEndKind: (int offset) =>
              offset == 11 ? ExclusiveLineEndKind.hardBreak : null,
        );
        expect(boxes, hasLength(1));
        expect(boxes.single.left, 100);
        expect(boxes.single.bottom, 10);
      },
    );

    test('content-less hard-break downstream: synthesizes max trailing', () {
      final boxes = computeHybridSelectionBoxes(
        selection: const TextSelection(
          baseOffset: 10,
          extentOffset: 11,
          affinity: TextAffinity.downstream,
        ),
        lineAtOffset: hardLineAt,
        boxesFor: boxesFor,
        exclusiveEndKind: (int offset) =>
            offset == 11 ? ExclusiveLineEndKind.hardBreak : null,
        synthesizeContentLessTrailing:
            ({
              required TextSelection contentEndLine,
              required ui.BoxWidthStyle style,
            }) {
              expect(style, ui.BoxWidthStyle.max);
              expect(contentEndLine.start, 0);
              return <ui.TextBox>[
                ui.TextBox.fromLTRBD(
                  50,
                  contentEndLine.start.toDouble(),
                  100,
                  10,
                  ui.TextDirection.ltr,
                ),
              ];
            },
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.left, 50);
      expect(boxes.single.right, 100);
    });

    test('content-less hard-break upstream: synthesizes tight trailing', () {
      final boxes = computeHybridSelectionBoxes(
        selection: const TextSelection(
          baseOffset: 10,
          extentOffset: 11,
          affinity: TextAffinity.upstream,
        ),
        lineAtOffset: hardLineAt,
        boxesFor: boxesFor,
        exclusiveEndKind: (int offset) =>
            offset == 11 ? ExclusiveLineEndKind.hardBreak : null,
        synthesizeContentLessTrailing:
            ({
              required TextSelection contentEndLine,
              required ui.BoxWidthStyle style,
            }) {
              expect(style, ui.BoxWidthStyle.tight);
              return <ui.TextBox>[
                ui.TextBox.fromLTRBD(80, 0, 80, 10, ui.TextDirection.ltr),
              ];
            },
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.left, 80);
      expect(boxes.single.right, 80);
    });

    test('hard-break with glyphs on content line is not content-less', () {
      final boxes = computeHybridSelectionBoxes(
        selection: const TextSelection(
          baseOffset: 0,
          extentOffset: 11,
          affinity: TextAffinity.downstream,
        ),
        lineAtOffset: hardLineAt,
        boxesFor: boxesFor,
        exclusiveEndKind: (int offset) =>
            offset == 11 ? ExclusiveLineEndKind.hardBreak : null,
        synthesizeContentLessTrailing:
            ({
              required TextSelection contentEndLine,
              required ui.BoxWidthStyle style,
            }) {
              fail('should not synthesize when glyphs remain on content line');
            },
      );
      expect(boxes, hasLength(1));
      expect(boxes.single.left, 100);
    });

    test(
      'exclusive end with empty engine boxes on content line: synthesizes',
      () {
        List<ui.TextBox> emptyContentBoxes(
          TextSelection range,
          ui.BoxWidthStyle style,
        ) {
          if (range.start >= 10) {
            return const <ui.TextBox>[];
          }
          return boxesFor(range, style);
        }

        final boxes = computeHybridSelectionBoxes(
          selection: const TextSelection(
            baseOffset: 0,
            extentOffset: 15,
            affinity: TextAffinity.downstream,
          ),
          lineAtOffset: softLineAt,
          boxesFor: emptyContentBoxes,
          exclusiveEndKind: (int offset) =>
              offset == 15 ? ExclusiveLineEndKind.softWrap : null,
          synthesizeContentLessTrailing:
              ({
                required TextSelection contentEndLine,
                required ui.BoxWidthStyle style,
              }) {
                expect(contentEndLine.start, 10);
                return <ui.TextBox>[
                  ui.TextBox.fromLTRBD(40, 10, 100, 15, ui.TextDirection.ltr),
                ];
              },
        );
        expect(boxes, hasLength(2));
        expect(boxes[0].left, 100);
        expect(boxes[1].left, 40);
        expect(boxes[1].right, 100);
      },
    );

    test(
      'soft-wrap exclusive multi-line downstream: prior max, content max',
      () {
        TextSelection threeLines(int offset) {
          if (offset < 10) {
            return const TextSelection(baseOffset: 0, extentOffset: 10);
          }
          if (offset < 20) {
            return const TextSelection(baseOffset: 10, extentOffset: 20);
          }
          return const TextSelection(baseOffset: 20, extentOffset: 30);
        }

        final boxes = computeHybridSelectionBoxes(
          selection: const TextSelection(
            baseOffset: 0,
            extentOffset: 20,
            affinity: TextAffinity.downstream,
          ),
          lineAtOffset: threeLines,
          boxesFor: boxesFor,
          exclusiveEndKind: (int offset) =>
              offset == 20 ? ExclusiveLineEndKind.softWrap : null,
        );
        expect(boxes, hasLength(2));
        expect(boxes[0].left, 100);
        expect(boxes[1].left, 100);
      },
    );
  });

  group('exclusiveLineEndKind', () {
    test('distinguishes soft wrap and hard break', () {
      const text = 'aaaaaAAAAA\nbbbb';
      TextSelection lineAt(int offset) {
        if (offset < 5) {
          return const TextSelection(baseOffset: 0, extentOffset: 5);
        }
        if (offset < 11) {
          return const TextSelection(baseOffset: 5, extentOffset: 11);
        }
        return const TextSelection(baseOffset: 11, extentOffset: 15);
      }

      expect(
        exclusiveLineEndKind(offset: 5, plainText: text, lineAtOffset: lineAt),
        ExclusiveLineEndKind.softWrap,
      );
      expect(
        exclusiveLineEndKind(offset: 11, plainText: text, lineAtOffset: lineAt),
        ExclusiveLineEndKind.hardBreak,
      );
    });
  });

  group('exclusiveEndUsesEmptyEdge', () {
    test('extent at end: follows affinity', () {
      expect(
        exclusiveEndUsesEmptyEdge(
          const TextSelection(
            baseOffset: 0,
            extentOffset: 10,
            affinity: TextAffinity.downstream,
          ),
        ),
        isTrue,
      );
      expect(
        exclusiveEndUsesEmptyEdge(
          const TextSelection(
            baseOffset: 0,
            extentOffset: 10,
            affinity: TextAffinity.upstream,
          ),
        ),
        isFalse,
      );
    });

    test('reversed: follows affinity (preserve exclusive-end mode)', () {
      expect(
        exclusiveEndUsesEmptyEdge(
          const TextSelection(
            baseOffset: 10,
            extentOffset: 0,
            affinity: TextAffinity.upstream,
          ),
        ),
        isFalse,
      );
      expect(
        exclusiveEndUsesEmptyEdge(
          const TextSelection(
            baseOffset: 10,
            extentOffset: 0,
            affinity: TextAffinity.downstream,
          ),
        ),
        isTrue,
      );
    });
  });

  group('affinityForHandleDrag', () {
    test('exclusive fixed base preserves drag-start affinity', () {
      expect(
        affinityForHandleDrag(
          fixedBaseIsExclusiveEnd: true,
          dragStartAffinity: TextAffinity.upstream,
          hitTestAffinity: TextAffinity.downstream,
        ),
        TextAffinity.upstream,
      );
      expect(
        affinityForHandleDrag(
          fixedBaseIsExclusiveEnd: true,
          dragStartAffinity: TextAffinity.downstream,
          hitTestAffinity: TextAffinity.upstream,
        ),
        TextAffinity.downstream,
      );
    });

    test('non-exclusive fixed base uses hit-test affinity', () {
      expect(
        affinityForHandleDrag(
          fixedBaseIsExclusiveEnd: false,
          dragStartAffinity: TextAffinity.upstream,
          hitTestAffinity: TextAffinity.downstream,
        ),
        TextAffinity.downstream,
      );
      expect(
        affinityForHandleDrag(
          fixedBaseIsExclusiveEnd: false,
          dragStartAffinity: TextAffinity.downstream,
          hitTestAffinity: TextAffinity.upstream,
        ),
        TextAffinity.upstream,
      );
    });
  });

  group('affinityForHandleDragStable', () {
    test('keeps previous affinity when extent offset is unchanged', () {
      expect(
        affinityForHandleDragStable(
          extent: 6229,
          previousExtent: 6229,
          previousAffinity: TextAffinity.upstream,
          candidateAffinity: TextAffinity.downstream,
        ),
        TextAffinity.upstream,
      );
    });

    test('uses candidate when extent moves', () {
      expect(
        affinityForHandleDragStable(
          extent: 6228,
          previousExtent: 6229,
          previousAffinity: TextAffinity.upstream,
          candidateAffinity: TextAffinity.downstream,
        ),
        TextAffinity.downstream,
      );
    });
  });

  group('preserveExclusiveEndAffinityOnHandleDrag', () {
    test(
      'preserves only when exclusive end is fixed (extent <= fixedBase)',
      () {
        expect(
          preserveExclusiveEndAffinityOnHandleDrag(
            fixedBaseIsExclusiveLineEnd: true,
            fixedBase: 6245,
            extent: 6206,
          ),
          isTrue,
        );
        expect(
          preserveExclusiveEndAffinityOnHandleDrag(
            fixedBaseIsExclusiveLineEnd: true,
            fixedBase: 6245,
            extent: 6245,
          ),
          isTrue,
        );
      },
    );

    test(
      'does not preserve when exclusive end is moving (extent > fixedBase)',
      () {
        // Fixed start may sit at a line start after wrap/break — that must not
        // freeze affinity while dragging the exclusive end as extent.
        expect(
          preserveExclusiveEndAffinityOnHandleDrag(
            fixedBaseIsExclusiveLineEnd: true,
            fixedBase: 6245,
            extent: 6270,
          ),
          isFalse,
        );
        // Exact soft-wrap log scenario (issue 02): hardBreak fixedBase + moving
        // exclusive end must not freeze drag-start downstream over hit upstream.
        expect(
          preserveExclusiveEndAffinityOnHandleDrag(
            fixedBaseIsExclusiveLineEnd: true,
            fixedBase: 6245,
            extent: 6271,
          ),
          isFalse,
        );
      },
    );

    test(
      'moving exclusive end: hit-test wins over drag-start (issue 02 log)',
      () {
        final bool preserve = preserveExclusiveEndAffinityOnHandleDrag(
          fixedBaseIsExclusiveLineEnd: true,
          fixedBase: 6245,
          extent: 6271,
        );
        expect(
          affinityForHandleDrag(
            fixedBaseIsExclusiveEnd: preserve,
            dragStartAffinity: TextAffinity.downstream,
            hitTestAffinity: TextAffinity.upstream,
          ),
          TextAffinity.upstream,
        );
      },
    );

    test('does not preserve when fixed base is not an exclusive line end', () {
      expect(
        preserveExclusiveEndAffinityOnHandleDrag(
          fixedBaseIsExclusiveLineEnd: false,
          fixedBase: 6245,
          extent: 6206,
        ),
        isFalse,
      );
    });
  });

  group('selectionsMatchForHybridCache', () {
    test('same offsets and affinity match', () {
      expect(
        selectionsMatchForHybridCache(
          const TextSelection(
            baseOffset: 3,
            extentOffset: 69,
            affinity: TextAffinity.downstream,
          ),
          const TextSelection(
            baseOffset: 3,
            extentOffset: 69,
            affinity: TextAffinity.downstream,
          ),
        ),
        isTrue,
      );
    });

    test('same offsets, different affinity do not match', () {
      // TextSelection.== would treat these as equal when non-collapsed.
      final a = const TextSelection(
        baseOffset: 3,
        extentOffset: 69,
        affinity: TextAffinity.downstream,
      );
      final b = const TextSelection(
        baseOffset: 3,
        extentOffset: 69,
        affinity: TextAffinity.upstream,
      );
      expect(a == b, isTrue);
      expect(selectionsMatchForHybridCache(a, b), isFalse);
    });

    test('subrange offsets do not match paint selection', () {
      expect(
        selectionsMatchForHybridCache(
          const TextSelection(baseOffset: 3, extentOffset: 69),
          const TextSelection(baseOffset: 67, extentOffset: 68),
        ),
        isFalse,
      );
    });
  });

  group('stitchSelectionLines', () {
    test('adjacent lines meet halfway across a sub-pixel gap', () {
      final lines = stitchSelectionLines(const <Rect>[
        Rect.fromLTRB(0, 4.3, 100, 24.9),
        Rect.fromLTRB(0, 25.4, 100, 47.9),
      ], maxGap: 10);
      expect(lines[0].bottom, 25.15);
      expect(lines[1].top, 25.15);
    });

    test('every run of a line takes the stitched bounds', () {
      final lines = stitchSelectionLines(const <Rect>[
        Rect.fromLTRB(0, 0, 40, 10),
        Rect.fromLTRB(40, 0, 100, 10),
        Rect.fromLTRB(0, 11, 100, 21),
      ], maxGap: 10);
      expect(lines[0].bottom, 10.5);
      expect(lines[1].bottom, 10.5);
      expect(lines[2].top, 10.5);
    });

    test('a gap wider than maxGap stays a break', () {
      const List<Rect> rects = <Rect>[
        Rect.fromLTRB(0, 0, 100, 10),
        Rect.fromLTRB(0, 30, 100, 40),
      ];
      expect(stitchSelectionLines(rects, maxGap: 10), rects);
    });

    test('lines that already touch are left alone', () {
      const List<Rect> rects = <Rect>[
        Rect.fromLTRB(0, 0, 100, 10),
        Rect.fromLTRB(0, 10, 100, 20),
      ];
      expect(stitchSelectionLines(rects, maxGap: 10), rects);
    });

    test('a single line is left alone', () {
      const List<Rect> rects = <Rect>[
        Rect.fromLTRB(0, 0, 40, 10),
        Rect.fromLTRB(40, 0, 100, 10),
      ];
      expect(stitchSelectionLines(rects, maxGap: 10), rects);
    });
  });
}
