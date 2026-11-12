import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _barrier = Color(0x7F000000);
const _fade = Duration(milliseconds: 200);

// A box that says what it is and keeps a counter, so a box brought back can
// be told from a new one.
class _Box extends StatefulWidget {
  const _Box(this.name);

  final String name;

  @override
  State<_Box> createState() => _BoxState();
}

class _BoxState extends State<_Box> {
  var _taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => setState(() => _taps++),
    child: SizedBox(
      width: 200,
      height: 100,
      child: Text('${widget.name} $_taps', textDirection: TextDirection.ltr),
    ),
  );
}

void main() {
  late BuildContext host;

  Future<void> pumpHost(WidgetTester tester) => tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (c, _, _) => builder(c),
      ),
      home: Builder(
        builder: (context) {
          host = context;
          return const SizedBox.expand();
        },
      ),
    ),
  );

  // Opens a layer with box [name] and lets it come in.
  Future<Future<T?>> open<T>(WidgetTester tester, String name) async {
    final result = ChromeBoxLayer.open<T>(
      host,
      barrierColor: _barrier,
      transitionDuration: _fade,
      builder: (_) => _Box(name),
    );
    await tester.pumpAndSettle();
    return result;
  }

  ChromeBoxLayer layerOf(WidgetTester tester, String name) =>
      ChromeBoxLayer.of(tester.element(find.textContaining(name)));

  BuildContext boxContext(WidgetTester tester, String name) =>
      tester.element(find.textContaining(name));

  // The layers' barriers: the home route's own barrier is not dismissible.
  int barriers(WidgetTester tester) => find
      .byWidgetPredicate((w) => w is ModalBarrier && w.dismissible)
      .evaluate()
      .length;

  testWidgets('show puts the new box in place of the shown one at once, on '
      'the same layer and barrier', (tester) async {
    await pumpHost(tester);
    await open<void>(tester, 'pack');
    expect(barriers(tester), 1);

    final confirm = layerOf(
      tester,
      'pack',
    ).show<bool>((_) => const _Box('confirm'));
    await tester.pump();

    expect(find.textContaining('confirm'), findsOneWidget);
    expect(find.textContaining('pack'), findsNothing, reason: 'hidden');
    expect(tester.hasRunningAnimations, isFalse, reason: 'no swap animation');
    expect(barriers(tester), 1, reason: 'one barrier for every box');
    expect(confirm, isA<Future<bool?>>());
  });

  testWidgets('popping the top box brings back the one under it, with its '
      'state, and completes the top box with the result', (tester) async {
    await pumpHost(tester);
    final layer = await open<void>(tester, 'pack');
    await tester.tap(find.textContaining('pack'));
    await tester.pump();
    expect(find.text('pack 1'), findsOneWidget);

    final confirm = layerOf(
      tester,
      'pack',
    ).show<bool>((_) => const _Box('confirm'));
    await tester.pump();
    Navigator.pop(boxContext(tester, 'confirm'), true);
    await tester.pump();

    expect(await confirm, isTrue);
    expect(find.text('pack 1'), findsOneWidget, reason: 'same box, same state');
    expect(tester.hasRunningAnimations, isFalse, reason: 'back at once');
    var closed = false;
    layer.whenComplete(() => closed = true).ignore();
    await tester.pump();
    expect(closed, isFalse, reason: 'the layer stays');
  });

  testWidgets('popping the last box closes the layer with its result, the '
      'layer fading out', (tester) async {
    await pumpHost(tester);
    final layer = await open<bool>(tester, 'confirm');

    Navigator.pop(boxContext(tester, 'confirm'), true);
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue, reason: 'the layer fades');
    await tester.pumpAndSettle();

    expect(await layer, isTrue);
    expect(barriers(tester), 0);
  });

  testWidgets('Escape closes the top box only', (tester) async {
    await pumpHost(tester);
    await open<void>(tester, 'pack');
    final confirm = layerOf(
      tester,
      'pack',
    ).show<bool>((_) => const _Box('confirm'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(await confirm, isNull);
    expect(find.textContaining('pack'), findsOneWidget);
    expect(barriers(tester), 1);
  });

  testWidgets('a tap on the barrier closes every box and the layer', (
    tester,
  ) async {
    await pumpHost(tester);
    final layer = await open<void>(tester, 'pack');
    final confirm = layerOf(
      tester,
      'pack',
    ).show<bool>((_) => const _Box('confirm'));
    await tester.pump();

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    // The box that was shown fades out with the layer.
    expect(find.textContaining('confirm'), findsOneWidget);
    await tester.pumpAndSettle();

    expect(await confirm, isNull);
    await layer;
    expect(barriers(tester), 0);
    expect(find.textContaining('pack'), findsNothing);
  });

  testWidgets('closeBox closes a box under the shown one without showing '
      'anything else', (tester) async {
    await pumpHost(tester);
    final layer = await open<String>(tester, 'pack');
    final packContext = boxContext(tester, 'pack');
    layerOf(tester, 'pack').show<void>((_) => const _Box('notice')).ignore();
    await tester.pump();

    ChromeBoxLayer.closeBox(packContext, 'gone');
    await tester.pump();
    expect(find.textContaining('notice'), findsOneWidget);

    Navigator.pop(boxContext(tester, 'notice'));
    await tester.pumpAndSettle();
    expect(barriers(tester), 0, reason: 'the last box took the layer away');
    expect(
      await layer,
      'gone',
      reason: "the layer answers its first box's result",
    );
  });

  testWidgets('closeAll from the shown box closes the layer with that box on '
      'it, answering it with the result and the others with null', (
    tester,
  ) async {
    await pumpHost(tester);
    final layer = await open<void>(tester, 'pack');
    final confirm = layerOf(
      tester,
      'pack',
    ).show<bool>((_) => const _Box('confirm'));
    await tester.pump();

    ChromeBoxLayer.of(boxContext(tester, 'confirm')).closeAll(true);
    await tester.pump();
    expect(find.textContaining('confirm'), findsOneWidget, reason: 'fading');
    expect(find.textContaining('pack'), findsNothing, reason: 'never back');
    await tester.pumpAndSettle();

    expect(await confirm, isTrue);
    await layer;
    expect(barriers(tester), 0);
  });

  testWidgets('maybeOf is null outside a layer', (tester) async {
    await pumpHost(tester);
    expect(ChromeBoxLayer.maybeOf(host), isNull);
    expect(ChromeBoxLayer.isShown(host), isFalse);
  });

  testWidgets('a box is shown until another box covers it, and again once '
      'that one closes', (tester) async {
    await pumpHost(tester);
    await open<void>(tester, 'pack');
    final pack = boxContext(tester, 'pack');
    expect(ChromeBoxLayer.isShown(pack), isTrue);

    ChromeBoxLayer.of(pack).show<void>((_) => const _Box('confirm')).ignore();
    await tester.pump();
    expect(ChromeBoxLayer.isShown(pack), isFalse);
    expect(ChromeBoxLayer.isShown(boxContext(tester, 'confirm')), isTrue);

    Navigator.pop(boxContext(tester, 'confirm'));
    await tester.pump();
    expect(ChromeBoxLayer.isShown(pack), isTrue);
  });

  testWidgets('an overlay covers the whole layer above the box and does not '
      'fade with it', (tester) async {
    await pumpHost(tester);
    const over = Key('over');
    ChromeBoxLayer.open<void>(
      host,
      barrierColor: _barrier,
      transitionDuration: _fade,
      builder: (_) => const _Box('pack'),
      overlay: (context, child) => Stack(
        children: [
          ?child,
          const Positioned.fill(child: SizedBox(key: over)),
        ],
      ),
    ).ignore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      tester.getSize(find.byKey(over)),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    expect(
      find.ancestor(
        of: find.byKey(over),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.textContaining('pack'),
        matching: find.byType(FadeTransition),
      ),
      findsWidgets,
    );
  });
}
