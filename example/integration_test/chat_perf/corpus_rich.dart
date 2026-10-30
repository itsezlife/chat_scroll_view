/// The `rich` content profile of the suite's corpus (spec 7.4): designated
/// target messages at fixed ids, a markdown-heavy region and a code-heavy
/// region. Pure Dart; every text is a function of its id alone.
library;

/// A designated message a selection script aims at. Its id is fixed, so the
/// same characters are targeted on every launch.
enum BenchTarget {
  /// A plain paragraph of several lines: long-press and text-drag target.
  plainParagraph(1000),

  /// A line that is one link: the link-tap target (and the row next to the
  /// paragraph, so one seat shows both).
  linkLine(1001),

  /// A fenced code block of at least 75 characters, so the mobile policy
  /// paints the bottom copy bar.
  fencedCode(1010),

  /// A long markdown block: headings, a list, a quote and inline styles.
  longMarkdown(1020),

  /// One paragraph taller than any phone viewport: the edge autoscroll of a
  /// text drag only runs while the subject has more of itself to reveal.
  tallParagraph(1030);

  const BenchTarget(this.id);

  /// The message id.
  final int id;
}

/// Ids of the markdown-heavy region, `[first, last)`.
const (int, int) kMarkdownRegion = (2000, 2400);

/// Ids of the code-heavy region, `[first, last)`.
const (int, int) kCodeRegion = (3000, 3400);

/// Ids of the plain region the rich flings are compared with, `[first, last)`.
/// These are ordinary corpus messages, drawn as plain text.
const (int, int) kPlainRegion = (4000, 4400);

/// One past the highest id the rich profile designates: a history shorter than
/// this has no complete rich profile.
const int kRichProfileExtent = 4400;

/// The markdown source of message [id] in the `rich` profile, or null when the
/// profile leaves it to the plain generator.
String? richTextOf(int id) {
  for (final t in BenchTarget.values) {
    if (t.id == id) return _targetText(t);
  }
  if (id >= kMarkdownRegion.$1 && id < kMarkdownRegion.$2) {
    return _markdownBlock(id);
  }
  if (id >= kCodeRegion.$1 && id < kCodeRegion.$2) return _codeBlock(id);
  return null;
}

String _targetText(BenchTarget target) => switch (target) {
  BenchTarget.plainParagraph =>
    'The first rule of the bench is that every launch selects the same '
        'characters. The second rule of the bench is that a paragraph must '
        'run over several lines so a drag can cross a line break. The third '
        'rule is that nothing in it is a link, a code span or a spoiler.',
  BenchTarget.linkLine => '[Flutter documentation](https://docs.flutter.dev)',
  BenchTarget.fencedCode =>
    '```dart\n'
        'Future<void> main() async {\n'
        '  final controller = ChatScrollController();\n'
        '  controller.jumpTo(1010, alignment: 0.5);\n'
        '}\n'
        '```',
  BenchTarget.longMarkdown => _markdownBlock(BenchTarget.longMarkdown.id),
  BenchTarget.tallParagraph => [
    for (var i = 1; i <= 240; i++)
      'Sentence $i of the tall paragraph keeps the block going.',
  ].join(' '),
};

String _markdownBlock(int id) =>
    '''
## Release notes $id

The **anchor viewport** lays out from one message, so a *long* history costs
the same as a short one. See the [layout notes](https://example.com/$id) and
the `fanOut` pass for the detail.

- first item with `inline code` and **bold** words
- second item with a [link](https://example.com/item/$id)
- third item that wraps over more than one line when the bubble is narrow

> A quoted paragraph for message $id that also wraps over a second line.

1. step one
2. step two
3. step three''';

String _codeBlock(int id) =>
    '''
Snippet $id:

```dart
class Counter$id {
  int _value = $id;

  void increment() {
    _value++;
  }

  int get value => _value;
}
```''';
