/// The web policy: boxes by the window's width class, the browser's
/// operating system's family for the rest, an instant re-layout, and the
/// `media` / `webClassChanged` report of a class change.
///
/// **Seam:** `MessageMediaPolicy.web` laid out on `MediaLayoutInput`s of
/// several window sizes; `MessageMediaView` in a resized test window,
/// observed through `RecordingDiagnostics`.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/testing.dart' hide RecordingDiagnostics;

import '../support/media_scopes.dart';

MediaItem _photo(String id, {int width = 1280, int height = 720}) => MediaItem(
  id: MediaItemId(id),
  kind: MediaItemKind.photo,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    size: ContentSize(width, height),
  ),
);

MediaLayoutInput _window(
  double width, {
  List<MediaItem>? items,
  MediaLinkPreviewInput? linkPreview,
}) => MediaLayoutInput(
  text: MediaScopes.text,
  items: items ?? [_photo('a')],
  availableWidth: width,
  displaySize: Size(width, 800),
  linkPreview: linkPreview,
);

void main() {
  group('the policy', () {
    test('takes the browser operating system\'s family, the web boxes, '
        'the web gestures and no transition', () {
      for (final (platform, family) in const [
        (TargetPlatform.android, MessageMediaPlatform.android),
        (TargetPlatform.iOS, MessageMediaPlatform.ios),
        (TargetPlatform.macOS, MessageMediaPlatform.desktop),
        (TargetPlatform.windows, MessageMediaPlatform.desktop),
      ]) {
        final web = MessageMediaPolicy.web(platform: platform);
        final native = MessageMediaPolicy.forPlatform(platform);
        expect(web.isWeb, isTrue);
        expect(web.family, family);
        expect(
          (web.layoutStep as MediaLayoutPolicy).box,
          isA<MediaBoxSizing$Web>(),
        );
        expect(
          (web.layoutStep as MediaLayoutPolicy).mosaicAlgorithm,
          same((native.layoutStep as MediaLayoutPolicy).mosaicAlgorithm),
        );
        expect(web.gestures, const MediaGesturePolicy.web());
        expect(web.transition, const MediaTransitionPolicy.none());
        expect(web.linkPreview.width, LinkPreviewCardWidth.fitMedia);
        expect(web.fileStack, same(native.fileStack));
        expect(web.corners, same(native.corners));
        expect(native.isWeb, isFalse);
      }
    });

    test('the web gestures: hover and the click cursor for a mouse only', () {
      const gestures = MediaGesturePolicy.web();
      expect(gestures.loadingTap, MediaLoadingTap.anywhere);
      expect(gestures.clickCursor, isTrue);
      expect(gestures.hover, const MediaHoverLook());
      expect(gestures.hoverNeedsMouse, isTrue);
      expect(const MediaGesturePolicy.desktop().hoverNeedsMouse, isFalse);
    });

    test('platform() is the web policy in a browser only', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(MessageMediaPolicy.platform().isWeb, kIsWeb);
      expect(MessageMediaPolicy.web().family, MessageMediaPlatform.android);
    });

    test('a resize across 600 re-lays the media out', () {
      final policy = MessageMediaPolicy.web(platform: TargetPlatform.macOS);
      final compact = policy.layout(_window(600));
      final medium = policy.layout(_window(601));
      expect(compact.size, const Size(340, 191));
      expect(medium.size, const Size(420, 236));
      expect(compact, isNot(medium));
      expect(policy.layout(_window(400)).size, compact.size);
    });

    test('an album is 340 wide compact and 420 otherwise', () {
      final policy = MessageMediaPolicy.web(platform: TargetPlatform.android);
      final album = [_photo('a'), _photo('b')];
      expect(policy.layout(_window(400, items: album)).size.width, 340);
      expect(policy.layout(_window(1000, items: album)).size.width, 420);
    });

    test('a card\'s large media fits 340 x 200 compact, 420 x 380 '
        'otherwise', () {
      final policy = MessageMediaPolicy.web(platform: TargetPlatform.iOS);
      MediaLayoutInput card(double width) => _window(
        width,
        items: const [],
        linkPreview: MediaLinkPreviewInput(
          messageId: 'm1',
          page: LinkPreview(
            url: Uri.parse('https://example.org/'),
            title: 'T',
            photo: const ContentDescriptor(
              key: ContentKey.document('page'),
              size: ContentSize(720, 1280),
            ),
          ),
        ),
      );
      MediaCell mediaOf(MediaLayout layout) =>
          layout.blocks.whereType<MediaBlock$LinkPreview>().single.media!;
      expect(mediaOf(policy.layout(card(590))).rect.size, const Size(112, 200));
      expect(
        mediaOf(policy.layout(card(1000))).rect.size,
        const Size(213, 380),
      );
    });
  });

  group('webClassChanged', () {
    late ContentAssetScope scope;
    late RecordingDiagnostics diagnostics;
    late MessageMediaState state;

    setUp(() {
      scope = ContentAssetScope.withMedia(producer: FakeAssetProducer());
      diagnostics = RecordingDiagnostics.install();
      state = MessageMediaState();
      addTearDown(scope.dispose);
      addTearDown(state.dispose);
    });

    Future<void> pump(WidgetTester tester, MessageMediaPolicy policy) {
      final items = [_photo('a')];
      return tester.pumpWidget(
        ChromeInputClassScope(
          child: MediaScopes.wrap(
            Directionality(
              textDirection: TextDirection.ltr,
              child: ContentAssetProvider(
                scope: scope,
                child: MessageMediaStateScope(
                  state: state,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final id in ['1', '2'])
                          MessageMediaView(
                            layout: policy.layout(_window(400, items: items)),
                            items: items,
                            policy: policy,
                            correlation: ChatCorrelation(
                              chatId: 'chat-1',
                              scrollId: id,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    void resize(WidgetTester tester, double width) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = Size(width, 1600);
    }

    testWidgets('a resize across a bound reports the classes once per chat', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      resize(tester, 500);
      await pump(
        tester,
        MessageMediaPolicy.web(platform: TargetPlatform.macOS),
      );
      expect(diagnostics.whereOp(MediaOp.webClassChanged), isEmpty);

      resize(tester, 560);
      await tester.pump();
      expect(diagnostics.whereOp(MediaOp.webClassChanged), isEmpty);

      resize(tester, 800);
      await tester.pump();
      final event = diagnostics.whereOp(MediaOp.webClassChanged).single;
      expect(event.level, ChatEventLevel.debug);
      expect(event.category, ChatEventCategory.media);
      expect(event.correlation.chatId, 'chat-1');
      expect(event.fields, {
        'from': 'compact',
        'to': 'medium',
        // No input class scope: the platform's class, touch for the
        // test's Android.
        'input': 'touch',
      });

      resize(tester, 1200);
      await tester.pump();
      expect(
        diagnostics.whereOp(MediaOp.webClassChanged).last.fields,
        containsPair('to', 'expanded'),
      );
      expect(diagnostics.whereOp(MediaOp.webClassChanged), hasLength(2));
    });

    testWidgets('a change of the input class reports the classes', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      resize(tester, 500);
      await pump(
        tester,
        MessageMediaPolicy.web(platform: TargetPlatform.macOS),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();

      expect(diagnostics.whereOp(MediaOp.webClassChanged).single.fields, {
        'from': 'compact',
        'to': 'compact',
        'input': 'mouse',
      });
    });

    testWidgets('a policy that is not the web never reports', (tester) async {
      addTearDown(tester.view.reset);
      resize(tester, 500);
      await pump(tester, const MessageMediaPolicy.desktop());
      resize(tester, 800);
      await tester.pump();
      expect(diagnostics.whereOp(MediaOp.webClassChanged), isEmpty);
    });
  });
}
