import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

void main() {
  group('value equality', () {
    test('leaves with the same key and facts are equal', () {
      const a = CatalogLeaf(
        key: ContentKey.document('7'),
        semanticKind: SemanticKind.sticker,
        mediaForm: MediaForm.still,
        sizeHint: ContentSize(512, 512),
      );
      const b = CatalogLeaf(
        key: ContentKey.document('7'),
        semanticKind: SemanticKind.sticker,
        mediaForm: MediaForm.still,
        sizeHint: ContentSize(512, 512),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different key or any paint fact makes a different leaf', () {
      const base = CatalogLeaf(
        key: ContentKey.document('7'),
        semanticKind: SemanticKind.sticker,
        mediaForm: MediaForm.still,
      );

      expect(
        base,
        isNot(const CatalogLeaf(key: ContentKey.document('8'))),
        reason: 'key',
      );
      expect(
        base,
        isNot(
          const CatalogLeaf(
            key: ContentKey.document('7'),
            semanticKind: SemanticKind.gif,
            mediaForm: MediaForm.still,
          ),
        ),
        reason: 'semantic kind',
      );
      expect(
        base,
        isNot(
          const CatalogLeaf(
            key: ContentKey.document('7'),
            semanticKind: SemanticKind.sticker,
            mediaForm: MediaForm.video,
          ),
        ),
        reason: 'media form',
      );
      expect(
        base,
        isNot(
          const CatalogLeaf(
            key: ContentKey.document('7'),
            semanticKind: SemanticKind.sticker,
            mediaForm: MediaForm.still,
            sizeHint: ContentSize(64, 64),
          ),
        ),
        reason: 'size hint',
      );
      expect(
        base,
        isNot(
          const CatalogLeaf(
            key: ContentKey.document('7'),
            semanticKind: SemanticKind.sticker,
            mediaForm: MediaForm.still,
            tintable: true,
          ),
        ),
        reason: 'tintable',
      );
      expect(
        base,
        isNot(
          const CatalogLeaf(
            key: ContentKey.document('7'),
            semanticKind: SemanticKind.sticker,
            mediaForm: MediaForm.still,
            spokenName: 'thumbs up',
          ),
        ),
        reason: 'spoken name',
      );
    });

    test('the host tag is excluded from equality', () {
      final a = CatalogLeaf.unicode('😀', tag: 'recents');
      final b = CatalogLeaf.unicode('😀', tag: 42);
      final c = CatalogLeaf.unicode('😀');

      expect(a, b);
      expect(a, c);
      expect(a.hashCode, c.hashCode);
      expect(a.tag, 'recents');
      expect(c.tag, isNull);
    });
  });

  group('construction', () {
    test('a unicode leaf is a glyph emoji keyed by its sequence', () {
      final leaf = CatalogLeaf.unicode('👍🏽');

      expect(leaf.key, const ContentKey.unicode('👍🏽'));
      expect(leaf.mediaForm, MediaForm.glyph);
      expect(leaf.semanticKind, SemanticKind.unicodeEmoji);
    });

    test('a document leaf keeps what the host knows about it', () {
      final leaf = CatalogLeaf.document(
        '5368',
        semanticKind: SemanticKind.sticker,
        mediaForm: MediaForm.vectorAnimation,
      );

      expect(leaf.key, const ContentKey.document('5368'));
      expect(leaf.semanticKind, SemanticKind.sticker);
      expect(leaf.mediaForm, MediaForm.vectorAnimation);
    });

    test('a descriptor supplies key, paint facts and spoken name', () {
      const descriptor = ContentDescriptor(
        key: ContentKey.document('9'),
        semanticKind: SemanticKind.customEmoji,
        mediaForm: MediaForm.vectorAnimation,
        animated: true,
        tintable: true,
        size: ContentSize(100, 100),
        spokenName: 'wave',
      );

      final leaf = CatalogLeaf.fromDescriptor(descriptor, tag: 'x');

      expect(leaf.key, descriptor.key);
      expect(leaf.semanticKind, SemanticKind.customEmoji);
      expect(leaf.mediaForm, MediaForm.vectorAnimation);
      expect(leaf.animated, isTrue);
      expect(leaf.tintable, isTrue);
      expect(leaf.sizeHint, const ContentSize(100, 100));
      expect(leaf.spokenName, 'wave');
      expect(leaf.tag, 'x');
    });
  });

  group('semantic label', () {
    test('is the spoken name when there is one', () {
      expect(
        CatalogLeaf.unicode('👍', spokenName: 'thumbs up').semanticLabel,
        'thumbs up',
      );
      expect(
        CatalogLeaf.document('1', spokenName: 'wave').semanticLabel,
        'wave',
      );
    });

    test('falls back to the glyph itself for a unicode emoji', () {
      expect(CatalogLeaf.unicode('👍🏽').semanticLabel, '👍🏽');
    });

    test('is absent for other content with no spoken name', () {
      expect(CatalogLeaf.document('1').semanticLabel, isNull);
    });
  });

  group('placeholder style', () {
    test('is derived from the descriptor facts, never stored', () {
      expect(
        CatalogLeaf.unicode('😀').placeholderStyle,
        CatalogPlaceholderStyle.circle,
      );
      expect(
        CatalogLeaf.document(
          '1',
          semanticKind: SemanticKind.sticker,
        ).placeholderStyle,
        CatalogPlaceholderStyle.shapedWash,
      );
      expect(
        CatalogLeaf.document(
          '2',
          semanticKind: SemanticKind.customEmoji,
          mediaForm: MediaForm.vectorAnimation,
        ).placeholderStyle,
        CatalogPlaceholderStyle.thumbFirst,
      );
      expect(
        const CatalogLeaf(key: ContentKey.unicode('😀')).placeholderStyle,
        CatalogPlaceholderStyle.circle,
        reason: 'a unicode key is a glyph whatever the facts say',
      );
      expect(
        CatalogLeaf.document('3').placeholderStyle,
        CatalogPlaceholderStyle.thumbFirst,
        reason: 'unknown facts fall back to the thumbnail silhouette',
      );
    });
  });

  group('content box', () {
    test(
      'a sticker, mask or GIF fills its cell, anything else the glyph box',
      () {
        CatalogContentBox boxOf(SemanticKind kind) =>
            CatalogLeaf.document('1', semanticKind: kind).contentBox;

        expect(boxOf(SemanticKind.sticker), CatalogContentBox.cell);
        expect(boxOf(SemanticKind.mask), CatalogContentBox.cell);
        expect(boxOf(SemanticKind.gif), CatalogContentBox.cell);
        expect(boxOf(SemanticKind.customEmoji), CatalogContentBox.glyph);
        expect(boxOf(SemanticKind.unknown), CatalogContentBox.glyph);
        expect(CatalogLeaf.unicode('😀').contentBox, CatalogContentBox.glyph);
      },
    );

    test(
      'the extent is the glyph fraction or the shorter side of the cell',
      () {
        expect(
          catalogContentBoxExtent(CatalogContentBox.glyph, 80, 40),
          closeTo(28.8, 1e-9),
        );
        expect(catalogContentBoxExtent(CatalogContentBox.cell, 80, 40), 40);
        expect(catalogContentBoxExtent(CatalogContentBox.cell, 30, 40), 30);
      },
    );
  });

  group('hit identity', () {
    test('is the section id and index, not the leaf', () {
      final leaf = CatalogLeaf.unicode('😀');

      expect(
        CatalogLeafHit(sectionId: 'a', index: 2, leaf: leaf),
        CatalogLeafHit(
          sectionId: 'a',
          index: 2,
          leaf: CatalogLeaf.unicode('😀', tag: 'other'),
        ),
      );
      expect(
        CatalogLeafHit(sectionId: 'a', index: 2, leaf: leaf),
        isNot(CatalogLeafHit(sectionId: 'b', index: 2, leaf: leaf)),
        reason: 'the same key in another section is another hit',
      );
      expect(
        CatalogLeafHit(sectionId: 'a', index: 2, leaf: leaf),
        isNot(CatalogLeafHit(sectionId: 'a', index: 3, leaf: leaf)),
      );
    });
  });
}
