/// The default file row: control or thumbnail, the name cut in the middle,
/// the info line with its progress, the link line, and right to left.
///
/// **Seam:** `MessageMediaView` over a `ContentAssetScope` whose media
/// producer is a `FakeAssetProducer`, laid out by each platform's policy.
library;

import 'package:chrome_foundation/chrome_foundation.dart'
    show ChromePalette, ChromeStrings, ChromeTooltip;
import 'package:chrome_foundation/testing.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

import '../support/media_scopes.dart';

/// The painter's measure, recording the family and the scaler of every
/// span it is asked for.
final class _RecordingMeasure implements MediaTextMeasure {
  final families = <String?>[];
  final scalers = <TextScaler>[];

  @override
  MediaTextSize measure(
    InlineSpan text, {
    required TextScaler scaler,
    double maxWidth = double.infinity,
    int maxLines = 1,
    bool ellipsis = false,
  }) {
    if (text case TextSpan(:final style)) families.add(style?.fontFamily);
    scalers.add(scaler);
    return const MediaTextMeasure.painter().measure(
      text,
      scaler: scaler,
      maxWidth: maxWidth,
      maxLines: maxLines,
      ellipsis: ellipsis,
    );
  }
}

Finder _tooltipOf(String text) => find.byWidgetPredicate(
  (widget) => widget is RawTooltip && widget.semanticsTooltip == text,
);

MediaItem _file(
  String id, {
  String name = 'a.pdf',
  String? mimeType,
  int? byteSize = 2048,
}) => MediaItem(
  id: MediaItemId(id),
  kind: MediaItemKind.file,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    fileName: name,
    mimeType: mimeType,
    byteSize: byteSize,
  ),
);

