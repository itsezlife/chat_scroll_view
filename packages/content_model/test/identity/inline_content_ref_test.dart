import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

void main() {
  const key = ContentKey.document('42');

  test('carries the key and its plain-text alternative', () {
    const ref = InlineContentRef(key: key, alternativeText: '\u{1F600}');

    expect(ref.key, key);
    expect(ref.alternativeText, '\u{1F600}');
  });

  test('is a value of its key and alternative text', () {
    const ref = InlineContentRef(key: key, alternativeText: 'a');

    expect(ref, const InlineContentRef(key: key, alternativeText: 'a'));
    expect(
      ref.hashCode,
      const InlineContentRef(key: key, alternativeText: 'a').hashCode,
    );
    expect(ref, isNot(const InlineContentRef(key: key, alternativeText: 'b')));
    expect(
      ref,
      isNot(
        const InlineContentRef(
          key: ContentKey.document('43'),
          alternativeText: 'a',
        ),
      ),
    );
  });

  test('the same content with a different alternative is a different ref', () {
    // The alternative is what copy, selection and accessibility read, so two
    // refs that would read differently must not be interchangeable.
    expect(
      const InlineContentRef(key: key, alternativeText: ':)'),
      isNot(const InlineContentRef(key: key, alternativeText: '\u{1F600}')),
    );
  });

  test('requires an alternative: an empty one would erase the content from '
      'copied text', () {
    final empty = StringBuffer().toString();

    expect(
      () => InlineContentRef(key: key, alternativeText: empty),
      throwsA(isA<AssertionError>()),
    );
  });

  test('accepts any content key variant', () {
    for (final content in const <ContentKey>[
      ContentKey.unicode('\u{1F600}'),
      ContentKey.document('1'),
      ContentKey.external('e'),
    ]) {
      expect(InlineContentRef(key: content, alternativeText: 'x').key, content);
    }
  });

  test('toString names the key and the alternative', () {
    expect(
      const InlineContentRef(key: key, alternativeText: 'a').toString(),
      'InlineContentRef(ContentKey.document(42), a)',
    );
  });
}
