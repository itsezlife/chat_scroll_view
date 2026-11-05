import 'package:chat_scroll_view_example/src/common/glyph_warmup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatefulWidget {
  const _Probe();

  static int mounts = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.mounts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Finder get _warmup => find.descendant(
  of: find.byType(GlyphWarmupLayer),
  matching: find.byType(CustomPaint),
);

void main() {
  // The chat screen warms in other tests of this process too.
  setUp(() {
    _Probe.mounts = 0;
    GlyphWarmupLayer.debugReset();
  });
  tearDown(GlyphWarmupLayer.debugReset);

  testWidgets('warms for two frames and keeps the child', (tester) async {
    await tester.pumpWidget(const GlyphWarmupLayer(child: _Probe()));
    expect(_warmup, findsOneWidget);

    await tester.pump();
    expect(_warmup, findsOneWidget);
    await tester.pump();
    expect(_warmup, findsNothing);
    // The child is the same state throughout.
    expect(_Probe.mounts, 1);
  });

  testWidgets('warms once per app run', (tester) async {
    await tester.pumpWidget(const GlyphWarmupLayer(child: _Probe()));
    await tester.pump();
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const GlyphWarmupLayer(child: _Probe()));
    expect(_warmup, findsNothing);
  });

  testWidgets('a disabled layer is its child', (tester) async {
    await tester.pumpWidget(
      const GlyphWarmupLayer(enabled: false, child: _Probe()),
    );
    expect(_warmup, findsNothing);
    expect(find.byType(Stack), findsNothing);
  });
}
