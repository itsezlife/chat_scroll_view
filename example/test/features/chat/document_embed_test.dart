import 'dart:ui';

import 'package:chat_scroll_view_example/src/features/chat/data/bundled_packs.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_documents.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/showcase_bodies.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_body_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/document_embed.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart' show FontWeight, TextStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

import '../../support/test_services.dart';

const _metrics = InlineEmbedMetrics(
  fontSize: 15,
  ascent: 14,
  descent: 4,
  devicePixelRatio: 2,
);

InlineEmbedTarget _file(String id) =>
    InlineEmbedTarget(scheme: 'file', id: id, alt: id);

/// Answers every target with null, and remembers it was asked.
final class _Otherwise implements InlineEmbedResolver {
  final asked = <InlineEmbedTarget>[];

  @override
  InlineEmbed? resolve(InlineEmbedTarget target, InlineEmbedMetrics metrics) {
    asked.add(target);
    return null;
  }
}

/// Counts the paths drawn (the file icon) and the text laid out.
final class _Canvas implements Canvas {
  int paths = 0;
  int paragraphs = 0;

  @override
  void drawPath(Path path, Paint paint) => paths++;

  @override
  void drawParagraph(Paragraph paragraph, Offset offset) => paragraphs++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late FakeAssetProducer producer;
  late ContentAssetScope scope;
  late _Otherwise otherwise;

  const drawing = ChatDocument(
    key: ContentKey.document('doc-svg'),
    name: 'diagram.svg',
    mimeType: 'image/svg+xml',
    byteSize: 4096,
  );
  const report = ChatDocument(
    key: ContentKey.document('doc-pdf'),
    name: 'report.pdf',
    mimeType: 'application/pdf',
    byteSize: 120000,
  );

  setUp(() {
    producer = FakeAssetProducer();
    scope = ContentAssetScope.withMedia(producer: producer);
    otherwise = _Otherwise();
  });
  tearDown(() => scope.dispose());

  const style = DocumentRowStyle(text: TextStyle(fontFamily: 'ChromeFace'));

  DocumentEmbedResolver resolver({
    SvgDocumentPreview? previews = const SvgDocumentPreview(),
  }) => DocumentEmbedResolver(
    scope: scope,
    documents: (id) => {'doc-svg': drawing, 'doc-pdf': report}[id],
    previews: previews,
    otherwise: otherwise,
    style: listen.ValueNotifier(style),
  );

  test('an SVG document is a row whose thumbnail is its own drawing, '
      'attached with the preview\'s tag so it never downloads', () {
    final embed = resolver().resolve(_file('doc-svg'), _metrics)!;
    addTearDown(embed.dispose);

    expect(embed, isA<DocumentEmbed>());
    // The row with a thumbnail: as tall as its square.
    expect(embed.sizeHint, Size(style.width, style.thumbnailExtent));
    expect(producer.last.request.key, drawing.key.mediaKey);
    expect(producer.last.demand.downloadContexts, {
      SvgDocumentPreview.downloadContext,
    });
    // The thumbnail's pixels at the text's density.
    expect(
      producer.last.request.spec.pixelWidth,
      (style.thumbnailExtent * 2).ceil(),
    );
  });

  test('a document that is not SVG, or any document with previews off, '
      'keeps its file icon and attaches nothing', () {
    final pdf = resolver().resolve(_file('doc-pdf'), _metrics)!;
    final off = resolver(previews: null).resolve(_file('doc-svg'), _metrics)!;
    addTearDown(pdf.dispose);
    addTearDown(off.dispose);

    expect(producer.attempts, isEmpty);
    // The row with an icon: the icon row's height.
    expect(pdf.sizeHint, Size(style.width, style.iconRowHeight));
    final canvas = _Canvas();
    pdf.paint(
      canvas,
      Offset.zero & pdf.sizeHint,
      const InlineEmbedPaintContext(),
    );
    expect(canvas.paths, greaterThan(0));
    expect(canvas.paragraphs, 2);
  });

  test('the icon gives way to the drawing once it is here', () {
    final embed = resolver().resolve(_file('doc-svg'), _metrics)!;
    addTearDown(embed.dispose);
    final drawn = producer.last.advance(AssetStage.full);

    final canvas = _Canvas();
    embed.paint(
      canvas,
      const Offset(10, 20) & embed.sizeHint,
      const InlineEmbedPaintContext(),
    );

    expect(canvas.paths, 0);
    expect(
      drawn.paints.single.rect,
      const Offset(10, 20) & Size.square(style.thumbnailExtent),
    );
  });

  test('its text starts from the chrome\'s text root, at the row\'s sizes '
      'in the text\'s colour', () {
    final embed =
        resolver().resolve(_file('doc-pdf'), _metrics)! as DocumentEmbed;
    addTearDown(embed.dispose);

    final (:name, :info) = embed.textStylesFor(const Color(0xFF102030));

    expect(name.fontFamily, 'ChromeFace');
    expect(name.fontSize, style.nameSize);
    expect(name.fontWeight, FontWeight.bold);
    expect(name.color, const Color(0xFF102030));
    expect(info.fontFamily, 'ChromeFace');
    expect(info.fontSize, style.infoSize);
  });

  test('a document the host does not know shows its alternative text; '
      'other targets go on to the next resolver', () {
    expect(resolver().resolve(_file('missing'), _metrics), isNull);
    resolver().resolve(
      const InlineEmbedTarget(scheme: 'document', id: '1', alt: 'x'),
      _metrics,
    );

    expect(otherwise.asked.single.scheme, 'document');
  });

  group('the demo\'s documents', () {
    test('are bundled, so a preview draws from bytes already here, and '
        'the SVG one is a vector image', () {
      final diagram = DemoDocuments.document('diagram')!;
      final notes = DemoDocuments.document('notes')!;

      expect(BundledPacks.of(diagram.key)?.assetPath, isNotNull);
      expect(
        BundledPacks.describe(diagram.key)?.mediaForm,
        MediaForm.vectorImage,
      );
      expect(SvgDocumentPreview.isSvg(name: notes.name), isFalse);
      expect(DemoDocuments.document('missing'), isNull);
    });

    test('the showcase sends them as rows', () {
      expect(
        ShowcaseBodies.all.where((body) => body.contains('](file:')),
        isNotEmpty,
      );
    });
  });

  testWidgets('through the app\'s services the SVG document draws its own '
      'picture, from the bundle, with nothing downloaded', (tester) async {
    final services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    final host = ChatBodyHost(
      assets: services.assets,
      policy: ValueNotifier(const LargeEmojiPolicy(enabled: true)),
    );

    // The decode starts at the attach: in real time, where its worker runs.
    final embed = (await tester.runAsync(
      () async =>
          host.embedResolver.resolve(_file('diagram'), _metrics)!
              as DocumentEmbed,
    ))!;
    addTearDown(embed.dispose);
    final binding = embed.previewBinding!;
    await tester.runAsync(() async {
      for (var i = 0; i < 400 && !binding.readiness.isFinal; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    expect(binding.lastError, isNull);
    expect(binding.readiness.stage, AssetStage.full);
    expect(binding.transfer, isA<AssetTransfer$None>());
  });
}
