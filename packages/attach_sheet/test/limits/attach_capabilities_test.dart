/// The picker under a chat's capabilities: denied kinds per platform,
/// one-send mode under a slow mode, a kind denied mid-pick.
///
/// **Seam:** `AttachSheet.show` (through the pages rig) and
/// `ConfirmBoxController` given an `AttachCapabilities`, observed through
/// what the pages draw, the selection, the outcome, the host's feedback
/// (`RecordingCapabilityFeedback`, the host's interactions) and the
/// diagnostics events.
library;

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' as content;
import 'package:content_model/content_model.dart' show ChatEventLevel;
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart' hide MediaKind;
import 'package:mpx_core/testing.dart' hide RecordingDiagnostics;
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';
import 'package:mpx_ui/mpx_ui.dart';

import '../page/pages_rig.dart';

final class _Host extends AttachSheetHost {
  final interactions = <AttachInteraction>[];

  @override
  void interaction(AttachInteraction interaction) =>
      interactions.add(interaction);
}

MediaKey _key(int index) =>
    LibraryKeys.libraryKeyOf(FakeMediaLibrary.assetAt(index));

IntakeFile _file(String name, {String? mime}) => IntakeFile(
  source: IntakeSource.path('/files/$name'),
  name: name,
  size: 900,
  mimeType: mime,
);

SendingCapabilities _denying(List<MediaKind> kinds) => SendingCapabilities(
  media: SendableMedia(
    allowed: MediaKindSet.all.without(MediaKindSet.of(kinds)),
  ),
);

const _slow = SlowMode$Active(interval: Duration(seconds: 30));

