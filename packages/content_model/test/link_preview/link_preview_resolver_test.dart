import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

final _page = LinkPreview(url: Uri.parse('https://example.org/a'));

void main() {
  group('LinkPreviewState', () {
    test('only loaded and none are terminal', () {
      expect(LinkPreviewState.pending.isTerminal, isFalse);
      expect(LinkPreviewState.loaded(_page).isTerminal, isTrue);
      expect(LinkPreviewState.none.isTerminal, isTrue);
    });

    test('loaded is equal by its page', () {
      expect(LinkPreviewState.loaded(_page), LinkPreviewState.loaded(_page));
      expect(
        LinkPreviewState.loaded(_page),
        isNot(
          LinkPreviewState.loaded(
            LinkPreview(url: Uri.parse('https://example.org/b')),
          ),
        ),
      );
    });

    test('toString shows the host only', () {
      final state = LinkPreviewState.loaded(
        LinkPreview(
          url: Uri.parse('https://example.org/secret?q=1'),
          title: 'Title',
        ),
      );

      expect(state.toString(), isNot(contains('secret')));
      expect(state.toString(), isNot(contains('Title')));
    });
  });

  group('LinkPreviewCompleter', () {
    test('its request starts pending', () {
      final completer = LinkPreviewCompleter();

      expect(completer.request.value, LinkPreviewState.pending);
      expect(completer.isSettled, isFalse);
    });

    test('completes to loaded with one notification', () {
      final completer = LinkPreviewCompleter();
      final seen = <LinkPreviewState>[];
      completer.request.addListener(() => seen.add(completer.request.value));

      completer.complete(_page);

      expect(seen, [LinkPreviewState.loaded(_page)]);
      expect(completer.isSettled, isTrue);
    });

    test('completes to none without a page', () {
      final completer = LinkPreviewCompleter()..complete(null);

      expect(completer.request.value, LinkPreviewState.none);
    });

    test('ignores a second complete', () {
      final completer = LinkPreviewCompleter()..complete(null);
      var notified = 0;
      completer.request.addListener(() => notified++);

      completer.complete(_page);

      expect(completer.request.value, LinkPreviewState.none);
      expect(notified, 0);
    });

    test('runs onCancel once, for a pending request only', () {
      var cancels = 0;
      final completer = LinkPreviewCompleter(onCancel: () => cancels++);

      completer.request
        ..cancel()
        ..cancel();

      expect(cancels, 1);
      expect(completer.isCancelled, isTrue);
      expect(completer.isSettled, isTrue);
    });

    test('a complete after cancel is ignored', () {
      final completer = LinkPreviewCompleter();
      var notified = 0;
      completer.request
        ..addListener(() => notified++)
        ..cancel();

      completer.complete(_page);

      expect(completer.request.value, LinkPreviewState.pending);
      expect(notified, 0);
    });

    test('a cancel after complete does not run onCancel', () {
      var cancels = 0;
      final completer = LinkPreviewCompleter(onCancel: () => cancels++)
        ..complete(_page);

      completer.request.cancel();

      expect(cancels, 0);
      expect(completer.isCancelled, isFalse);
      expect(completer.request.value, LinkPreviewState.loaded(_page));
    });
  });
}
