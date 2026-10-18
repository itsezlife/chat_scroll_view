import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/app/overlay_pause_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PlaybackClock clock;
  late PlaybackActivity activity;
  late PlaybackOverlayPauseObserver observer;

  setUp(() {
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    activity = PlaybackActivity(clock: clock);
    observer = PlaybackOverlayPauseObserver(activity);
  });
  tearDown(() {
    observer.dispose();
    activity.dispose();
    clock.dispose();
  });

  Future<void> pumpHome(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(content: Text('dialog')),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  Set<PlaybackPauseLayer> layers() => clock.pausedLayers;

  testWidgets('the first route, the chat itself, is not an overlay', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(layers(), isEmpty);
  });

  testWidgets('a dialog over the chat pauses it until the dialog closes', (
    tester,
  ) async {
    await pumpHome(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(layers(), {PlaybackPauseLayer.overlayShown});

    Navigator.of(tester.element(find.text('dialog'))).pop();
    await tester.pumpAndSettle();
    expect(layers(), isEmpty);
  });

  testWidgets('a sheet over a dialog keeps the pause until both are gone', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('dialog'));

    unawaited(
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => const SizedBox(height: 80, child: Text('sheet')),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('sheet'))).pop();
    await tester.pumpAndSettle();
    expect(layers(), {PlaybackPauseLayer.overlayShown});

    Navigator.of(tester.element(find.text('dialog'))).pop();
    await tester.pumpAndSettle();
    expect(layers(), isEmpty);
  });

  testWidgets('a full-screen route over the chat pauses it too', (
    tester,
  ) async {
    await pumpHome(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('settings')),
      ),
    );
    await tester.pumpAndSettle();
    expect(layers(), {PlaybackPauseLayer.overlayShown});

    navigator.pop();
    await tester.pumpAndSettle();
    expect(layers(), isEmpty);
  });

  testWidgets('a route removed without a pop gives its claim back', (
    tester,
  ) async {
    await pumpHome(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final route = MaterialPageRoute<void>(builder: (_) => const Text('x'));
    unawaited(navigator.push(route));
    await tester.pumpAndSettle();

    navigator.removeRoute(route);
    await tester.pumpAndSettle();

    expect(layers(), isEmpty);
  });

  testWidgets('a route replaced by another stays one claim', (tester) async {
    await pumpHome(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Text('a'))),
    );
    await tester.pumpAndSettle();

    unawaited(
      navigator.pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const Text('b')),
      ),
    );
    await tester.pumpAndSettle();
    expect(layers(), {PlaybackPauseLayer.overlayShown});

    navigator.pop();
    await tester.pumpAndSettle();
    expect(layers(), isEmpty);
  });

  testWidgets('disposing the observer releases what is still open', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    observer.dispose();

    expect(layers(), isEmpty);
  });
}
