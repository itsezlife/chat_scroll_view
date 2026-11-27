/// The default file row: control or thumbnail, the name cut in the middle,
/// the info line with its progress, the link line, and right to left.
///
/// **Seam:** `MessageMediaView` over a `ContentAssetScope` whose media
/// producer is a `FakeAssetProducer`, laid out by each platform's policy.
library;

import 'package:chrome_foundation/testing.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

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

  Future<void> pump(
    WidgetTester tester,
    MessageMediaPolicy policy,
    List<MediaItem> items, {
    TextDirection direction = TextDirection.ltr,
    double width = 364,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: direction,
        child: ContentAssetProvider(
          scope: scope,
          child: Align(
            alignment: Alignment.topLeft,
            child: MessageMediaView(
              layout: policy.layout(
                MediaLayoutInput(items: items, availableWidth: width),
              ),
              items: items,
              policy: policy,
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
    expect(find.byTooltip(name), findsOneWidget);
  });

  testWidgets('a name that fits is drawn whole, with no tooltip', (
    tester,
  ) async {
    await pump(tester, const MessageMediaPolicy.desktop(), [_file('f')]);
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
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
    expect(find.byType(Tooltip), findsNothing);
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

  testWidgets('host strings word the link line', (tester) async {
    const base = MessageMediaPolicy.desktop();
    final step = base.layoutStep as MediaLayoutPolicy;
    final policy = base.copyWith(
      layoutStep: step.copyWith(
        fileStack: step.fileStack.copyWith(
          strings: MediaFileStrings.english.copyWith(download: 'FETCH'),
        ),
      ),
    );
    await pump(tester, policy, [
      _file('i', name: 'b.png', mimeType: 'image/png'),
    ]);
    expect(find.text('FETCH'), findsOneWidget);
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
      MediaLayoutInput(items: items, availableWidth: 364),
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
      Directionality(
        textDirection: TextDirection.ltr,
        child: ContentAssetProvider(
          scope: scope,
          child: Align(
            alignment: Alignment.topLeft,
            child: MessageMediaView(
              layout: policy.layout(
                MediaLayoutInput(items: items, availableWidth: 364),
              ),
              items: items,
              policy: policy,
            ),
          ),
        ),
      ),
    );
    expectChromeText(tester, within: find.byType(MediaRowCell));
  });
}
