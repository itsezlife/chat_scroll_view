/// The content library's lists as the panel shows them: caught up when the
/// host commits, except for what leaves the library, which leaves at once,
/// and an edit the user asked for, which shows at once.
///
/// **Seam:** [DeferredLibraryView] over a `FakeContentLibrary` edited through
/// its `apply` or the view's `apply` and `record`, observed through the
/// view's lists and their signals.
library;

import 'package:chat_scroll_view_example/src/features/chat/data/deferred_library_view.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = ContentKey.document('a');
const _b = ContentKey.document('b');
const _c = ContentKey.document('c');

void main() {
  late FakeContentLibrary library;
  late DeferredLibraryView view;

  setUp(() {
    library = FakeContentLibrary(
      limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
      initial: LibraryState(
        recentStickers: const [_a, _b],
        favouriteStickers: const [_c],
        savedGifs: const [_b],
      ),
    );
    view = DeferredLibraryView(library);
    addTearDown(() {
      view.dispose();
      library.dispose();
    });
  });

  test('shows what the library holds when it is made', () {
    expect(view.recentStickers.value, [_a, _b]);
    expect(view.favouriteStickers.value, [_c]);
    expect(view.savedGifs.value, [_b]);
  });

  test('shows a key added or moved only once the host commits', () {
    var signals = 0;
    view.recentStickers.addListener(() => signals++);

    library
      ..apply(const LibraryEdit.addRecentSticker(_b))
      ..apply(const LibraryEdit.addRecentSticker(_c))
      ..apply(const LibraryEdit.favouriteSticker(_a))
      ..apply(const LibraryEdit.saveGif(_a));

    expect(view.recentStickers.value, [_a, _b]);
    expect(view.favouriteStickers.value, [_c]);
    expect(view.savedGifs.value, [_b]);
    expect(signals, 0);

    view.commit();

    expect(view.recentStickers.value, [_c, _b, _a]);
    expect(view.favouriteStickers.value, [_a, _c]);
    expect(view.savedGifs.value, [_a, _b]);
    expect(signals, 1);
  });

  test('a commit with nothing new signals nothing', () {
    var signals = 0;
    view.recentStickers.addListener(() => signals++);
    view.favouriteStickers.addListener(() => signals++);
    view.savedGifs.addListener(() => signals++);

    view.commit();

    expect(signals, 0);
  });

  test('takes a key that left the library out at once, and nothing else '
      'moves', () {
    library
      ..apply(const LibraryEdit.addRecentSticker(_c))
      ..apply(const LibraryEdit.removeRecentSticker(_b))
      ..apply(const LibraryEdit.unfavouriteSticker(_c))
      ..apply(const LibraryEdit.unsaveGif(_b));

    // _c was added to the recents and is not shown yet; _b left them.
    expect(view.recentStickers.value, [_a]);
    expect(view.favouriteStickers.value, isEmpty);
    expect(view.savedGifs.value, isEmpty);
  });

  test('records a send in the library and shows it only once the host '
      'commits', () {
    view
      ..record(const LibraryEdit.addRecentSticker(_c))
      ..record(const LibraryEdit.saveGif(_a));

    expect(library.recentStickers.value, [_c, _a, _b]);
    expect(library.savedGifs.value, [_a, _b]);
    expect(view.recentStickers.value, [_a, _b]);
    expect(view.savedGifs.value, [_b]);

    view.commit();

    expect(view.recentStickers.value, [_c, _a, _b]);
    expect(view.savedGifs.value, [_a, _b]);
  });

  test('shows an edit the user asked for at once: the key first, the sends '
      'still waiting', () {
    var signals = 0;
    view.favouriteStickers.addListener(() => signals++);
    view
      ..record(const LibraryEdit.saveGif(_c))
      ..apply(const LibraryEdit.favouriteSticker(_a))
      ..apply(const LibraryEdit.saveGif(_a));

    expect(library.favouriteStickers.value, [_a, _c]);
    expect(view.favouriteStickers.value, [_a, _c]);
    expect(signals, 1);
    // _c, sent, waits; _a, saved, is first.
    expect(view.savedGifs.value, [_a, _b]);
    expect(view.recentStickers.value, [_a, _b]);
  });

  test('moves a key the user saves again to the front at once', () {
    library.apply(const LibraryEdit.saveGif(_a));
    view.commit();

    view.apply(const LibraryEdit.saveGif(_b));

    expect(view.savedGifs.value, [_b, _a]);
  });

  test('takes out at once what the user removes, and nothing else moves', () {
    view
      ..record(const LibraryEdit.addRecentSticker(_c))
      ..apply(const LibraryEdit.removeRecentSticker(_b))
      ..apply(const LibraryEdit.unfavouriteSticker(_c))
      ..apply(const LibraryEdit.unsaveGif(_b));

    expect(view.recentStickers.value, [_a]);
    expect(view.favouriteStickers.value, isEmpty);
    expect(view.savedGifs.value, isEmpty);
  });

  test('stops following the library once disposed', () {
    view.dispose();
    library.apply(const LibraryEdit.removeRecentSticker(_a));
    view.commit();

    expect(view.recentStickers.value, [_a, _b]);
  });
}
