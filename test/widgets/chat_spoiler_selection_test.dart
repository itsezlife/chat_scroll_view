import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// A text selection that enters a hidden spoiler reveals its message, as the
/// reference clients do: the range would otherwise copy what the screen hides.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatSelectionController selection;

  setUp(() {
    selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.desktop(),
    );
  });
  tearDown(() => selection.dispose());

  // `a b c` is the rendered text; the spoiler covers `b`, at 2..3.
  void putSpoilerBody(int id) =>
      selection.putBody(id, Markdown.fromString('a ||b|| c'));

  MarkdownSelection range(int id, int from, int to) => MarkdownSelection(
    base: MarkdownPosition(documentId: id, blockIndex: 0, offset: from),
    extent: MarkdownPosition(documentId: id, blockIndex: 0, offset: to),
  );

  void select(int id, int from, int to) {
    expect(selection.armTextSelection(id), isTrue);
    // ignore: invalid_use_of_internal_member
    selection.markdownSelection.selection = range(id, from, to);
  }

  test('select all reveals the message and only that one', () {
    putSpoilerBody(1);
    putSpoilerBody(2);

    expect(selection.enterTextSelection(1), isTrue);

    expect(selection.spoilers.isRevealed(1), isTrue);
    expect(selection.spoilers.isRevealed(2), isFalse);
  });

  test('a range that covers the spoiler reveals it', () {
    putSpoilerBody(1);

    select(1, 0, 3);

    expect(selection.spoilers.isRevealed(1), isTrue);
  });

  test('a range that covers part of the spoiler reveals it', () {
    putSpoilerBody(1);

    select(1, 2, 3);

    expect(selection.spoilers.isRevealed(1), isTrue);
  });

  test('a range dragged backwards over the spoiler reveals it', () {
    putSpoilerBody(1);

    select(1, 5, 1);

    expect(selection.spoilers.isRevealed(1), isTrue);
  });

  test('a range that ends where the spoiler starts leaves it hidden', () {
    putSpoilerBody(1);

    select(1, 0, 2);

    expect(selection.spoilers.isRevealed(1), isFalse);
  });

  test('a range that starts where the spoiler ends leaves it hidden', () {
    putSpoilerBody(1);

    select(1, 3, 5);

    expect(selection.spoilers.isRevealed(1), isFalse);
  });

  test('a message with no spoiler stays as it was', () {
    selection.putBody(1, Markdown.fromString('plain words'));

    expect(selection.enterTextSelection(1), isTrue);

    expect(selection.spoilers.isRevealed(1), isFalse);
  });

  test('a spoiler in a later block is found by a range across blocks', () {
    selection.putBody(1, Markdown.fromString('one\n\ntwo ||three|| four'));
    expect(selection.armTextSelection(1), isTrue);

    // ignore: invalid_use_of_internal_member
    selection.markdownSelection.selection = const MarkdownSelection(
      base: MarkdownPosition(documentId: 1, blockIndex: 0, offset: 1),
      extent: MarkdownPosition(documentId: 1, blockIndex: 2, offset: 5),
    );

    expect(selection.spoilers.isRevealed(1), isTrue);
  });

  test('dismissing the selection does not hide the message again', () {
    putSpoilerBody(1);
    select(1, 0, 3);

    selection.clearTextSelection();

    expect(selection.spoilers.isRevealed(1), isTrue);
  });
}
