import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/overlay_pause_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

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

  for (final presentation in ChatMessageMenuPresentation.values) {
    testWidgets('a ${presentation.name} message menu leaves the chat playing', (
      tester,
    ) async {
      await pumpHome(tester);
      unawaited(
        ChatMessageMenu.show(
          context: tester.element(find.text('open')),
          messageRect: const Rect.fromLTWH(20, 100, 200, 60),
          presentation: presentation,
          items: const [
            ChatMessageMenuItem(id: 'reply', label: 'Reply', icon: Icons.reply),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(layers(), isEmpty);

      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(layers(), isEmpty);
    });
  }

  // The reference pauses everything while its sticker and emoji sheets move
  // and only what is under them while they are open: their own stickers and
  // the preview opened from them play (ticket 128).
  group('a pack sheet', () {
    for (final arrangement in PanelArrangement.values) {
      testWidgets('(${arrangement.name}) pauses while it moves and plays '
          'while it is open', (tester) async {
        await pumpHome(tester);
        unawaited(
          PackSheet.show(
            tester.element(find.text('open')),
            arrangement: arrangement,
            builder: (_) => const SizedBox(height: 80, child: Text('sheet')),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(layers(), {PlaybackPauseLayer.overlayShown});

        await tester.pumpAndSettle();
        expect(find.text('sheet'), findsOneWidget);
        expect(layers(), isEmpty);

        Navigator.of(tester.element(find.text('sheet'))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(layers(), {PlaybackPauseLayer.overlayShown});

        await tester.pumpAndSettle();
        expect(find.text('sheet'), findsNothing);
        expect(layers(), isEmpty);
      });
    }

    testWidgets('a dialog over an open sheet pauses until it closes', (
      tester,
    ) async {
      await pumpHome(tester);
      unawaited(
        PackSheet.show(
          tester.element(find.text('open')),
          arrangement: PanelArrangement.touch,
          builder: (_) => const SizedBox(height: 80, child: Text('sheet')),
        ),
      );
      await tester.pumpAndSettle();

      unawaited(
        showDialog<void>(
          context: tester.element(find.text('sheet')),
          builder: (_) => const AlertDialog(content: Text('dialog')),
        ),
      );
      await tester.pumpAndSettle();
      expect(layers(), {PlaybackPauseLayer.overlayShown});

      Navigator.of(tester.element(find.text('dialog'))).pop();
      await tester.pumpAndSettle();
      expect(layers(), isEmpty);
    });

    testWidgets('removed without a pop, it gives its claim back', (
      tester,
    ) async {
      await pumpHome(tester);
      unawaited(
        PackSheet.show(
          tester.element(find.text('open')),
          arrangement: PanelArrangement.touch,
          builder: (_) => const SizedBox(height: 80, child: Text('sheet')),
        ),
      );
      await tester.pump();
      expect(layers(), {PlaybackPauseLayer.overlayShown});

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.removeRoute(ModalRoute.of(tester.element(find.text('sheet')))!);
      await tester.pumpAndSettle();

      expect(layers(), isEmpty);
    });
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

  group('a chat opened as a page', () {
    // The chat list pushes the chat itself: it is the page the animations
    // belong to, not something laid over it.
    testWidgets('a route the host names as the chat is not an overlay', (
      tester,
    ) async {
      final chatObserver = PlaybackOverlayPauseObserver(
        activity,
        isChat: (route) => route.settings.name == 'chat',
      );
      addTearDown(chatObserver.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [chatObserver],
          home: const Text('list'),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));

      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'chat'),
            builder: (_) => const Text('chat'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(layers(), isEmpty);
    });

    testWidgets('a dialog over that chat still pauses it', (tester) async {
      final chatObserver = PlaybackOverlayPauseObserver(
        activity,
        isChat: (route) => route.settings.name == 'chat',
      );
      addTearDown(chatObserver.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [chatObserver],
          home: const Text('list'),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'chat'),
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
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(layers(), {PlaybackPauseLayer.overlayShown});
    });

    testWidgets('any other pushed page still pauses it', (tester) async {
      final chatObserver = PlaybackOverlayPauseObserver(
        activity,
        isChat: (route) => route.settings.name == 'chat',
      );
      addTearDown(chatObserver.dispose);
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [chatObserver],
          home: const Text('list'),
        ),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));

      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Text('settings')),
        ),
      );
      await tester.pumpAndSettle();

      expect(layers(), {PlaybackPauseLayer.overlayShown});
    });
  });
}
