/// The link preview header strip: the page drawn compactly, the open action
/// with the strip's rect, the input guard on its taps and the mouse hover
/// report.
///
/// **Seam:** `ComposerHeaderStrip` over a `ComposerHeader.linkPreview`, under
/// the composer's scopes.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/view/composer_header_strip.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' as model;
import 'package:content_model/content_model.dart' hide RichText;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');

final _page = LinkPreview(
  url: _url,
  siteName: 'Example News',
  title: 'A story',
  description: const model.RichText.plain('What happened today'),
  photo: const ContentDescriptor(key: ContentKey.external('p')),
);

Future<void> _show(WidgetTester tester, ComposerHeader header) =>
    tester.pumpWidget(composerHarness(ComposerHeaderStrip(header: header)));

void main() {
  testWidgets('a loaded page shows its site name and title', (tester) async {
    await _show(tester, ComposerHeader.linkPreview(url: _url, page: _page));

    expect(find.text('Example News'), findsOneWidget);
    expect(find.text('A story'), findsOneWidget);
    expectChromeText(tester, within: find.byType(ComposerHeaderStrip));
  });

  testWidgets('without a site name: the title, then the description', (
    tester,
  ) async {
    await _show(
      tester,
      ComposerHeader.linkPreview(
        url: _url,
        page: LinkPreview(
          url: _url,
          title: 'A story',
          description: const model.RichText.plain('What happened today'),
        ),
      ),
    );

    expect(find.text('A story'), findsOneWidget);
    expect(find.text('What happened today'), findsOneWidget);
  });

  testWidgets('while pending: the host and the address', (tester) async {
    await _show(tester, ComposerHeader.linkPreview(url: _url));

    expect(find.text('news.example'), findsOneWidget);
    expect(find.text(_url.toString()), findsOneWidget);
    expectChromeText(tester, within: find.byType(ComposerHeaderStrip));
  });

  testWidgets('the host builds the thumbnail of a page with a photo', (
    tester,
  ) async {
    final asked = <(LinkPreview, Size)>[];
    await _show(
      tester,
      ComposerHeader.linkPreview(
        url: _url,
        page: _page,
        thumbnail: (context, page, size) {
          asked.add((page, size));
          return const ColoredBox(
            key: ValueKey('thumb'),
            color: Color(0xFF00FF00),
          );
        },
      ),
    );

    expect(find.byKey(const ValueKey('thumb')), findsOneWidget);
    expect(asked.single.$1, _page);
    expect(
      tester.getSize(find.byKey(const ValueKey('thumb'))),
      asked.single.$2,
    );
  });

  testWidgets('a tap opens with the strip rect, once per guard window', (
    tester,
  ) async {
    final opened = <Rect>[];
    await _show(
      tester,
      ComposerHeader.linkPreview(url: _url, page: _page, onOpen: opened.add),
    );

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('A story'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(opened, hasLength(1));
    expect(opened.single, tester.getRect(find.byType(ComposerHeaderStrip)));

    await tester.pump(ComposerHeaderStrip.tapGuard);
    await tester.tap(find.text('A story'));
    await tester.pump();
    expect(opened, hasLength(2));
  });

  testWidgets('the cross dismisses once per guard window', (tester) async {
    var dismissed = 0;
    await _show(
      tester,
      ComposerHeader.linkPreview(
        url: _url,
        page: _page,
        onOpen: (_) {},
        onDismiss: () => dismissed++,
      ),
    );
    final cross = find.bySemanticsLabel('Cancel');

    for (var i = 0; i < 4; i++) {
      await tester.tap(cross);
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(dismissed, 1);

    await tester.pump(ComposerHeaderStrip.tapGuard);
    await tester.tap(cross);
    await tester.pump();
    expect(dismissed, 2);
  });

  testWidgets('a mouse coming on reports the strip rect, leaving reports '
      'null; a pen hovering reports nothing', (tester) async {
    final hovers = <Rect?>[];
    await _show(
      tester,
      ComposerHeader.linkPreview(url: _url, page: _page, onHover: hovers.add),
    );
    final strip = tester.getRect(find.byType(ComposerHeaderStrip));

    final pen = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await pen.addPointer(location: const Offset(1, 1));
    await pen.moveTo(strip.center);
    await pen.moveTo(const Offset(1, 1));
    await pen.removePointer();
    await tester.pump();
    expect(hovers, isEmpty);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(strip.center);
    await tester.pump();
    await mouse.moveTo(const Offset(1, 1));
    await tester.pump();
    await mouse.removePointer();

    expect(hovers, [strip, null]);
  });
}
