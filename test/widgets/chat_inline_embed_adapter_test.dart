import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_inline_embed_adapter.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

const _metrics = MarkdownInlineEmbedMetrics(
  fontSize: 16,
  ascent: 15,
  descent: 4,
  devicePixelRatio: 2,
);

const _target = MarkdownInlineEmbedTarget(
  scheme: 'fake',
  id: '7',
  alt: ':wave:',
);

/// The adapter is the one place `catalog_assets`' embed seam meets the
/// markdown library's: every test here reads the library's side of it.
void main() {
  late FakeInlineEmbedResolver resolver;
  late ChatInlineEmbedAdapter adapter;

  setUp(() {
    resolver = FakeInlineEmbedResolver();
    adapter = ChatInlineEmbedAdapter(resolver);
  });

  test('hands the resolver the target as it came', () {
    adapter.resolve(_target, _metrics);

    expect(resolver.asked, [
      const InlineEmbedTarget(scheme: 'fake', id: '7', alt: ':wave:'),
    ]);
  });

  test('reserves the size the embed asked for', () {
    final embed = adapter.resolve(_target, _metrics)!;

    expect(embed.size, resolver.made.single.sizeHint);
    // The fake sizes itself 1.2 * (ascent + descent): the metrics arrived.
    expect(embed.size, const Size.square(1.2 * (15 + 4)));
  });

  test('is null where the resolver does not know the scheme', () {
    const unknown = MarkdownInlineEmbedTarget(
      scheme: 'other',
      id: '1',
      alt: 'x',
    );

    expect(adapter.resolve(unknown, _metrics), isNull);
  });

  test('is null for a font with no ascent or no descent', () {
    const flat = MarkdownInlineEmbedMetrics(
      fontSize: 16,
      ascent: 0,
      descent: 0,
      devicePixelRatio: 1,
    );

    expect(adapter.resolve(_target, flat), isNull);
    expect(resolver.asked, isEmpty, reason: 'nothing to size an embed by');
  });

  test('paints the embed into the rectangle with the tint and opacity', () {
    final embed = adapter.resolve(_target, _metrics)!;
    const rect = Rect.fromLTWH(3, 4, 20, 20);
    const tint = Color(0xFF123456);

    embed.paint(
      Canvas(PictureRecorder()),
      rect,
      const MarkdownInlineEmbedPaintContext(tint: tint, opacity: 0.5),
    );

    final painted = resolver.made.single.paints.single;
    expect(painted.rect, rect);
    expect(painted.context.tint, tint);
    expect(painted.context.opacity, 0.5);
  });

  test('forwards visible both ways', () {
    final embed = adapter.resolve(_target, _metrics)!;
    expect(embed.visible, isTrue);

    embed.visible = false;

    expect(resolver.made.single.visible, isFalse);
  });

  test('forwards the embed\'s signal to a listener and stops on remove', () {
    final embed = adapter.resolve(_target, _metrics)!;
    var heard = 0;
    void listener() => heard++;

    embed.addListener(listener);
    resolver.made.single.invalidate();
    embed.removeListener(listener);
    resolver.made.single.invalidate();

    expect(heard, 1);
  });

  test('disposes the embed, once however often it is asked', () {
    final embed = adapter.resolve(_target, _metrics)!;

    embed
      ..dispose()
      ..dispose();

    expect(resolver.made.single.disposals, 1);
  });

  test('each resolve is an embed of its own', () {
    final a = adapter.resolve(_target, _metrics)!;
    final b = adapter.resolve(_target, _metrics)!;

    a.dispose();

    expect(resolver.made[0].isDisposed, isTrue);
    expect(resolver.made[1].isDisposed, isFalse);
    b.dispose();
  });
}
