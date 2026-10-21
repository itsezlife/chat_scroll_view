/// `RichTextMarkdown.codec`: the same conversion as `encode` / `decode`, in
/// the shape of `dart:convert`, so it fuses with other codecs.
///
/// **Seam:** `RichTextMarkdown.codec`.
library;

import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:test/test.dart';

void main() {
  final text = RichText('a b c', const [
    Entity(0, 1, EntityKind.bold),
    Entity(2, 1, EntityKind.code),
  ]);

  test('encodes and decodes as the static functions do', () {
    expect(RichTextMarkdown.codec.encode(text), RichTextMarkdown.encode(text));
    expect(
      RichTextMarkdown.codec.decode('**a** b'),
      RichTextMarkdown.decode('**a** b'),
    );
  });

  test('inverted is the codec the other way', () {
    expect(
      RichTextMarkdown.codec.inverted.decode(
        RichTextMarkdown.codec.inverted.encode('**a**'),
      ),
      '**a**',
    );
  });

  test('fuses with utf8: a body as the bytes a file or socket carries', () {
    final bytes = RichTextMarkdown.codec.fuse(utf8);

    expect(bytes.decode(bytes.encode(text)), text);
    expect(bytes.encode(text), utf8.encode(RichTextMarkdown.encode(text)));
  });
}
