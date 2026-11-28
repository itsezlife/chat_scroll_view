import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:test/test.dart';

final _article = Uri.parse('https://example.org/article');
final _plain = Uri.parse('https://example.org/plain');
final _page = LinkPreview(url: _article, title: 'An article');

void main() {
  LinkPreviewResolverContract.run(() async {
    final resolver = FakeLinkPreviewResolver()..answer([_article], _page);
    return LinkPreviewResolverHarness(
      resolver: resolver,
      withPage: [_article],
      withoutPage: [_plain],
      settle: () async => resolver.completeAll(),
    );
  });

  group('FakeLinkPreviewResolver', () {
    test('answers the scripted list and none for any other', () {
      final resolver = FakeLinkPreviewResolver()
        ..answer([_plain, _article], _page);
      final scripted = resolver.resolve([_plain, _article]);
      final reordered = resolver.resolve([_article, _plain]);

      resolver.completeAll();

      expect(scripted.value, LinkPreviewState.loaded(_page));
      expect(reordered.value, LinkPreviewState.none);
    });

    test('a later answer replaces an earlier one', () {
      final resolver = FakeLinkPreviewResolver()
        ..answer([_article], _page)
        ..answer([_article], null);
      final request = resolver.resolve([_article]);

      resolver.completeAll();

      expect(request.value, LinkPreviewState.none);
    });

    test('stays pending until completed', () {
      final resolver = FakeLinkPreviewResolver()..answer([_article], _page);
      final request = resolver.resolve([_article]);

      expect(request.value, LinkPreviewState.pending);
      expect(resolver.pendingCount, 1);

      resolver.completeAll();

      expect(resolver.pendingCount, 0);
      expect(request.value, LinkPreviewState.loaded(_page));
    });

    test('records each call, repeats included', () {
      final resolver = FakeLinkPreviewResolver()
        ..resolve([_article])
        ..resolve([_article])
        ..resolve(const []);

      expect(resolver.calls, [
        [_article],
        [_article],
        <Uri>[],
      ]);
    });

    test('records a cancel of a pending request once', () {
      final resolver = FakeLinkPreviewResolver();
      final cancelled = resolver.resolve([_plain])
        ..cancel()
        ..cancel();
      final completed = resolver.resolve([_article]);
      resolver.completeAll();
      completed.cancel();

      expect(resolver.cancels, [
        [_plain],
      ]);
      expect(resolver.pendingCount, 0);
      expect(cancelled.value, LinkPreviewState.pending);
    });

    test('throws its failure from resolve', () {
      final resolver = FakeLinkPreviewResolver()..failure = Exception('broken');

      expect(() => resolver.resolve([_article]), throwsException);
      expect(resolver.calls, hasLength(1));
      expect(resolver.pendingCount, 0);
    });
  });
}
