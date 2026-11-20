import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' as content;
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../page/pages_rig.dart';

final class _Host extends AttachSheetHost {
  final interactions = <AttachInteraction>[];
  SendSchedule? schedule;
  int scheduleAsks = 0;
  int externals = 0;

  @override
  void interaction(AttachInteraction interaction) =>
      interactions.add(interaction);

  @override
  Future<SendSchedule?> pickSchedule(BuildContext context) async {
    scheduleAsks++;
    return schedule;
  }

  @override
  void openExternalPicker() => externals++;
}

void main() {
  const android = AttachSheetPolicy.android();
  const ios = AttachSheetPolicy.ios();

  Future<(PagesRig, AttachPageScope)> open(
    WidgetTester tester, {
    AttachSheetPolicy policy = android,
    AttachPolicy attachPolicy = const AttachPolicy.android(),
    AttachLimits limits = const AttachLimits(),
    AttachSheetHost host = const AttachSheetHost(),
    content.RichText caption = content.RichText.empty,
    SendOptionStore? store,
  }) async {
    late AttachPageScope scope;
    final rig = await PagesRig.open(
      tester,
      policy: policy,
      attachPolicy: attachPolicy,
      limits: limits,
      host: host,
      initialCaption: caption,
      optionStore: store,
      pages: [
        rowsPage('gallery', onScope: (s) => scope = s),
        rowsPage('files'),
      ],
    );
    return (rig, scope);
  }

  Opacity panel(WidgetTester tester) =>
      tester.widget<Opacity>(find.byKey(const ValueKey('attach-panel')));

  double sendScale(WidgetTester tester) => tester
      .widget<Transform>(find.byKey(const ValueKey('attach-send-reveal')))
      .transform
      .storage[0];

  group('swap', () {
    testWidgets('Android: the panel fades in and Send grows from 0.2 over '
        '180 ms', (tester) async {
      final (rig, _) = await open(tester);
      expect(
        find.byKey(const ValueKey('attach-panel'), skipOffstage: true),
        findsNothing,
      );

      rig.selection.toggle(AttachItems.photo('p'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(panel(tester).opacity, inExclusiveRange(0, 1));
      expect(sendScale(tester), inExclusiveRange(0.2, 1));

      await tester.pumpAndSettle();
      expect(panel(tester).opacity, 1);
      expect(sendScale(tester), 1);

      rig.selection.clear();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('attach-panel'), skipOffstage: true),
        findsNothing,
      );
    });

    testWidgets('iOS: the panel rises 44 and fades in over 0.25 s', (
      tester,
    ) async {
      final (rig, _) = await open(
        tester,
        policy: ios,
        attachPolicy: const AttachPolicy.ios(),
      );
      rig.selection.toggle(AttachItems.photo('p'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      double rise() => tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('attach-panel')),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .getTranslation()
          .y;
      expect(rise(), closeTo(44, 1));
      await tester.pump(const Duration(milliseconds: 125));
      expect(rise(), inExclusiveRange(0, 44));
      await tester.pumpAndSettle();
      expect(rise(), 0);
      expect(sendScale(tester), 1);
    });
  });

  group('counter', () {
    testWidgets('Android shows it at 100 left', (tester) async {
      final (rig, scope) = await open(
        tester,
        limits: const AttachLimits(captionLength: 200),
      );
      rig.selection.toggle(AttachItems.photo('p'));
      scope.panel.caption.restore(content.RichText.plain('a' * 99));
      await tester.pumpAndSettle();
      expect(find.text('101'), findsNothing);
      scope.panel.caption.restore(content.RichText.plain('a' * 100));
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('iOS shows it under 5 left', (tester) async {
      final (rig, scope) = await open(
        tester,
        policy: ios,
        attachPolicy: const AttachPolicy.ios(),
        limits: const AttachLimits(captionLength: 10),
      );
      rig.selection.toggle(AttachItems.photo('p'));
      scope.panel.caption.restore(content.RichText.plain('a' * 5));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsNothing);
      scope.panel.caption.restore(content.RichText.plain('a' * 6));
      await tester.pumpAndSettle();
      expect(find.text('4'), findsOneWidget);
    });
  });

  group('over the limit', () {
    for (final (name, policy, haptic) in [
      ('Android', android, 'HapticFeedbackType.selectionClick'),
      ('iOS', ios, 'HapticFeedbackType.heavyImpact'),
    ]) {
      testWidgets('$name: shakes, plays its haptic, tells the host, sends '
          'nothing', (tester) async {
        final haptics = <Object?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final host = _Host();
        final (rig, _) = await open(
          tester,
          policy: policy,
          host: host,
          limits: const AttachLimits(captionLength: 5),
          caption: const content.RichText.plain('abcdefg'),
        );
        rig.selection.toggle(AttachItems.photo('p'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('attach-send')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final field = tester.widget<Transform>(
          find.byKey(const ValueKey('attach-caption-shake')),
        );
        expect(field.transform.getTranslation().x, isNot(0));
        await tester.pumpAndSettle();

        expect(rig.outcome, isNull);
        expect(host.interactions, [
          const AttachInteraction.captionTooLong(over: 2),
        ]);
        expect(haptics, [haptic]);
      });
    }
  });

  group('send', () {
    testWidgets('Send hands the host a request with the caption', (
      tester,
    ) async {
      final (rig, scope) = await open(
        tester,
        caption: const content.RichText.plain('hello'),
      );
      final photo = AttachItems.photo('p');
      rig.selection.toggle(photo);
      await tester.pumpAndSettle();
      expect(
        scope.panel.caption.richText,
        const content.RichText.plain('hello'),
      );

      await tester.tap(find.byKey(const ValueKey('attach-send')));
      await tester.pumpAndSettle();

      final outcome = rig.outcome! as AttachOutcome$Send;
      expect(outcome.request.items, [photo]);
      expect(outcome.request.caption, const content.RichText.plain('hello'));
      expect(outcome.request.options, const SendOptions());
    });

    testWidgets('a cancel returns the caption', (tester) async {
      final (rig, _) = await open(
        tester,
        caption: const content.RichText.plain('draft'),
      );
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      expect(
        rig.outcome,
        const AttachOutcome.cancelled(content.RichText.plain('draft')),
      );
    });

    testWidgets('a discard returns the caption as it was edited', (
      tester,
    ) async {
      final (rig, scope) = await open(
        tester,
        caption: const content.RichText.plain('draft'),
      );
      rig.selection.toggle(AttachItems.photo('p'));
      scope.panel.caption.restore(const content.RichText.plain('draft 2'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(
        rig.outcome,
        const AttachOutcome.cancelled(content.RichText.plain('draft 2')),
      );
    });
  });

  group('send menu', () {
    Future<void> longPressSend(WidgetTester tester) async {
      await tester.longPress(find.byKey(const ValueKey('attach-send')));
      await tester.pumpAndSettle();
    }

    Finder entry(String id) => find.byKey(ValueKey('attach-menu-send-$id'));

    testWidgets('Android: without sound and schedule; caption above with a '
        'caption', (tester) async {
      final (rig, scope) = await open(tester);
      rig.selection.toggle(AttachItems.photo('p'));
      await tester.pumpAndSettle();
      expect(scope.panel.sendMenu, [
        AttachSendMenuItem.silent,
        AttachSendMenuItem.schedule,
      ]);
      scope.panel.caption.restore(const content.RichText.plain('x'));
      expect(scope.panel.sendMenu, [
        AttachSendMenuItem.silent,
        AttachSendMenuItem.schedule,
        AttachSendMenuItem.captionAbove,
      ]);
    });

    testWidgets('iOS adds when online', (tester) async {
      final (rig, scope) = await open(
        tester,
        policy: ios,
        attachPolicy: const AttachPolicy.ios(),
      );
      rig.selection.toggle(AttachItems.photo('p'));
      expect(scope.panel.sendMenu, [
        AttachSendMenuItem.silent,
        AttachSendMenuItem.schedule,
        AttachSendMenuItem.whenOnline,
      ]);
    });

    testWidgets('a timer hides scheduling', (tester) async {
      final (rig, scope) = await open(
        tester,
        policy: ios,
        attachPolicy: const AttachPolicy.ios(),
      );
      rig.selection.toggle(
        AttachItems.photo('t', timer: const AttachTimer.once()),
      );
      expect(scope.panel.sendMenu, [AttachSendMenuItem.silent]);
    });

    testWidgets('no schedule right hides scheduling', (tester) async {
      final (rig, scope) = await open(
        tester,
        limits: const AttachLimits(scheduleAllowed: false),
      );
      rig.selection.toggle(AttachItems.photo('p'));
      expect(scope.panel.sendMenu, [AttachSendMenuItem.silent]);
    });

    testWidgets('Schedule asks the host and sends at its time', (tester) async {
      final host = _Host()..schedule = SendSchedule.at(DateTime(2030));
      final (rig, _) = await open(tester, host: host);
      rig.selection.toggle(AttachItems.photo('p'));
      await tester.pumpAndSettle();

      await longPressSend(tester);
      await tester.tap(entry('schedule'));
      await tester.pumpAndSettle();

      expect(host.scheduleAsks, 1);
      final outcome = rig.outcome! as AttachOutcome$Send;
      expect(outcome.request.options.schedule, SendSchedule.at(DateTime(2030)));
    });

    testWidgets('a cancelled schedule sends nothing', (tester) async {
      final host = _Host();
      final (rig, _) = await open(tester, host: host);
      rig.selection.toggle(AttachItems.photo('p'));
      await tester.pumpAndSettle();
      await longPressSend(tester);
      await tester.tap(entry('schedule'));
      await tester.pumpAndSettle();
      expect(rig.outcome, isNull);
    });

    testWidgets('Without sound sends silently', (tester) async {
      final (rig, _) = await open(tester);
      rig.selection.toggle(AttachItems.photo('p'));
      await tester.pumpAndSettle();
      await longPressSend(tester);
      await tester.tap(entry('silent'));
      await tester.pumpAndSettle();
      expect((rig.outcome! as AttachOutcome$Send).request.options.silent, true);
    });
  });

  group('overflow', () {
    testWidgets('Android entries follow the selection', (tester) async {
      final (rig, scope) = await open(tester);
      final send = scope.panel;
      expect(send.overflow, [AttachOverflowItem.openExternal]);

      rig.selection.toggle(AttachItems.photo('p'));
      expect(send.overflow, [
        AttachOverflowItem.sendAsFiles,
        AttachOverflowItem.spoiler,
        AttachOverflowItem.quality,
      ]);

      rig.selection.toggle(AttachItems.photo('q'));
      send.caption.restore(const content.RichText.plain('x'));
      expect(send.overflow, [
        AttachOverflowItem.sendAsFiles,
        AttachOverflowItem.withoutGrouping,
        AttachOverflowItem.spoiler,
        AttachOverflowItem.quality,
        AttachOverflowItem.captionAbove,
      ]);

      rig.selection.toggle(AttachItems.file('f'));
      expect(send.overflow, [
        AttachOverflowItem.sendAsFiles,
        AttachOverflowItem.withoutGrouping,
        AttachOverflowItem.spoiler,
      ]);
    });

    testWidgets('iOS entries; send as file hides under a spoiler', (
      tester,
    ) async {
      final (rig, scope) = await open(
        tester,
        policy: ios,
        attachPolicy: const AttachPolicy.ios(),
      );
      final send = scope.panel;
      expect(send.overflow, isEmpty);
      rig.selection.toggle(AttachItems.photo('p'));
      expect(send.overflow, [
        AttachOverflowItem.sendAsFiles,
        AttachOverflowItem.highQuality,
        AttachOverflowItem.spoiler,
      ]);
      send.runOverflow(AttachOverflowItem.spoiler);
      expect(rig.selection.items.single.spoiler, isTrue);
      expect(send.overflow, [
        AttachOverflowItem.highQuality,
        AttachOverflowItem.spoiler,
      ]);
    });

    testWidgets('open in an external app goes to the host', (tester) async {
      final host = _Host();
      final (_, scope) = await open(tester, host: host);
      scope.panel.runOverflow(AttachOverflowItem.openExternal);
      expect(host.externals, 1);
    });

    testWidgets('the overflow button shows the entries and runs them', (
      tester,
    ) async {
      final (rig, scope) = await open(tester);
      rig.selection.toggle(AttachItems.photo('p'));
      rig.selection.toggle(AttachItems.photo('q'));
      scope.headerItems = AttachOverflowButton(controller: scope.panel);
      scope.requestExpansion();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('attach-overflow')));
      await tester.pumpAndSettle();
      expect(find.text('Send as files'), findsOneWidget);
      // The menu is a route of its own: it carries the chrome text root.
      expectChromeText(tester);
      await tester.tap(find.text('Send without grouping'));
      await tester.pumpAndSettle();

      final outcome = rig.outcome! as AttachOutcome$Send;
      expect(outcome.request.options.grouped, isFalse);
    });
  });

  group('options store', () {
    testWidgets('iOS restores high quality on open', (tester) async {
      final storage = FakeKeyValueStore();
      await storage.write(
        SendOptionStore.namespace,
        'high_quality',
        const content.StoredValue('true', version: 1),
      );
      final (_, scope) = await open(
        tester,
        policy: ios,
        attachPolicy: const AttachPolicy.ios(),
        store: SendOptionStore(storage, policy: const AttachPolicy.ios()),
      );
      await tester.pump();
      expect(scope.panel.options.value.highQuality, isTrue);
    });

    testWidgets('Android remembers the quality switch', (tester) async {
      final storage = FakeKeyValueStore();
      final (rig, scope) = await open(
        tester,
        store: SendOptionStore(storage, policy: const AttachPolicy.android()),
      );
      rig.selection.toggle(AttachItems.photo('p'));
      scope.panel.runOverflow(AttachOverflowItem.quality);
      await tester.pump();
      expect(
        storage.entries['attach_model:high_quality'],
        const content.StoredValue('true', version: 1),
      );
    });
  });

  testWidgets('iOS: focusing the caption expands the sheet', (tester) async {
    final (rig, _) = await open(
      tester,
      policy: ios,
      attachPolicy: const AttachPolicy.ios(),
    );
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attach-caption')));
    await tester.pumpAndSettle();
    expect(rig.top, 24);
  });

  testWidgets('iOS: the count bumps to 1.2 when it grows', (tester) async {
    final (rig, _) = await open(
      tester,
      policy: ios,
      attachPolicy: const AttachPolicy.ios(),
    );
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    rig.selection.toggle(AttachItems.photo('q'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final badge = tester.widget<Transform>(
      find.byKey(const ValueKey('attach-send-bounce')),
    );
    expect(badge.transform.storage[0], closeTo(1.2, 0.02));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });
}
