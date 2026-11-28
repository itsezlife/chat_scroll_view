/// One open of the draft options: the edited value, the apply mode, the host
/// reports and the events.
///
/// **Seam:** `DraftOptionsSession` over a `RecordingDraftOptionsHost`, with
/// `RecordingDiagnostics` installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));

void main() {
  late RecordingDiagnostics diagnostics;
  late RecordingDraftOptionsHost host;
  late ManualComposerClock clock;
  late List<DraftOptionsCloseTrigger> closes;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    host = RecordingDraftOptionsHost();
    clock = ManualComposerClock(DateTime(2026, 11, 28));
    closes = [];
  });

  DraftOptionsSession open(
    DraftOptionsPolicy policy, {
    LinkPreviewState page = LinkPreviewState.pending,
  }) => DraftOptionsSession(
    policy: policy,
    host: host,
    part: DraftPart.link,
    initial: _initial,
    page: page,
    clock: clock,
    correlation: () => const ChatCorrelation(chatId: 'chat-1'),
    onClose: closes.add,
  );

  final larger = _initial.copyWith(
    options: _initial.options.copyWith(media: LinkPreviewMedia.large),
  );
  final above = larger.copyWith(invertMedia: true);

  group('liveApply', () {
    test('reports each edit at once', () {
      final session = open(const DraftOptionsPolicy.android())
        ..edit(larger, field: DraftOptionsField.size);
      expect(host.edits, [larger]);

      session.edit(above, field: DraftOptionsField.position);
      expect(host.edits, [larger, above]);
      expect(session.value.value, above);
    });

    test('apply only closes: nothing more is reported', () {
      final session = open(const DraftOptionsPolicy.android())
        ..edit(larger, field: DraftOptionsField.size)
        ..apply();

      expect(host.edits, [larger]);
      expect(closes, [DraftOptionsCloseTrigger.apply]);
      expect(session.isClosing, isTrue);
    });

    test('edits while closing are dropped', () {
      open(const DraftOptionsPolicy.android())
        ..apply()
        ..edit(larger, field: DraftOptionsField.size)
        ..apply();

      expect(host.edits, isEmpty);
      expect(closes, [DraftOptionsCloseTrigger.apply]);
    });

    test('an edit to the same value reports nothing', () {
      open(
        const DraftOptionsPolicy.android(),
      ).edit(_initial, field: DraftOptionsField.size);

      expect(host.edits, isEmpty);
    });

    test('each edit emits editReported, live', () {
      open(
        const DraftOptionsPolicy.ios(),
      ).edit(larger, field: DraftOptionsField.size);

      expect(diagnostics.whereOp(OverlayOp.editReported), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
          fields: {'field': 'size', 'mode': 'live'},
        ),
      ]);
    });
  });

  group('commitOnSave', () {
    test('reports nothing until save, then the copy, and closes', () {
      final session =
          open(
              const DraftOptionsPolicy.desktop(),
              page: LinkPreviewState.loaded(LinkPreview(url: _url)),
            )
            ..edit(larger, field: DraftOptionsField.size)
            ..edit(above, field: DraftOptionsField.position);

      expect(host.edits, isEmpty);
      expect(session.value.value, above);

      session.apply();
      expect(host.edits, [above]);
      expect(closes, [DraftOptionsCloseTrigger.save]);
      expect(diagnostics.whereOp(OverlayOp.editReported).map((e) => e.fields), [
        {'field': 'size', 'mode': 'onSave'},
        {'field': 'position', 'mode': 'onSave'},
      ]);
    });

    test('cancel discards the copy', () {
      open(const DraftOptionsPolicy.desktop())
        ..edit(larger, field: DraftOptionsField.size)
        ..cancel();

      expect(host.edits, isEmpty);
      expect(closes, [DraftOptionsCloseTrigger.cancel]);
      expect(diagnostics.whereOp(OverlayOp.editsDiscarded), [
        isChatEvent(fields: {'edits': 1}),
      ]);
    });

    test('Escape, outside and back discard the copy', () {
      for (final trigger in [
        DraftOptionsCloseTrigger.escape,
        DraftOptionsCloseTrigger.outside,
        DraftOptionsCloseTrigger.back,
      ]) {
        open(const DraftOptionsPolicy.desktop())
          ..edit(larger, field: DraftOptionsField.size)
          ..close(trigger);
      }

      expect(host.edits, isEmpty);
      expect(diagnostics.whereOp(OverlayOp.editsDiscarded), hasLength(3));
    });

    test('save without edits reports nothing', () {
      open(const DraftOptionsPolicy.desktop()).apply();

      expect(host.edits, isEmpty);
      expect(closes, [DraftOptionsCloseTrigger.save]);
    });
  });

  group('events', () {
    test('opened names the presentation, part, page and apply mode', () {
      DraftOptionsSession(
        policy: const DraftOptionsPolicy.android(),
        host: host,
        part: DraftPart.link,
        initial: _initial,
        page: LinkPreviewState.pending,
        clock: clock,
        keyboardWasUp: true,
        correlation: () => const ChatCorrelation(chatId: 'chat-1'),
        onClose: closes.add,
      );

      expect(diagnostics.whereOp(OverlayOp.opened), [
        isChatEvent(
          level: ChatEventLevel.info,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
          fields: {
            'presentation': 'android',
            'part': 'link',
            'page': 'pending',
            'apply': 'liveApply',
            'keyboardWasUp': true,
          },
        ),
      ]);
    });

    test('closed carries the trigger, open time, edits and committed', () {
      open(
        const DraftOptionsPolicy.android(),
      ).edit(larger, field: DraftOptionsField.size);
      clock.advance(const Duration(milliseconds: 1200));
      open(const DraftOptionsPolicy.desktop())
        ..edit(larger, field: DraftOptionsField.size)
        ..cancel();

      expect(diagnostics.whereOp(OverlayOp.closed), [
        isChatEvent(
          level: ChatEventLevel.info,
          fields: {
            'trigger': 'cancel',
            'openMs': 0,
            'edits': 1,
            'committed': false,
          },
        ),
      ]);
    });

    test('closed after a live edit and apply is committed', () {
      final session = open(const DraftOptionsPolicy.android())
        ..edit(larger, field: DraftOptionsField.size);
      clock.advance(const Duration(milliseconds: 1200));
      session.apply();

      expect(diagnostics.whereOp(OverlayOp.closed).single.fields, {
        'trigger': 'apply',
        'openMs': 1200,
        'edits': 1,
        'committed': true,
      });
    });

    test('no event carries the URL', () {
      open(const DraftOptionsPolicy.desktop())
        ..edit(larger, field: DraftOptionsField.size)
        ..apply();

      for (final event in diagnostics.events) {
        expect(event.fields.values.join(' '), isNot(contains('news.example')));
      }
    });
  });

  group('removed after close', () {
    test('reports the host value with removed set', () {
      final session = open(const DraftOptionsPolicy.desktop())
        ..edit(larger, field: DraftOptionsField.size)
        ..close(DraftOptionsCloseTrigger.denied)
        ..reportRemoved();

      expect(host.edits, [
        _initial.copyWith(options: _initial.options.copyWith(removed: true)),
      ]);
      expect(session.isClosing, isTrue);
    });

    test('live: over the last edit reported', () {
      open(const DraftOptionsPolicy.android())
        ..edit(larger, field: DraftOptionsField.size)
        ..close(DraftOptionsCloseTrigger.denied)
        ..reportRemoved();

      expect(
        host.edits.last,
        larger.copyWith(options: larger.options.copyWith(removed: true)),
      );
    });
  });
}