void main() {
  late FakeMediaLibrary library;
  late FakeFileIntake intake;
  late PlaybackClock clock;
  late AssetCacheScope scope;
  late FakeChatCapabilitiesSource source;
  late RecordingCapabilityFeedback feedback;
  late RecordingDiagnostics diagnostics;
  late _Host host;

  setUp(() {
    library = FakeMediaLibrary(assets: 40);
    intake = FakeFileIntake();
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    scope = AssetCacheScope(producer: FakeAssetProducer(), clock: clock);
    source = FakeChatCapabilitiesSource();
    feedback = RecordingCapabilityFeedback(
      texts: const {
        CapabilityAction.sendPhoto: 'No photos here',
        CapabilityAction.sendFile: 'No files here',
      },
    );
    diagnostics = RecordingDiagnostics.install();
    host = _Host();
  });
  tearDown(() async {
    scope.dispose();
    clock.dispose();
    await library.dispose();
  });

  AttachCapabilities capabilities() => AttachCapabilities(
    capabilities: source,
    chatId: 'c1',
    feedback: feedback,
  );

  Future<PagesRig> open(
    WidgetTester tester, {
    AttachSheetPolicy policy = const AttachSheetPolicy.android(),
    AttachPolicy attachPolicy = const AttachPolicy.android(),
    AttachPageId initial = AttachPageId.gallery,
    bool withCapabilities = true,
    TextDirection? direction,
  }) async {
    final rig = await PagesRig.open(
      tester,
      policy: policy,
      attachPolicy: attachPolicy,
      host: host,
      initial: initial,
      capabilities: withCapabilities ? capabilities() : null,
      wrap: (app) => AssetCacheProvider(
        scope: scope,
        child: switch (direction) {
          final direction? => Directionality(
            textDirection: direction,
            child: app,
          ),
          null => app,
        },
      ),
      pages: [
        GalleryPage.create(
          library: library,
          label: 'Gallery',
          icon: const SizedBox(width: 24, height: 24),
        ),
        FilesPage.create(
          intake: intake,
          label: 'File',
          icon: const SizedBox(width: 24, height: 24),
        ),
      ],
    );
    await tester.pumpAndSettle();
    return rig;
  }

  Finder cell(int index) => find.byKey(ValueKey<MediaKey>(_key(index)));

  Future<void> tapCheck(WidgetTester tester, int index) async {
    await tester.tapAt(tester.getTopRight(cell(index)) + const Offset(-10, 10));
    await tester.pump();
  }

  AttachSendController panel(WidgetTester tester) =>
      tester.widget<GalleryView>(find.byType(GalleryView)).panel;

  AttachItem photoItem(int index) =>
      AttachPickerSelection.itemOf(FakeMediaLibrary.assetAt(index));

  const deniedText = ValueKey('attach-denied-text');

  group('gallery', () {
    testWidgets('Android: photos and videos denied show a page with the '
        'denial text in place of the grid', (tester) async {
      source.update(sending: _denying([MediaKind.photo, MediaKind.video]));
      await open(tester);

      expect(find.byKey(const ValueKey('attach-gallery-denied')), findsOne);
      expect(find.byType(LibraryGridCell), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(deniedText)).data,
        'No photos here',
      );
      expectChromeText(
        tester,
        within: find.byKey(const ValueKey('attach-gallery-denied')),
      );
    });

    testWidgets('the denied page is one focusable text node', (tester) async {
      final semantics = tester.ensureSemantics();
      source.update(sending: _denying([MediaKind.photo, MediaKind.video]));
      await open(tester);

      expect(
        tester.getSemantics(find.byKey(deniedText)),
        isSemantics(label: 'No photos here', isFocusable: true),
      );
      semantics.dispose();
    });

    testWidgets('the denied page mirrors in a right-to-left chat', (
      tester,
    ) async {
      source.update(sending: _denying([MediaKind.photo, MediaKind.video]));
      await open(tester, direction: TextDirection.rtl);

      final text = tester.getRect(find.byKey(deniedText));
      expect(text.right, closeTo(400 - 16, 1), reason: 'starts on the right');
    });

    testWidgets('iOS: photos and videos denied keep the grid, no item '
        'selectable, and a burst of taps reports once', (tester) async {
      source.update(sending: _denying([MediaKind.photo, MediaKind.video]));
      final rig = await open(
        tester,
        policy: const AttachSheetPolicy.ios(),
        attachPolicy: const AttachPolicy.ios(),
      );

      expect(find.byKey(const ValueKey('attach-gallery-denied')), findsNothing);
      expect(tester.widget<LibraryGridCell>(cell(0)).dimmed, isTrue);
      expect(tester.widget<LibraryGridCell>(cell(3)).dimmed, isTrue);

      for (var i = 0; i < 5; i++) {
        await tapCheck(tester, 0);
      }
      expect(rig.selection.isEmpty, isTrue);
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendPhoto,
          reason: const DenialReason.everyone(),
        ),
      ]);
      expect(host.interactions, isEmpty, reason: 'onDenied, not a refusal');
      // Every tap is logged; the repeats skip the host.
      final burst = diagnostics.whereOp(CapabilitiesOp.denied);
      expect(burst, hasLength(5));
      expect(
        burst.skip(1).map((e) => e.fields['repeated']),
        everyElement(isTrue),
      );
      final denied = burst.first;
      expect(denied.fields, {
        'action': CapabilityAction.sendPhoto,
        'reason': 'everyone',
        'consumer': CapabilityConsumer.picker,
      });
      expect(denied.correlation.chatId, 'c1');

      await tester.pump(AttachCapabilityGate.deniedGuard);
      await tapCheck(tester, 0);
      expect(feedback.denials, hasLength(2), reason: 'past the guard window');
      await tester.pumpAndSettle();
    });

    testWidgets('one kind denied keeps the grid on Android; only that kind '
        'is not selectable', (tester) async {
      source.update(sending: _denying([MediaKind.video]));
      final rig = await open(tester);

      expect(tester.widget<LibraryGridCell>(cell(3)).dimmed, isTrue);
      expect(tester.widget<LibraryGridCell>(cell(0)).dimmed, isFalse);
      await tapCheck(tester, 0);
      expect(rig.selection.length, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('a change while open swaps the page on the next value', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(LibraryGridCell), findsWidgets);

      source.update(sending: _denying([MediaKind.photo, MediaKind.video]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-gallery-denied')), findsOne);

      source.update(sending: const SendingCapabilities());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attach-gallery-denied')), findsNothing);
      expect(find.byType(LibraryGridCell), findsWidgets);
    });
  });

  group('a kind denied mid-pick', () {
    testWidgets('the picks stay selected and marked, the send is refused '
        'through onDenied with the picker open and the caption kept', (
      tester,
    ) async {
      final rig = await open(tester);
      await tapCheck(tester, 0);
      await tapCheck(tester, 3);
      await tester.pumpAndSettle();
      final controller = panel(tester);
      controller.caption.restore(const content.RichText.plain('look'));

      source.update(sending: _denying([MediaKind.photo]));
      await tester.pumpAndSettle();

      expect(rig.selection.length, 2, reason: 'nothing is dropped');
      final photo = photoItem(0);
      expect(
        find.byKey(ValueKey('attach-gallery-denied-${photo.id}')),
        findsOne,
      );
      expect(
        find.byKey(ValueKey('attach-gallery-denied-${photoItem(3).id}')),
        findsNothing,
        reason: 'the video is still allowed',
      );
      expect(tester.widget<LibraryGridCell>(cell(1)).dimmed, isTrue);

      expect(controller.send(), isFalse);
      await tester.pumpAndSettle();
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendPhoto,
          reason: const DenialReason.everyone(),
        ),
      ]);
      expect(rig.outcome, isNull);
      expect(find.byType(GalleryView), findsOne, reason: 'the picker is open');
      expect(rig.selection.length, 2);
      expect(controller.caption.richText.plain, 'look');
      expect(controller.refusals.value, 1, reason: 'the field shakes');

      source.update(sending: const SendingCapabilities());
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('attach-gallery-denied-${photo.id}')),
        findsNothing,
      );
      expect(controller.send(), isTrue);
      await tester.pumpAndSettle();
      expect(rig.outcome, isA<AttachOutcome$Send>());
    });
  });

  group('files', () {
    testWidgets('Android: files denied replace the content with the text', (
      tester,
    ) async {
      source.update(sending: _denying([MediaKind.file]));
      await open(tester, initial: AttachPageId.files);

      expect(find.byKey(const ValueKey('attach-files-denied')), findsOne);
      expect(find.byKey(const ValueKey('attach-files-dialog')), findsNothing);
      final text = tester.widget<Text>(find.byKey(deniedText));
      expect(text.data, 'No files here');
      expect(text.textAlign, TextAlign.start);
      expectChromeText(
        tester,
        within: find.byKey(const ValueKey('attach-files-denied')),
      );
    });

    testWidgets('iOS: files denied show an empty state with the text', (
      tester,
    ) async {
      source.update(sending: _denying([MediaKind.file]));
      await open(
        tester,
        policy: const AttachSheetPolicy.ios(),
        attachPolicy: const AttachPolicy.ios(),
        initial: AttachPageId.files,
      );

      final text = tester.widget<Text>(find.byKey(deniedText));
      expect(text.data, 'No files here');
      expect(text.textAlign, TextAlign.center);
      expectChromeText(
        tester,
        within: find.byKey(const ValueKey('attach-files-denied')),
      );
    });

    testWidgets('with no text from the host the page is silent and the '
        'missing text is reported', (tester) async {
      feedback.texts.clear();
      source.update(sending: _denying([MediaKind.file]));
      await open(tester, initial: AttachPageId.files);

      expect(find.byKey(const ValueKey('attach-files-denied')), findsOne);
      expect(find.byKey(deniedText), findsNothing);
      final missing = diagnostics.whereOp(CapabilitiesOp.denialTextMissing);
      expect(missing.last.fields['form'], AttachDenialForm.filesPage);
      expect(missing.last.correlation.chatId, 'c1');
    });

    testWidgets('audio denied alone: the tab keeps its content and an audio '
        'pick is reported, a document joins', (tester) async {
      source.update(sending: _denying([MediaKind.audio]));
      final rig = await open(tester, initial: AttachPageId.files);
      intake.enqueuePick([
        _file('song.mp3', mime: 'audio/mpeg'),
        _file('report.pdf', mime: 'application/pdf'),
      ]);

      await tester.tap(find.byKey(const ValueKey('attach-files-dialog')));
      await tester.pumpAndSettle();

      expect(rig.selection.items.map((i) => i.kind), [AttachKind.file]);
      expect(feedback.denials.single.action, CapabilityAction.sendAudio);
      expect(host.interactions, isEmpty);
    });

    testWidgets('re-allowed while open, the content comes back', (
      tester,
    ) async {
      source.update(sending: _denying([MediaKind.file]));
      await open(tester, initial: AttachPageId.files);

      source.update(sending: const SendingCapabilities());
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('attach-files-denied')), findsNothing);
      expect(find.byKey(const ValueKey('attach-files-dialog')), findsOne);
    });
  });

  group('desktop', () {
    testWidgets('an attach of a denied file is refused per file', (
      tester,
    ) async {
      source.update(sending: _denying([MediaKind.photo]));
      final box = ConfirmBoxController(
        policy: const AttachSheetPolicy.desktop(),
        selection: AttachSelection(
          policy: const AttachPolicy.desktop(),
          limits: const AttachLimits(),
        ),
        intake: intake,
        host: host,
        capabilities: capabilities(),
      );
      addTearDown(box.dispose);

      box.addFiles([
        _file('a.jpg', mime: 'image/jpeg'),
        _file('b.jpg', mime: 'image/jpeg'),
        _file('c.pdf', mime: 'application/pdf'),
      ]);

      expect(box.selection.items.map((i) => i.kind), [AttachKind.file]);
      expect(feedback.denials.map((d) => d.action), [
        CapabilityAction.sendPhoto,
        CapabilityAction.sendPhoto,
      ]);
      expect(host.interactions, isEmpty);
    });
  });

  group('one-send mode', () {
    testWidgets('Android: an 11th gallery pick is refused', (tester) async {
      source.update(slowMode: _slow);
      final rig = await open(tester);
      for (var i = 0; i < 10; i++) {
        rig.selection.toggle(AttachItems.photo('p$i'));
      }
      await tester.pumpAndSettle();
      expect(tester.widget<LibraryGridCell>(cell(0)).dimmed, isTrue);

      await tapCheck(tester, 0);
      await tester.pumpAndSettle();

      expect(rig.selection.length, 10);
      expect(host.interactions, [
        const AttachInteraction.refused(AttachRefusal.capReached),
      ]);
    });

    testWidgets('one album sends as one unit', (tester) async {
      source.update(slowMode: _slow);
      final rig = await open(tester);
      for (var i = 0; i < 10; i++) {
        rig.selection.toggle(AttachItems.photo('p$i'));
      }
      await tester.pumpAndSettle();

      // Asked ungrouped, it still goes as one album.
      expect(panel(tester).send((o) => o.copyWith(grouped: false)), isTrue);
      await tester.pumpAndSettle();

      final request = (rig.outcome! as AttachOutcome$Send).request;
      final plan = planSend(
        request,
        rig.selection.policy,
        rig.selection.limits,
      );
      expect((plan as SendPlan$Ready).sends, hasLength(1));
    });

    testWidgets('a selection that would go as two units is refused', (
      tester,
    ) async {
      source.update(slowMode: _slow);
      final rig = await open(tester);
      rig.selection
        ..toggle(AttachItems.photo('p0'))
        ..toggle(AttachItems.photo('p1'))
        ..toggle(AttachItems.file('f'));
      await tester.pumpAndSettle();
      final controller = panel(tester);

      expect(controller.send(), isFalse);
      await tester.pumpAndSettle();

      expect(rig.outcome, isNull);
      expect(host.interactions, [const AttachInteraction.oneSendRefused()]);
      expect(
        controller.overflow,
        isNot(contains(AttachOverflowItem.withoutGrouping)),
      );
    });

    testWidgets('the default capabilities behave as none', (tester) async {
      final rig = await open(tester);
      expect(rig.selection.limits, const AttachLimits());
      expect(rig.selection.cap, 100);
      expect(diagnostics.whereOp(AttachOp.pickerOneSend), isEmpty);
    });

    testWidgets('pickerOneSend reports on and off, not a slow mode tick', (
      tester,
    ) async {
      final rig = await open(tester);
      var signals = 0;
      rig.selection.changes.addListener(() => signals++);

      source.update(slowMode: _slow);
      source.update(
        slowMode: _slow.copyWith(nextSendAt: DateTime(2026), pending: true),
      );
      final afterOn = signals;
      source.update(slowMode: _slow.copyWith(nextSendAt: DateTime(2027)));
      expect(signals, afterOn, reason: 'a tick does not reach the selection');
      source.update(slowMode: SlowMode.none);

      final events = diagnostics.whereOp(AttachOp.pickerOneSend);
      expect(
        [for (final e in events) e.fields],
        [
          {'on': true, 'albumCap': 10},
          {'on': false, 'albumCap': 10},
        ],
      );
      expect(events.first.correlation.chatId, 'c1');
      expect(events.first.level, ChatEventLevel.debug);
    });
  });
}
