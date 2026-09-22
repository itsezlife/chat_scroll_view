import 'package:flutter/painting.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

/// Membership gate for nested table pan uses md's construct-time
/// [BlockPainter$ScrollableTable.enabled] (see ChatMarkdownBody theme cache).
void main() {
  const wideTable = '''
| Path |
| --- |
| packages/flutter/lib/src/material/scrollbar_theme.dart |
| packages/flutter/lib/src/material/animated_icons/animated_icons.dart |
''';

  BlockPainter$ScrollableTable build({required bool enabled}) {
    final md = Markdown.fromString(wideTable);
    final table = md.blocks.whereType<MD$Table>().single;
    return BlockPainter$ScrollableTable(
      header: table.header,
      rows: table.rows,
      alignments: table.alignments,
      theme: MarkdownThemeData(textStyle: const TextStyle(fontSize: 14)),
      enabled: enabled,
    );
  }

  test('enabled:false refuses pan deltas but restores offset', () {
    final painter = build(enabled: false);
    addTearDown(painter.dispose);

    expect(painter.layout(180).width, 180);
    expect(painter.canPanHorizontally, isFalse);
    expect(painter.applyScrollDelta(40), isFalse);
    expect(painter.scrollOffset, 0);

    painter.restoreScrollOffset(50);
    expect(painter.scrollOffset, 50);
    expect(painter.applyScrollDelta(10), isFalse);
    expect(painter.scrollOffset, 50);
  });

  test('enabled:true pans; recreating with enabled:false stops deltas', () {
    final open = build(enabled: true);
    addTearDown(open.dispose);
    open.layout(180);
    expect(open.canPanHorizontally, isTrue);
    expect(open.applyScrollDelta(40), isTrue);
    final saved = open.scrollOffset;
    expect(saved, greaterThan(0));

    final gated = build(enabled: false);
    addTearDown(gated.dispose);
    gated.layout(180);
    gated.restoreScrollOffset(saved);
    expect(gated.scrollOffset, saved);
    expect(gated.canPanHorizontally, isFalse);
    expect(gated.applyScrollDelta(40), isFalse);
    expect(gated.scrollOffset, saved);
  });
}
