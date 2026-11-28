/// The link page's rows, headless: which rows each platform shows, when the
/// size row is there or inert, what a tap edits, the remove row and the
/// input guard.
///
/// **Seam:** `DraftLinkPage` over a `DraftOptionsSession`, reporting to a
/// `RecordingDraftOptionsHost`, with `RecordingDiagnostics` installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _other = Uri.parse('https://docs.example/guide');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));
const _photo = ContentDescriptor(key: ContentKey.external('p'));
const _video = ContentDescriptor(key: ContentKey.external('v'));

LinkPreviewState _page({ContentDescriptor? photo, ContentDescriptor? media}) =>
    LinkPreviewState.loaded(
      LinkPreview(url: _url, title: 'A story', photo: photo, media: media),
    );

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

  DraftLinkPage open(
    DraftOptionsPolicy policy, {
    LinkPreviewState? page,
    DraftLinkPart? initial,
    List<Uri>? links,
    bool hasText = true,
    LinkPreviewDismissal? dismissal,
    DraftLinkMediaReader? mediaOf,
  }) {
    final session = DraftOptionsSession(
      policy: policy,
      host: host,
      part: DraftPart.link,
      initial: initial ?? _initial,
      page: page ?? _page(photo: _photo),
      links: links ?? [_url],
      clock: clock,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
      onClose: closes.add,
    );
    return DraftLinkPage(
      session: session,
      hasText: hasText,
      dismissal: dismissal,
      mediaOf: mediaOf,
      clock: clock,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
    );
  }

  List<DraftLinkRow> rowsOf(DraftLinkPage page) => [
    for (final row in page.rows) row.row,
  ];

  group('rows per platform', () {
    test('Android: position, size, apply, remove', () {
      final page = open(const DraftOptionsPolicy.android());

      expect(rowsOf(page), [
        DraftLinkRow.position,
        DraftLinkRow.size,
        DraftLinkRow.apply,
        DraftLinkRow.remove,
      ]);
      expect(
        [for (final row in page.rows) row.label],
        [
          DraftLinkLabel.moveUp,
          DraftLinkLabel.shrinkPhoto,
          DraftLinkLabel.applyChanges,
          DraftLinkLabel.doNotPreview,
        ],
      );
      expect(page.showsLinkHint, isFalse);
    });

    test('iOS: position, size, apply, remove', () {
      final page = open(const DraftOptionsPolicy.ios());

      expect(rowsOf(page), [
        DraftLinkRow.position,
        DraftLinkRow.size,
        DraftLinkRow.apply,
        DraftLinkRow.remove,
      ]);
      expect(page.rows.last.label, DraftLinkLabel.doNotPreview);
    });

    test('desktop: position, size and remove; Save is a button', () {
      final page = open(const DraftOptionsPolicy.desktop());

      expect(rowsOf(page), [
        DraftLinkRow.position,
        DraftLinkRow.size,
        DraftLinkRow.remove,
      ]);
      expect(page.rows.last.label, DraftLinkLabel.removePreview);
    });

    test('desktop shows position only when the draft has text', () {
      final page = open(const DraftOptionsPolicy.desktop(), hasText: false);

      expect(rowsOf(page), [DraftLinkRow.size, DraftLinkRow.remove]);
      expect(
        rowsOf(open(const DraftOptionsPolicy.android(), hasText: false)),
        contains(DraftLinkRow.position),
      );
    });

    test('desktop hints at choosing a link with more than one link', () {
      expect(
        open(const DraftOptionsPolicy.desktop(), links: [_url]).showsLinkHint,
        isFalse,
      );
      expect(
        open(
          const DraftOptionsPolicy.desktop(),
          links: [_url, _other],
        ).showsLinkHint,
        isTrue,
      );
      expect(
        open(
          const DraftOptionsPolicy.android(),
          links: [_url, _other],
        ).showsLinkHint,
        isFalse,
      );
    });

    test('row icons show the target state', () {
      final page = open(const DraftOptionsPolicy.android());

      expect(
        [for (final row in page.rows) row.icon],
        [
          ChromeIconId.moveUp,
          ChromeIconId.shrink,
          ChromeIconId.confirm,
          ChromeIconId.delete,
        ],
      );
    });
  });

  group('size row (D10, D22)', () {
    test('iOS and desktop show it only with shrinkable media', () {
      for (final policy in [
        const DraftOptionsPolicy.ios(),
        const DraftOptionsPolicy.desktop(),
      ]) {
        expect(
          rowsOf(open(policy, page: _page())),
          isNot(contains(DraftLinkRow.size)),
          reason: '$policy',
        );
        expect(
          rowsOf(
            open(
              policy,
              mediaOf: (_, _) => const DraftLinkMedia(
                kind: DraftLinkMediaKind.photo,
                shrinkable: false,
                large: true,
              ),
            ),
          ),
          isNot(contains(DraftLinkRow.size)),
          reason: '$policy, media that cannot shrink',
        );
        expect(
          rowsOf(open(policy)),
          contains(DraftLinkRow.size),
          reason: '$policy',
        );
      }
    });

    test('a pending page has no media to size', () {
      final page = open(
        const DraftOptionsPolicy.ios(),
        page: LinkPreviewState.pending,
      );

      expect(rowsOf(page), isNot(contains(DraftLinkRow.size)));
    });

    test('Android shows it inert without shrinkable media', () {
      final page = open(
        const DraftOptionsPolicy.android(),
        page: _page(),
        links: [_url, _other],
      );

      final size = page.rows.firstWhere((r) => r.row == DraftLinkRow.size);
      expect(size.inert, isTrue);
      expect(page.rows.where((r) => r.inert), [size]);
    });

    test('Android hides it only for a single link with no media', () {
      expect(
        rowsOf(open(const DraftOptionsPolicy.android(), page: _page())),
        isNot(contains(DraftLinkRow.size)),
      );
      final unshrinkable = open(
        const DraftOptionsPolicy.android(),
        mediaOf: (_, _) => const DraftLinkMedia(
          kind: DraftLinkMediaKind.video,
          shrinkable: false,
          large: true,
        ),
      );
      final size = unshrinkable.rows.firstWhere(
        (r) => r.row == DraftLinkRow.size,
      );
      expect(size.inert, isTrue);
      expect(size.label, DraftLinkLabel.shrinkVideo);
    });

    test('an inert touch is ignored and reported', () {
      final page = open(
        const DraftOptionsPolicy.android(),
        page: _page(),
        links: [_url, _other],
      )..tap(DraftLinkRow.size);

      expect(host.edits, isEmpty);
      expect(diagnostics.whereOp(OverlayOp.rowInertTouch), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
          fields: {'row': 'size'},
        ),
      ]);
      expect(page.session.isClosing, isFalse);
    });

    test('a tap toggles the media between large and small', () {
      final page = open(const DraftOptionsPolicy.android())
        ..tap(DraftLinkRow.size);

      expect(host.edits.single.options.media, LinkPreviewMedia.small);
      expect(
        page.rows.firstWhere((r) => r.row == DraftLinkRow.size).label,
        DraftLinkLabel.enlargePhoto,
      );

      clock.advance(DraftLinkPagePolicy.android.rowGuard);
      page.tap(DraftLinkRow.size);
      expect(host.edits.last.options.media, LinkPreviewMedia.large);
      expect(diagnostics.whereOp(OverlayOp.editReported).map((e) => e.fields), [
        {'field': 'size', 'mode': 'live'},
        {'field': 'size', 'mode': 'live'},
      ]);
    });

    test('the video pair names a video', () {
      final page = open(
        const DraftOptionsPolicy.android(),
        page: _page(media: _video),
      );

      expect(
        page.rows.firstWhere((r) => r.row == DraftLinkRow.size).label,
        DraftLinkLabel.shrinkVideo,
      );
    });
  });

  group('position row', () {
    test('a tap edits invertMedia and flips the label', () {
      final page = open(const DraftOptionsPolicy.ios())
        ..tap(DraftLinkRow.position);

      expect(host.edits.single, _initial.copyWith(invertMedia: true));
      final position = page.rows.first;
      expect(position.label, DraftLinkLabel.moveDown);
      expect(position.icon, ChromeIconId.moveDown);
      expect(diagnostics.whereOp(OverlayOp.editReported).single.fields, {
        'field': 'position',
        'mode': 'live',
      });
    });

    test('under commit on save the edit waits for save', () {
      final page = open(const DraftOptionsPolicy.desktop())
        ..tap(DraftLinkRow.position);

      expect(host.edits, isEmpty);
      expect(page.session.value.value.invertMedia, isTrue);
    });
  });

  group('apply row', () {
    test('a tap within the guard of another row is dropped', () {
      open(const DraftOptionsPolicy.android())
        ..tap(DraftLinkRow.position)
        ..tap(DraftLinkRow.apply);

      // Within the guard: the second tap is dropped.
      expect(closes, isEmpty);
    });

    test('closes with trigger apply', () {
      final page = open(const DraftOptionsPolicy.android())
        ..tap(DraftLinkRow.position);
      clock.advance(DraftLinkPagePolicy.android.rowGuard);
      page.tap(DraftLinkRow.apply);

      expect(closes, [DraftOptionsCloseTrigger.apply]);
      expect(host.edits, [_initial.copyWith(invertMedia: true)]);
    });
  });

  group('remove row (Q5)', () {
    test('sets removed, applies the dismissal and closes', () {
      final dismissal = LinkPreviewDismissal(
        policy: LinkPreviewDismissalPolicy.perUrl,
      );
      open(
        const DraftOptionsPolicy.ios(),
        dismissal: dismissal,
      ).tap(DraftLinkRow.remove);

      expect(host.edits.single.options.removed, isTrue);
      expect(dismissal.allows(_url), isFalse);
      expect(closes, [DraftOptionsCloseTrigger.remove]);
      expect(diagnostics.whereOp(OverlayOp.removeApplied), [
        isChatEvent(
          level: ChatEventLevel.info,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
          fields: {'dismissal': 'perUrl', 'nextLink': false},
        ),
      ]);
      expect(
        diagnostics.whereOp(LinkPreviewDismissalOp.dismissed),
        hasLength(1),
      );
    });

    test('Android then falls back to the next link the dismissal allows', () {
      final dismissal = LinkPreviewDismissal(
        policy: LinkPreviewDismissalPolicy.perUrl,
      );
      open(
        const DraftOptionsPolicy.android(),
        initial: _initial.copyWith(invertMedia: true),
        links: [_url, _other],
        dismissal: dismissal,
      ).tap(DraftLinkRow.remove);

      expect(host.edits, [
        DraftLinkPart(
          options: LinkPreviewOptions(url: _url, removed: true),
          invertMedia: true,
        ),
        DraftLinkPart(
          options: LinkPreviewOptions(url: _other),
          invertMedia: true,
        ),
      ]);
      expect(closes, [DraftOptionsCloseTrigger.remove]);
      expect(diagnostics.whereOp(OverlayOp.removeApplied).single.fields, {
        'dismissal': 'perUrl',
        'nextLink': true,
      });
      expect(diagnostics.whereOp(OverlayOp.editReported).map((e) => e.fields), [
        {'field': 'remove', 'mode': 'live'},
        {'field': 'link', 'mode': 'live'},
      ]);
    });

    test('Android takes no next link a field dismissal turned off', () {
      final dismissal = LinkPreviewDismissal(
        policy: LinkPreviewDismissalPolicy.fieldUntilBigEdit,
      );
      open(
        const DraftOptionsPolicy.android(),
        links: [_url, _other],
        dismissal: dismissal,
      ).tap(DraftLinkRow.remove);

      expect(host.edits.single.options.removed, isTrue);
      expect(dismissal.searchEnabled, isFalse);
      expect(diagnostics.whereOp(OverlayOp.removeApplied).single.fields, {
        'dismissal': 'fieldUntilBigEdit',
        'nextLink': false,
      });
    });

    test('iOS does not fall back to another link', () {
      open(
        const DraftOptionsPolicy.ios(),
        links: [_url, _other],
      ).tap(DraftLinkRow.remove);

      expect(host.edits.single.options.removed, isTrue);
      expect(diagnostics.whereOp(OverlayOp.removeApplied).single.fields, {
        'dismissal': 'none',
        'nextLink': false,
      });
    });

    test('desktop reports the removal (and the copy) at once', () {
      final page = open(const DraftOptionsPolicy.desktop())
        ..tap(DraftLinkRow.position);
      clock.advance(DraftLinkPagePolicy.desktop.rowGuard);
      page.tap(DraftLinkRow.remove);

      expect(host.edits, [
        DraftLinkPart(
          options: LinkPreviewOptions(url: _url, removed: true),
          invertMedia: true,
        ),
      ]);
      expect(closes, [DraftOptionsCloseTrigger.remove]);
      expect(diagnostics.whereOp(OverlayOp.editsDiscarded), isEmpty);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['committed'],
        isTrue,
      );
    });
  });

  group('input guard', () {
    test('a burst on a row applies once per tap and is reported', () {
      final page = open(const DraftOptionsPolicy.android());
      for (var i = 0; i < 4; i++) {
        page.tap(DraftLinkRow.position);
        clock.advance(const Duration(milliseconds: 50));
      }

      expect(host.edits, [_initial.copyWith(invertMedia: true)]);
      expect(diagnostics.whereOp(OverlayOp.rowDropped).map((e) => e.fields), [
        {'row': 'position', 'ms': 50},
        {'row': 'position', 'ms': 100},
        {'row': 'position', 'ms': 150},
      ]);
    });

    test('no row re-enters while the close runs', () {
      final page = open(const DraftOptionsPolicy.android())
        ..tap(DraftLinkRow.apply);
      clock.advance(DraftLinkPagePolicy.android.rowGuard * 2);
      page
        ..tap(DraftLinkRow.position)
        ..tap(DraftLinkRow.remove);

      expect(closes, [DraftOptionsCloseTrigger.apply]);
      expect(host.edits, isEmpty);
      expect(
        diagnostics.whereOp(OverlayOp.rowDropped).map((e) => e.fields['row']),
        ['position', 'remove'],
      );
    });
  });
}
