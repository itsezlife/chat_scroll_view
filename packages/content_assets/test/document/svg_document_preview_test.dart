import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';

const ContentKey _document = ContentKey.document('doc-7');

/// A policy that downloads everything, and says which context it was asked.
final class _Eager implements AutoDownloadPolicy {
  final asked = <AutoDownloadContext?>[];

  @override
  AutoDownload decide(
    MediaDescriptor descriptor,
    AutoDownloadContext? context,
  ) {
    asked.add(context);
    return AutoDownload.now;
  }

  @override
  AutoDownloadContext? get defaultContext => null;

  @override
  Listenable get changes => const _NoChanges();
}

final class _NoChanges implements Listenable {
  const _NoChanges();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

void main() {
  const preview = SvgDocumentPreview();

  group('an SVG document', () {
    test('is one by its type, or by its name when the type says nothing', () {
      expect(SvgDocumentPreview.isSvg(mimeType: 'image/svg+xml'), isTrue);
      expect(
        SvgDocumentPreview.isSvg(mimeType: 'Image/SVG+XML; charset=utf-8'),
        isTrue,
      );
      expect(SvgDocumentPreview.isSvg(name: 'Logo.SVG'), isTrue);
      expect(
        SvgDocumentPreview.isSvg(mimeType: 'image/png', name: 'a.png'),
        isFalse,
      );
      expect(SvgDocumentPreview.isSvg(name: 'a.svgz'), isFalse);
      expect(SvgDocumentPreview.isSvg(), isFalse);
    });

    test('is previewed as a vector image under its own key', () {
      final descriptor = preview.descriptorOf(
        _document,
        mimeType: 'image/svg+xml',
        byteSize: 2048,
      );

      expect(descriptor?.key, _document);
      expect(descriptor?.mediaForm, MediaForm.vectorImage);
      expect(descriptor?.byteSize, 2048);
    });

    test('is not previewed when it is not SVG, or larger than the input '
        'cap', () {
      expect(preview.descriptorOf(_document, name: 'a.pdf'), isNull);
      expect(
        preview.descriptorOf(
          _document,
          name: 'big.svg',
          byteSize: 1024 * 1024 + 1,
        ),
        isNull,
      );
      expect(
        preview.descriptorOf(_document, name: 'ok.svg', byteSize: 1024 * 1024),
        isNotNull,
      );
    });

    test('is drawn at the thumbnail\'s pixels, never past the preview\'s '
        'edge', () {
      final small = preview.presetOf(extent: 48, devicePixelRatio: 3);
      final large = preview.presetOf(extent: 400, devicePixelRatio: 3);

      expect(small.size, const Size.square(48));
      expect((small.spec.pixelWidth, small.spec.pixelHeight), (144, 144));
      expect((large.spec.pixelWidth, large.spec.pixelHeight), (960, 960));
    });
  });

  group('localOnly', () {
    test('answers manual for the preview\'s context, and the host\'s policy '
        'for every other', () {
      final eager = _Eager();
      final policy = SvgDocumentPreview.localOnly(eager);
      const media = MediaDescriptor(key: MediaKey.remote('doc-7'));

      expect(
        policy.decide(media, SvgDocumentPreview.downloadContext),
        AutoDownload.manual,
      );
      expect(
        policy.decide(media, AutoDownloadContext.groups),
        AutoDownload.now,
      );
      expect(eager.asked, [AutoDownloadContext.groups]);
    });

    test('a preview never starts a download; a document already here is '
        'drawn', () async {
      final fetcher = FakeFetcher()
        ..serve(
          const MediaKey.remote('far'),
          FetchedContent.bytes(Uint8List(4)),
        )
        ..serve(
          const MediaKey.remote('here'),
          FetchedContent.bytes(Uint8List(4)),
        )
        ..missing.add(const MediaKey.remote('far'));
      final pipeline = AssetPipeline(
        fetcher: fetcher,
        decoders: DecoderRegistry()
          ..register(MediaKind.vectorImage, FakeDecoder()),
      );
      final scope = AssetCacheScope(
        producer: pipeline,
        clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
        autoDownload: SvgDocumentPreview.localOnly(_Eager()),
      );
      addTearDown(() {
        scope.dispose();
        pipeline.dispose();
      });
      for (final id in ['far', 'here']) {
        pipeline.know(
          preview
              .descriptorOf(ContentKey.document(id), name: '$id.svg')!
              .mediaDescriptor!,
        );
      }
      final shown = preview.presetOf(extent: 48, devicePixelRatio: 1);

      AssetBinding attach(String id) => scope.attach(
        MediaKey.remote(id),
        shown.spec,
        shown.profile,
        downloadContext: SvgDocumentPreview.downloadContext,
      );
      final far = attach('far');
      final here = attach('here');
      for (var i = 0; i < 100 && !here.readiness.isFinal; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(here.readiness.stage, AssetStage.full);
      expect(far.readiness.stage, AssetStage.none);
      expect(far.transfer, isA<AssetTransfer$AwaitingUser>());
      expect(
        fetcher.fetches.where(
          (f) => f.request.descriptor.key == const MediaKey.remote('far'),
        ),
        isEmpty,
      );
      far.detach();
      here.detach();
    });
  });
}
