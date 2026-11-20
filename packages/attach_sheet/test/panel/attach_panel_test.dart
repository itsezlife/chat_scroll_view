import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' as content;
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../page/pages_rig.dart';

/// A host whose caption has a panel: a box that types an emoji.
final class _PanelHost extends AttachSheetHost {
  @override
  Widget? buildCaptionPanel(BuildContext context, ComposerController caption) =>
      GestureDetector(
        key: const ValueKey('emoji-page'),
        onTap: () => caption.insertText('🙂'),
        child: const ColoredBox(color: Color(0xFF123456)),
      );
}

/// A host whose caption draws inline content: its builder counts the spans
/// it is asked for.
final class _InlineHost extends AttachSheetHost {
  final drawn = <String>[];

  @override
  ComposerTextController? createCaptionText() => ComposerTextController(
    inlineContentBuilder: (context, reference, style) {
      drawn.add(reference.alternativeText);
      return WidgetSpan(
        child: SizedBox(
          key: ValueKey('inline-${reference.alternativeText}'),
          width: 20,
          height: 20,
        ),
      );
    },
  );
}

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
    double safeBottom = 0,
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
      // A safe area under the screen (a gesture bar), which a raised
      // keyboard covers.
      wrap: safeBottom == 0
          ? null
          : (app) => Builder(
              builder: (context) {
                final media = MediaQuery.of(context);
                final keyboard = media.viewInsets.bottom;
                return MediaQuery(
                  data: media.copyWith(
                    padding: media.padding.copyWith(bottom: safeBottom),
                    viewPadding: media.viewPadding.copyWith(
                      bottom: safeBottom + keyboard,
                    ),
                  ),
                  child: app,
                );
              },
            ),
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

  testWidgets('the count: the fill with a ring of the sheet background, '
      'white bold 12, on the button top-start corner, rolling to a new '
      'value', (tester) async {
    final (rig, _) = await open(tester);
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    final badge = find.byKey(const ValueKey('attach-send-count'));
    final button = tester.getRect(find.byKey(const ValueKey('attach-send')));
    final rect = tester.getRect(badge);
    // max(9 + the count's width, 18), and the ring on both sides; the test
    // face draws a digit 12 wide.
    expect(rect.height, 18 + 4);
    expect(rect.width, 9 + 12 + 4);
    expect(rect.top, button.top);
    expect(rect.center.dx, closeTo(button.left, 0.5));

    final context = tester.element(badge);
    final palette = ChromeThemeScope.paletteOf(context);
    final tokens = ChromeThemeScope.attachOf(context);
    final decoration =
        tester.widget<Container>(badge).decoration! as BoxDecoration;
    expect(decoration.color, palette.accent);
    expect((decoration.border! as Border).top.color, tokens.background);
    expect((decoration.border! as Border).top.width, 2);
    final text = tester.widget<Text>(
      find.descendant(of: badge, matching: find.text('1')),
    );
    expect(text.style!.fontSize, 12);
    expect(text.style!.fontWeight, FontWeight.w700);
    expect(text.style!.color, palette.onAccent);

    rig.selection.toggle(AttachItems.photo('q'));
    await tester.pump();
    // The roll: 320 ms on an ease out quint; the old digit drops 0.3 of the
    // text size and fades, the new one drops in from that far above.
    double dyOf(String digit) => tester
        .widget<Positioned>(
          find
              .ancestor(
                of: find.descendant(of: badge, matching: find.text(digit)),
                matching: find.byType(Positioned),
              )
              .first,
        )
        .top!;
    double opacityOf(String digit) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.descendant(of: badge, matching: find.text(digit)),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    await tester.pump(const Duration(milliseconds: 40));
    final t = Curves.easeOutQuint.transform(40 / 320);
    expect(dyOf('1'), closeTo(12 * 0.3 * t, 0.01));
    expect(opacityOf('1'), closeTo(1 - t, 0.01));
    expect(dyOf('2'), closeTo(-12 * 0.3 * (1 - t), 0.01));
    expect(opacityOf('2'), closeTo(t, 0.01));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: badge, matching: find.text('1')), findsNothing);
    expect(dyOf('2'), 0);
    await tester.pumpAndSettle();

    // 9 to 10: the badge widens with the text through the roll.
    for (var i = 0; i < 7; i++) {
      rig.selection.toggle(AttachItems.photo('r$i'));
    }
    await tester.pumpAndSettle();
    final nine = tester.getSize(badge).width;
    rig.selection.toggle(AttachItems.photo('x'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final mid = tester.getSize(badge).width;
    await tester.pumpAndSettle();
    final ten = tester.getSize(badge).width;
    expect(mid, greaterThan(nine));
    expect(mid, lessThan(ten));

    // Emptied, it rolls away to nothing, shrinking with the text.
    rig.selection.clear();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final scale = tester.widget<Transform>(
      find.byKey(const ValueKey('attach-send-bounce')),
    );
    expect(scale.transform.storage[0], closeTo(1 - t, 0.02));
    expectChromeText(tester, within: badge);
    await tester.pumpAndSettle();
    expect(badge, findsNothing);
  });

  testWidgets("the caption is the chat's composer island floating over the "
      "page in the sheet's bottom fade, Send beside it", (tester) async {
    final (rig, _) = await open(tester);
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('attach-panel'));
    expect(
      find.descendant(of: panel, matching: find.byType(ComposerView)),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('attach-bottom-fade')), findsOneWidget);
    expect(find.text('Add a caption…'), findsOneWidget);
    final island = tester.getRect(
      find.descendant(of: panel, matching: find.byType(ComposerView)),
    );
    final send = tester.getRect(find.byKey(const ValueKey('attach-send')));
    expect(send.left, greaterThanOrEqualTo(island.right));
    // With no button leading it the hint keeps off the pill's round start.
    final hint = tester.getRect(find.text('Add a caption…'));
    expect(
      hint.left - island.left,
      greaterThanOrEqualTo(AttachCaptionBar.fieldStartInset),
    );
    expectChromeText(tester, within: panel);
  });

  testWidgets('a close takes the keyboard down: the caption lets go of '
      'focus as the sheet closes on a send', (tester) async {
    final (rig, scope) = await open(tester);
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    scope.panel.caption.focusNode.requestFocus();
    await tester.pump();
    expect(scope.panel.caption.focusNode.hasFocus, isTrue);

    await tester.tap(find.byKey(const ValueKey('attach-send')));
    await tester.pump();
    expect(scope.panel.caption.focusNode.hasFocus, isFalse);
    await tester.pumpAndSettle();
    expect(rig.outcome, isA<AttachOutcome$Send>());
  });

  testWidgets('99 to 100: the badge grows as a pill through the roll and '
      'the count never leaves it', (tester) async {
    final (rig, _) = await open(tester);
    for (var i = 0; i < 99; i++) {
      rig.selection.toggle(AttachItems.photo('p$i'));
    }
    await tester.pumpAndSettle();
    final badge = find.byKey(const ValueKey('attach-send-count'));
    final at99 = tester.getRect(badge);
    expect(at99.height, 22);

    rig.selection.toggle(AttachItems.photo('p99'));
    await tester.pump();
    for (final ms in [20, 60, 120, 320]) {
      await tester.pump(Duration(milliseconds: ms == 20 ? 20 : ms - 20));
      final rect = tester.getRect(badge);
      expect(
        tester.getSize(badge).height,
        22,
        reason: 'a pill: the height holds ($ms ms)',
      );
      // The text is drawn clipped to its box, and the box sits inside the
      // badge at every frame.
      final text = tester.getRect(
        find.descendant(of: badge, matching: find.byType(ClipRect)),
      );
      expect(text.left, greaterThanOrEqualTo(rect.left - 0.01), reason: '$ms');
      expect(text.right, lessThanOrEqualTo(rect.right + 0.01), reason: '$ms');
    }
    await tester.pumpAndSettle();
    final at100 = tester.getSize(badge);
    // max(9 + text, 18) and the ring: three digits of the test face, 12 each.
    expect(at100.width, 9 + 36 + 4);
    expect(at100.width, greaterThan(at99.width));
  });

  testWidgets("the bottom fade: the sheet's background ramping in over 48 "
      'above the safe area, under the tab bar and under the caption; it '
      'drops away at the top with no bar up', (tester) async {
    final (rig, scope) = await open(tester);
    final fade = find.byKey(const ValueKey('attach-bottom-fade'));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(tester.getRect(fade).bottom, closeTo(screen.height, 0.5));
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: fade, matching: find.byType(DecoratedBox)),
    );
    final gradient =
        (box.decoration as BoxDecoration).gradient! as LinearGradient;
    final background = ChromeThemeScope.attachOf(
      tester.element(fade),
    ).background;
    expect(gradient.colors.first.a, 0);
    expect(gradient.colors.last, background);

    scope.requestExpansion();
    await tester.pumpAndSettle();
    expect(
      tester.getRect(fade).top,
      closeTo(screen.height, 0.5),
      reason: 'dropped 48: no bar at the top',
    );

    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    expect(tester.getRect(fade).bottom, closeTo(screen.height, 0.5));
  });

  testWidgets('Android: the caption raising the keyboard takes the sheet to '
      'its top, and the caption bar stands on the keyboard', (tester) async {
    final (rig, scope) = await open(tester);
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    expect(rig.top, greaterThan(24));

    scope.panel.caption.focusNode.requestFocus();
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(rig.top, 24, reason: 'expanded');
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bar = tester.getRect(find.byKey(const ValueKey('attach-sheet-bar')));
    expect(bar.bottom, closeTo(screen.height - 300, 0.5));
    final send = tester.getRect(find.byKey(const ValueKey('attach-send')));
    expect(send.bottom, lessThanOrEqualTo(screen.height - 300));
  });

  testWidgets("the caption's emoji button puts its panel in the keyboard's "
      'place at its height, the field keeping focus; the button again brings '
      'the keyboard back; back closes the panel before the sheet', (
    tester,
  ) async {
    final (rig, scope) = await open(tester, host: _PanelHost());
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    final english = ChromeStringsPresets.english.composer;
    final caption = scope.panel.caption;

    // The keyboard is up for the caption first.
    caption.focusNode.requestFocus();
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel(english.showPanelAction));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('attach-caption-panel-slot'));
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).height, 300, reason: "the keyboard's height");
    expect(caption.focusNode.hasFocus, isTrue);
    expect(caption.softKeyboard.value, SoftKeyboardMode.suppressed);
    await tester.tap(find.byKey(const ValueKey('emoji-page')));
    await tester.pump();
    expect(caption.richText.plain, '🙂');

    await tester.tap(find.bySemanticsLabel(english.showKeyboardAction));
    await tester.pumpAndSettle();
    expect(caption.softKeyboard.value, SoftKeyboardMode.auto);
    // Handed to the keyboard: the place stays, shrinking as it rises, so
    // the bar does not jump.
    expect(tester.getSize(panel).height, 300);
    tester.view.viewInsets = FakeViewPadding(
      bottom: 120 * tester.view.devicePixelRatio,
    );
    await tester.pump();
    expect(tester.getSize(panel).height, 180);
    tester.view.viewInsets = FakeViewPadding(
      bottom: 300 * tester.view.devicePixelRatio,
    );
    await tester.pumpAndSettle();
    expect(panel, findsNothing);

    // Opened over the keyboard it takes its place at once.
    await tester.tap(find.bySemanticsLabel(english.showPanelAction));
    await tester.pump();
    expect(tester.getSize(panel).height, 300);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();

    // Back: the panel first, sliding down; the sheet stays.
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getSize(panel).height, inExclusiveRange(0, 300));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(rig.outcome, isNull);
    expectChromeText(tester, within: find.byType(AttachSheet));
  });

  testWidgets("custom content in the caption is drawn by the host's builder, "
      'as in the chat composer', (tester) async {
    final host = _InlineHost();
    final (rig, scope) = await open(tester, host: host);
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    scope.panel.caption.insertContent(
      const content.InlineContentRef(
        key: content.ContentKey.document('party'),
        alternativeText: '★',
      ),
    );
    await tester.pumpAndSettle();
    expect(host.drawn, contains('★'));
    expect(find.byKey(const ValueKey('inline-★')), findsOneWidget);
  });

  testWidgets("the panel takes the keyboard's full height, not the inset of "
      'a keyboard on its way down', (tester) async {
    final (rig, scope) = await open(tester, host: _PanelHost());
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    final english = ChromeStringsPresets.english.composer;
    scope.panel.caption.focusNode.requestFocus();
    final dpr = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetViewInsets);
    // Up: rising to 358.
    for (final inset in [40.0, 200.0, 358.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset * dpr);
      await tester.pump();
    }
    // Going down as the button is pressed: 4.6 left.
    for (final inset in [200.0, 4.6]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset * dpr);
      await tester.pump();
    }
    await tester.tap(find.bySemanticsLabel(english.showPanelAction));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('attach-caption-panel-slot'))),
      const Size(400, 358),
    );
  });

  testWidgets('the caption stands on the keyboard and on the panel at the '
      'same place: a raised keyboard covers the safe area, so the swap does '
      'not move the bar', (tester) async {
    final (rig, scope) = await open(tester, host: _PanelHost(), safeBottom: 34);
    rig.selection.toggle(AttachItems.photo('p'));
    final dpr = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final english = ChromeStringsPresets.english.composer;
    scope.panel.caption.focusNode.requestFocus();
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * dpr);
    await tester.pumpAndSettle();
    final screen = tester.view.physicalSize / dpr;
    final island = find.byKey(const ValueKey('attach-caption'));
    final onKeyboard = tester.getRect(island).bottom;

    await tester.tap(find.bySemanticsLabel(english.showPanelAction));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.getRect(island).bottom, closeTo(onKeyboard, 0.5));
    expect(
      tester
          .getRect(find.byKey(const ValueKey('attach-caption-panel-slot')))
          .top,
      closeTo(screen.height - 300, 0.5),
    );
  });

  testWidgets('a tap on the caption while its panel is up brings the '
      'keyboard back in its place; after the panel closed with back, a tap '
      'asks for the keyboard again', (tester) async {
    final (rig, scope) = await open(tester, host: _PanelHost());
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    final english = ChromeStringsPresets.english.composer;
    final caption = scope.panel.caption;
    await tester.tap(find.bySemanticsLabel(english.showPanelAction));
    await tester.pumpAndSettle();
    expect(scope.panel.captionPanelShown.value, isTrue);

    await tester.tap(find.byKey(const ValueKey('attach-caption')));
    await tester.pump();
    expect(scope.panel.captionPanelShown.value, isFalse);
    expect(caption.softKeyboard.value, SoftKeyboardMode.auto);
    expect(caption.focusNode.hasFocus, isTrue);

    // Panel again, closed with back: the field stays focused, attached with
    // no keyboard; a tap asks for one.
    await tester.tap(find.bySemanticsLabel(english.showPanelAction));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    var requests = 0;
    void count() => requests++;
    caption.keyboardRequests.addListener(count);
    addTearDown(() => caption.keyboardRequests.removeListener(count));
    await tester.tap(find.byKey(const ValueKey('attach-caption')));
    await tester.pump();
    expect(requests, 1);
  });

  testWidgets("the caption's handle goes down when its panel takes the "
      "keyboard's place and with each pick the panel types", (tester) async {
    final (rig, scope) = await open(tester, host: _PanelHost());
    rig.selection.toggle(AttachItems.photo('p'));
    await tester.pumpAndSettle();
    final caption = scope.panel.caption;
    var hides = 0;
    void count() => hides++;
    caption.selectionUiHides.addListener(count);
    addTearDown(() => caption.selectionUiHides.removeListener(count));
    await tester.tap(
      find.bySemanticsLabel(
        ChromeStringsPresets.english.composer.showPanelAction,
      ),
    );
    await tester.pumpAndSettle();
    expect(hides, 1);
    await tester.tap(find.byKey(const ValueKey('emoji-page')));
    await tester.pump();
    expect(hides, 2);
  });
}