void main() {
  late FakeAssetProducer producer;
  late ContentAssetScope scope;

  setUp(() {
    producer = FakeAssetProducer();
    scope = ContentAssetScope.withMedia(producer: producer);
    addTearDown(scope.dispose);
  });

  // The host's path: the layout input's text is the view's own
  // `MediaLayoutText.of(context)`, here under [strings], a theme of
  // [fontFamily] and a [textScale].
  Future<void> pump(
    WidgetTester tester,
    MessageMediaPolicy policy,
    List<MediaItem> items, {
    TextDirection direction = TextDirection.ltr,
    double width = 364,
    ChromeStrings? strings,
    String? fontFamily,
    double textScale = 1,
    MediaTextMeasure measure = const MediaTextMeasure.painter(),
  }) => tester.pumpWidget(
    MediaScopes.wrap(
      strings: strings,
      MaterialApp(
        theme: ThemeData(fontFamily: fontFamily),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Directionality(
            textDirection: direction,
            child: ContentAssetProvider(
              scope: scope,
              child: Align(
                alignment: Alignment.topLeft,
                child: Builder(
                  builder: (context) => MessageMediaView(
                    layout: policy.layout(
                      MediaLayoutInput(
                        text: MediaLayoutText.of(context, measure: measure),
                        items: items,
                        availableWidth: width,
                      ),
                    ),
                    items: items,
                    policy: policy,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Rect rectIn(WidgetTester tester, String id, Finder finder) {
    final cell = find.byKey(ValueKey(MediaItemId(id)));
    final origin = tester.getTopLeft(cell);
    return tester
        .getRect(find.descendant(of: cell, matching: finder).first)
        .shift(-origin);
  }

  testWidgets('a row draws its control, name and info line where the file '
      'stack laid them out', (tester) async {
    const policy = MessageMediaPolicy.android();
    await pump(tester, policy, [_file('f')]);

    expect(find.byType(MediaRowCell), findsOneWidget);
    expect(
      rectIn(tester, 'f', find.byType(ContentAssetView)),
      const Rect.fromLTWH(14, 6, 44, 44),
    );
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('2.0 KB PDF'), findsOneWidget);
    expect(
      rectIn(tester, 'f', find.text('a.pdf')).topLeft,
      const Offset(67, 10),
    );
    expect(
      rectIn(tester, 'f', find.text('2.0 KB PDF')).topLeft,
      const Offset(67, 33),
    );
    final status = tester.widget<ContentAssetView>(
      find.byType(ContentAssetView),
    );
    expect(status.status, const MediaStatusMode.control());
  });

  testWidgets('a row without a picture draws the file disc in the control '
      'slot, under the control, in the theme\'s accent', (tester) async {
    const policy = MessageMediaPolicy.android();
    await pump(tester, policy, [_file('f', name: 'notes.txt')]);

    expect(
      rectIn(tester, 'f', find.byType(MediaFileDisc)),
      const Rect.fromLTWH(14, 6, 44, 44),
    );
    final disc = tester.widget<MediaFileDisc>(find.byType(MediaFileDisc));
    expect(disc.color, const ChromePalette.light().accent);
    // The control draws over the disc.
    final stack = find
        .ancestor(of: find.byType(MediaFileDisc), matching: find.byType(Stack))
        .first;
    final children = tester.widget<Stack>(stack).children;
    expect(
      children.indexWhere((c) => c is MediaFileDisc),
      lessThan(children.indexWhere((c) => c is IgnorePointer)),
    );
  });

  testWidgets('a row with a thumbnail draws no file disc', (tester) async {
    await pump(tester, const MessageMediaPolicy.android(), [
      _file('i', name: 'b.png', mimeType: 'image/png'),
    ]);
    expect(find.byType(MediaFileDisc), findsNothing);
  });

  testWidgets('a row with a thumbnail draws the thumbnail, the control '
      'centred on it, its leading corners from the cell', (tester) async {
    const policy = MessageMediaPolicy.android();
    await pump(tester, policy, [
      _file('i', name: 'b.png', mimeType: 'image/png'),
    ]);

    expect(
      rectIn(tester, 'i', find.byType(ContentAssetView)),
      const Rect.fromLTWH(4, 0, 86, 86),
    );
    final clips = tester
        .widgetList<ClipRRect>(
          find.descendant(
            of: find.byType(MediaRowCell),
            matching: find.byType(ClipRRect),
          ),
        )
        .toList();
    // The row's own clip, then the thumbnail's: leading corners from the
    // bubble's edge radius, trailing 4.
    final row = clips.first.borderRadius as BorderRadius;
    final thumb = clips[1].borderRadius as BorderRadius;
    expect(thumb.topLeft, row.topLeft);
    expect(thumb.bottomLeft, row.bottomLeft);
    expect(thumb.topRight, const Radius.circular(4));
    expect(thumb.bottomRight, const Radius.circular(4));
  });

  testWidgets('a long name is cut in the middle, keeping its start and its '
      'extension', (tester) async {
    const policy = MessageMediaPolicy.desktop();
    final name = '${'a' * 40}-final.pdf';
    await pump(tester, policy, [_file('f', name: name)]);

    final text = tester.widget<Text>(
      find.descendant(
        of: find.byType(MiddleElidedText),
        matching: find.byType(Text),
      ),
    );
    final shown = text.data!;
    expect(shown, contains('…'));
    expect(shown, startsWith('aaaa'));
    expect(shown, endsWith('l.pdf'));
    expect(shown.length, lessThan(name.length));
    // Desktop shows the full name in a tooltip when it is cut.
    expect(_tooltipOf(name), findsOneWidget);
  });

  testWidgets('the cut name\'s tooltip is the chrome tooltip, in the chrome '
      'text style', (tester) async {
    final name = '${'a' * 40}-final.pdf';
    await pump(tester, const MessageMediaPolicy.desktop(), [
      _file('f', name: name),
    ]);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(MiddleElidedText)));
    await tester.pumpAndSettle();
    final tooltip = find.byType(ChromeTooltip);
    expect(tooltip, findsOneWidget);
    expect(
      find.descendant(of: tooltip, matching: find.text(name)),
      findsOneWidget,
    );
    expectChromeText(tester, within: tooltip);
  });

  testWidgets('a name that fits is drawn whole, with no tooltip', (
    tester,
  ) async {
    await pump(tester, const MessageMediaPolicy.desktop(), [_file('f')]);
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.byType(RawTooltip), findsNothing);
  });

  testWidgets('mobile names are cut too, with no tooltip', (tester) async {
    final name = '${'b' * 60}.zip';
    await pump(tester, const MessageMediaPolicy.android(), [
      _file('f', name: name),
    ]);
    final shown = tester
        .widget<Text>(
          find.descendant(
            of: find.byType(MiddleElidedText),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(shown, contains('…'));
    expect(shown, endsWith('.zip'));
    expect(find.byType(RawTooltip), findsNothing);
  });

  testWidgets('while bytes arrive the info line shows received / total', (
    tester,
  ) async {
    await pump(tester, const MessageMediaPolicy.android(), [_file('f')]);
    producer.attempts.last.transfer(1024, 4096);
    await tester.pump();
    expect(find.text('1.0 KB / 4.0 KB'), findsOneWidget);
    expect(find.text('2.0 KB PDF'), findsNothing);
  });

  testWidgets('the desktop link line reads download, then cancel while the '
      'file downloads', (tester) async {
    await pump(tester, const MessageMediaPolicy.desktop(), [
      _file('i', name: 'b.png', mimeType: 'image/png'),
    ]);
    expect(find.text('DOWNLOAD'), findsOneWidget);
    expect(
      rectIn(tester, 'i', find.text('DOWNLOAD')).topLeft,
      const Offset(92, 55),
    );
    producer.attempts.last.transfer(10, 100);
    await tester.pump();
    expect(find.text('CANCEL'), findsOneWidget);
  });

  testWidgets('the chrome strings scope words the size, the info and the '
      'link line', (tester) async {
    await pump(
      tester,
      const MessageMediaPolicy.desktop(),
      [_file('i', name: 'b.png', mimeType: 'image/png')],
      strings: ChromeStringsPresets.russian,
    );
    expect(find.text('СКАЧАТЬ'), findsOneWidget);
    expect(find.text('2.0 КБ'), findsOneWidget);
  });

  group('measure and paint agree', () {
    // A themed family and a larger text: the layout measures in the one base
    // style and scaler the row paints with.
    testWidgets('the row measures and draws its text in the theme\'s '
        'family under the platform\'s text scaler', (tester) async {
      final measure = _RecordingMeasure();
      final name = '${'n' * 30}.pdf';
      await pump(
        tester,
        const MessageMediaPolicy.android(),
        [_file('f', name: name)],
        fontFamily: 'Serif',
        textScale: 1.5,
        measure: measure,
      );
      expect(measure.families, everyElement('Serif'));
      expect(measure.scalers, everyElement(const TextScaler.linear(1.5)));
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(MediaRowCell),
          matching: find.byType(Text),
        ),
      );
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(text.style?.fontFamily, 'Serif');
        expect(text.textScaler, const TextScaler.linear(1.5));
      }
    });

    testWidgets('a scaled name takes the lines the layout gave it', (
      tester,
    ) async {
      const policy = MessageMediaPolicy.android();
      final item = _file('f', name: '${'w' * 24}.pdf');
      await pump(tester, policy, [item], textScale: 1.6);
      final row = policy
          .layout(
            MediaLayoutInput(
              text: MediaScopes.text.copyWith(
                scaler: const TextScaler.linear(1.6),
              ),
              items: [item],
              availableWidth: 364,
            ),
          )
          .blocks
          .whereType<MediaBlock$FileStack>()
          .single
          .rows
          .single;
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(MiddleElidedText),
          matching: find.byType(RichText),
        ),
      );
      // The name was measured over more than one line at this scale, and
      // the drawn text fills exactly the rect laid out for it.
      expect(row.nameLines, greaterThan(1));
      expect(paragraph.size.height, row.name.height);
      expect(
        paragraph.getMaxIntrinsicHeight(row.name.width),
        lessThanOrEqualTo(row.name.height),
      );
    });
  });

  group('right to left', () {
    testWidgets('desktop mirrors a file row', (tester) async {
      await pump(tester, const MessageMediaPolicy.desktop(), [
        _file('f'),
      ], direction: TextDirection.rtl);
      // 268 wide: the control's (12, 8, 44, 44) mirrored.
      expect(
        rectIn(tester, 'f', find.byType(ContentAssetView)),
        const Rect.fromLTWH(268 - 56, 8, 44, 44),
      );
      final name = tester.widget<MiddleElidedText>(
        find.byType(MiddleElidedText),
      );
      expect(name.textAlign, TextAlign.right);
    });

    for (final policy in const [
      MessageMediaPolicy.android(),
      MessageMediaPolicy.ios(),
    ]) {
      testWidgets('${policy.family.name} does not mirror a file row', (
        tester,
      ) async {
        await pump(tester, policy, [_file('f')], direction: TextDirection.rtl);
        final leading = policy.fileStack.plain.leading;
        expect(rectIn(tester, 'f', find.byType(ContentAssetView)), leading);
        final name = tester.widget<MiddleElidedText>(
          find.byType(MiddleElidedText),
        );
        expect(name.textAlign, TextAlign.left);
      });
    }
  });

  testWidgets('a three-file stack draws one row per file at its rect', (
    tester,
  ) async {
    const policy = MessageMediaPolicy.ios();
    final items = [
      _file('a'),
      _file('b', name: 'b.png', mimeType: 'image/png'),
      _file('c'),
    ];
    await pump(tester, policy, items);
    final layout = policy.layout(
      MediaLayoutInput(
        text: MediaScopes.text,
        items: items,
        availableWidth: 364,
      ),
    );
    expect(find.byType(MediaRowCell), findsNWidgets(3));
    for (final item in items) {
      final cell = find.byKey(ValueKey(item.id));
      expect(tester.getRect(cell), layout.cellOf(item.id)!.rect);
    }
  });

  testWidgets('row text starts from the chrome typography, not the '
      'framework fallback, with no app above it', (tester) async {
    const policy = MessageMediaPolicy.desktop();
    final items = [_file('i', name: 'b.png', mimeType: 'image/png')];
    await tester.pumpWidget(
      MediaScopes.wrap(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ContentAssetProvider(
            scope: scope,
            child: Align(
              alignment: Alignment.topLeft,
              child: MessageMediaView(
                layout: policy.layout(
                  MediaLayoutInput(
                    text: MediaScopes.text,
                    items: items,
                    availableWidth: 364,
                  ),
                ),
                items: items,
                policy: policy,
              ),
            ),
          ),
        ),
      ),
    );
    expectChromeText(tester, within: find.byType(MediaRowCell));
  });
}
