import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/gestures.dart' show PointerDownEvent, PointerUpEvent;
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

const _style = TextStyle(fontSize: 14);

/// A painter that counts its disposal; it lays out one fixed box.
class _CountingPainter implements BlockPainter {
  _CountingPainter(this.owner);

  final _Ledger owner;

  @override
  Size size = Size.zero;

  @override
  void handleTapDown(PointerDownEvent event) {}

  @override
  void handleTapUp(PointerUpEvent event) {}

  @override
  Size layout(double width) => size = Size(width, 10);

  @override
  void paint(Canvas canvas, Size size, double offset) {}

  @override
  void dispose() => owner.disposed++;
}

class _Ledger {
  int built = 0;
  int disposed = 0;

  BlockPainter? build(MD$Block block, MarkdownThemeData theme) {
    built++;
    return _CountingPainter(this);
  }
}

/// Who disposes the painters a theme `builder` makes, through the real body:
/// the engine's own are the body's, a host builder's are the host's unless the
/// host sets [MarkdownThemeData.disposeBuiltPainters].
void main() {
  late ChatSelectionController selection;

  setUp(() => selection = ChatSelectionController());
  tearDown(() => selection.dispose());

  Future<void> mount(
    WidgetTester tester,
    String text, {
    MarkdownThemeData? theme,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          child: ChatMarkdownBody(
            controller: selection,
            messageId: 1,
            markdown: Markdown.fromString(text),
            theme: theme,
          ),
        ),
      ),
    ),
  );

  MarkdownThemeData resolved(WidgetTester tester) =>
      tester.widget<MarkdownWidget>(find.byType(MarkdownWidget)).theme!;

  testWidgets('a body with no host builder disposes the painters it builds', (
    tester,
  ) async {
    await mount(tester, 'one', theme: MarkdownThemeData(textStyle: _style));
    expect(resolved(tester).builder, isNotNull);
    expect(resolved(tester).disposeBuiltPainters, isTrue);
  });

  testWidgets('a host builder alone is not disposed by the body', (
    tester,
  ) async {
    final ledger = _Ledger();
    final theme = MarkdownThemeData(textStyle: _style, builder: ledger.build);
    await mount(tester, 'one', theme: theme);
    expect(resolved(tester).disposeBuiltPainters, isFalse);
    final builtBefore = ledger.built;
    expect(builtBefore, greaterThan(0));

    await mount(tester, 'two', theme: theme);
    expect(ledger.built, greaterThan(builtBefore));
    expect(
      ledger.disposed,
      0,
      reason: 'the replaced painters belong to the host that made them',
    );
  });

  testWidgets(
    'a host builder that opts in has its replaced painters disposed',
    (tester) async {
      final ledger = _Ledger();
      final theme = MarkdownThemeData(
        textStyle: _style,
        builder: ledger.build,
        disposeBuiltPainters: true,
      );
      await mount(tester, 'one', theme: theme);
      expect(resolved(tester).disposeBuiltPainters, isTrue);
      final firstBatch = ledger.built;

      await mount(tester, 'two', theme: theme);
      expect(ledger.disposed, firstBatch);

      final live = ledger.built - ledger.disposed;
      await tester.pumpWidget(const SizedBox());
      expect(ledger.disposed, ledger.built, reason: '$live live ones go too');
    },
  );
}
