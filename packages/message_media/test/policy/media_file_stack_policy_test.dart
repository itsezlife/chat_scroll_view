/// The file stack through `MessageMediaPolicy.layout`: each platform's row
/// geometry, bubble width, stacking, time, caption slots and footer.
///
/// **Seam:** `MessageMediaPolicy.layout` with the file stack's text measure
/// replaced by a fixed one (10 per name glyph, 6 per info glyph), so the
/// numbers do not depend on a font.
library;

import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

/// A measure of fixed glyph widths: a name glyph is 10 wide and its line
/// 20 high, an info glyph 6 wide and its line 16 high.
final class _FixedMeasure implements MediaFileTextMeasure {
  const _FixedMeasure();

  @override
  MediaFileTextSize name(
    String text,
    MediaFileText type, {
    required double maxWidth,
    required int maxLines,
  }) {
    final natural = text.length * 10.0;
    final lines = maxWidth.isInfinite || natural <= maxWidth
        ? 1
        : (natural / maxWidth).ceil().clamp(1, maxLines);
    return MediaFileTextSize(
      width: lines == 1 ? natural : maxWidth,
      height: lines * 20.0,
      lines: lines,
    );
  }

  @override
  MediaFileTextSize info(String text, MediaFileText type) =>
      MediaFileTextSize(width: text.length * 6.0, height: 16);
}

MessageMediaPolicy _fixed(MessageMediaPolicy policy) {
  final step = policy.layoutStep as MediaLayoutPolicy;
  return policy.copyWith(
    layoutStep: step.copyWith(
      fileStack: step.fileStack.copyWith(measure: const _FixedMeasure()),
    ),
  );
}

final _android = _fixed(const MessageMediaPolicy.android());
final _ios = _fixed(const MessageMediaPolicy.ios());
final _desktop = _fixed(const MessageMediaPolicy.desktop());

/// A file "a.pdf" of 2048 bytes (info "2.0 KB PDF" on Android, "2.0 KB"
/// elsewhere), or [name] / [mimeType] as given.
MediaItem _file(
  String id, {
  String name = 'a.pdf',
  String? mimeType,
  int? byteSize = 2048,
}) => MediaItem(
  id: MediaItemId(id),
  kind: MediaItemKind.file,
  descriptor: ContentDescriptor(
    key: ContentKey.document(id),
    fileName: name,
    mimeType: mimeType,
    byteSize: byteSize,
  ),
);

MediaItem _image(String id) => _file(id, name: 'b.png', mimeType: 'image/png');

MediaLayoutInput _input(
  List<MediaItem> items, {
  double availableWidth = 364,
  bool showsAvatar = false,
  MediaCaptionPosition captionPosition = MediaCaptionPosition.none,
  double? captionWidth,
  Map<MediaItemId, double> fileCaptionHeights = const {},
  MediaLayoutChrome chrome = MediaLayoutChrome.none,
}) => MediaLayoutInput(
  items: items,
  availableWidth: availableWidth,
  showsAvatar: showsAvatar,
  captionPosition: captionPosition,
  captionWidth: captionWidth,
  fileCaptionHeights: fileCaptionHeights,
  chrome: chrome,
  correlation: const ChatCorrelation(chatId: 'chat', scrollId: 'm1'),
);

MediaBlock$FileStack _stack(
  MessageMediaPolicy policy,
  MediaLayoutInput input,
) => policy.layout(input).blocks.single as MediaBlock$FileStack;

MediaFileRow _row(MediaBlock$FileStack block, String id) =>
    block.rowOf(MediaItemId(id))!;

Rect _cell(MediaBlock$FileStack block, String id) =>
    block.cells.singleWhere((cell) => cell.itemId == MediaItemId(id)).rect;

void main() {
  group('thumbnail', () {
    test('an image, an mp4 video or a carried thumbnail gives a thumbnail', () {
      expect(MediaFileStackPolicy.hasThumbnail(_image('i')), isTrue);
      expect(
        MediaFileStackPolicy.hasThumbnail(
          _file('v', name: 'v.mp4', mimeType: 'video/mp4'),
        ),
        isTrue,
      );
      expect(
        MediaFileStackPolicy.hasThumbnail(
          MediaItem(
            id: const MediaItemId('t'),
            kind: MediaItemKind.file,
            descriptor: const ContentDescriptor(
              key: ContentKey.document('t'),
              thumbnail: ThumbnailRef('t-thumb'),
            ),
          ),
        ),
        isTrue,
      );
      expect(
        MediaFileStackPolicy.hasThumbnail(
          _file('w', name: 'w.webm', mimeType: 'video/webm'),
        ),
        isFalse,
      );
      expect(MediaFileStackPolicy.hasThumbnail(_file('p')), isFalse);
    });
  });

  group('Android', () {
    test('a single file without a thumbnail', () {
      final block = _stack(_android, _input([_file('f')]));
      final row = _row(block, 'f');
      // The max text width (the list's 364), the row 56 + 4 for the time
      // beside the info line.
      expect(_cell(block, 'f'), const Rect.fromLTWH(0, 0, 364, 60));
      expect(row.hasThumbnail, isFalse);
      expect(row.leading, const Rect.fromLTWH(14, 6, 44, 44));
      expect(row.control, row.leading);
      // Text at the control + 53; name + 4, info + 27.
      expect(row.name, const Rect.fromLTWH(67, 10, 364 - 67 - 41, 20));
      expect(row.info, const Rect.fromLTWH(67, 33, 364 - 67 - 41, 16));
      expect(row.infoText, '2.0 KB PDF');
      expect(row.nameLines, 1);
      expect(row.link, isNull);
      expect(row.carriesTime, isTrue);
      expect(row.mirrorsInRtl, isFalse);
    });

    test('an extra title line grows the row and moves the info line 16', () {
      final block = _stack(_android, _input([_file('f', name: 'x' * 40)]));
      final row = _row(block, 'f');
      expect(row.nameLines, 2);
      expect(row.name.height, 40);
      expect(row.info.top, 33 + 16);
      expect(_cell(block, 'f').height, 56 + 16 + 4);
    });

    test('the name takes at most two lines', () {
      final row = _row(
        _stack(_android, _input([_file('f', name: 'x' * 200)])),
        'f',
      );
      expect(row.nameLines, 2);
    });

    test('the time on its own line grows the last row 12', () {
      // 364 − 122 − info 60 leaves 182, less than a 200-wide time.
      final block = _stack(
        _android,
        _input([_file('f')], chrome: const MediaLayoutChrome(timeWidth: 200)),
      );
      expect(_cell(block, 'f').height, 56 + 12);
    });

    test('a caption below takes the time: the row keeps 56', () {
      final block = _stack(
        _android,
        _input([_file('f')], captionPosition: MediaCaptionPosition.below),
      );
      expect(_cell(block, 'f').height, 56);
      expect(_row(block, 'f').carriesTime, isFalse);
    });

    test('a row with a thumbnail', () {
      final block = _stack(_android, _input([_image('i')]));
      final row = _row(block, 'i');
      expect(row.hasThumbnail, isTrue);
      expect(row.leading, const Rect.fromLTWH(4, 0, 86, 86));
      expect(row.control, const Rect.fromLTWH(25, 21, 44, 44));
      // Text at the thumb + 10, title + 8, info under the title + 13.
      expect(row.name.topLeft, const Offset(100, 8));
      expect(row.info.top, 8 + 16 + 13);
      expect(_cell(block, 'i').height, 86);
    });

    test('a single file widens to its caption + 31, never past the list', () {
      final block = _stack(
        _android,
        _input(
          [_file('f')],
          availableWidth: 400,
          captionWidth: 360,
          captionPosition: MediaCaptionPosition.below,
        ).withContentWidth(300),
      );
      expect(block.rect.width, 391);
    });

    test('a stack is min(list − 50 − avatar, 300) wide; rows pull up 3 with '
        'a thumbnail, 6 without, and give up as much below', () {
      final block = _stack(
        _android,
        _input([_file('a'), _image('b'), _file('c')]),
      );
      expect(block.rect.width, 300);
      expect(_cell(block, 'a'), const Rect.fromLTWH(0, 0, 300, 56));
      // 56 − 3 (b pulls up) − 6 (a gives up).
      expect(_cell(block, 'b'), const Rect.fromLTWH(0, 47, 300, 86));
      // 133 − 6 − 3; the last file carries the time.
      expect(_cell(block, 'c'), const Rect.fromLTWH(0, 124, 300, 60));
      expect(block.rect.height, 184);
      expect(_row(block, 'a').carriesTime, isFalse);
      expect(_row(block, 'c').carriesTime, isTrue);

      final narrow = _stack(
        _android,
        _input([_file('a'), _file('b')], showsAvatar: true),
      );
      expect(narrow.rect.width, 364 - 50 - 52);
    });
  });

  group('iOS', () {
    test('a single file without a thumbnail', () {
      final block = _stack(_ios, _input([_file('f')]));
      final row = _row(block, 'f');
      // Insets 15 + control area 52 + text + 15, up to the content width.
      expect(block.rect.width, 70 + 50 + 15);
      expect(_cell(block, 'f').height, 65);
      expect(row.leading, const Rect.fromLTWH(18, 9, 44, 44));
      expect(row.infoText, '2.0 KB');
      // Name and info centred on the control, the info under the name − 1.
      expect(row.name.top, 31 - (20 - 1 + 16) / 2);
      expect(row.info.top, row.name.bottom - 1);
      expect(row.name.left, 70);
    });

    test('one name line without a thumbnail, two with one', () {
      final long = 'x' * 60;
      expect(
        _row(_stack(_ios, _input([_file('f', name: long)])), 'f').nameLines,
        1,
      );
      final row = _row(
        _stack(_ios, _input([_file('i', name: long, mimeType: 'image/png')])),
        'i',
      );
      expect(row.nameLines, 2);
      expect(row.leading, const Rect.fromLTWH(14, 2, 74, 74));
      expect(row.control.center, row.leading.center);
      expect(row.name.left, 15 + 86);
    });

    test('consecutive files overlap 4', () {
      final block = _stack(_ios, _input([_file('a'), _file('b')]));
      expect(_cell(block, 'b').top, 65 - 4);
    });
  });

  group('desktop', () {
    test('a single file: at least 268 wide, padding (12, 8, 10, 8)', () {
      final block = _stack(_desktop, _input([_file('f')]));
      final row = _row(block, 'f');
      expect(block.rect.width, 268);
      expect(_cell(block, 'f').height, 60);
      expect(row.leading, const Rect.fromLTWH(12, 8, 44, 44));
      expect(row.name, const Rect.fromLTWH(67, 12, 268 - 77, 20));
      expect(row.info.top, 34);
      expect(row.link, isNull);
      expect(row.mirrorsInRtl, isTrue);
    });

    test('at most 430 wide, the name on one line', () {
      final block = _stack(
        _desktop,
        _input([_file('f', name: 'x' * 80)], availableWidth: 900),
      );
      expect(block.rect.width, 430);
      expect(_row(block, 'f').nameLines, 1);
    });

    test('a thumbnail row: 72 thumb, padding (6, 6, 10, 6), the link line '
        'at 55', () {
      final block = _stack(_desktop, _input([_image('i')]));
      final row = _row(block, 'i');
      expect(_cell(block, 'i').height, 84);
      expect(row.leading, const Rect.fromLTWH(6, 6, 72, 72));
      expect(row.name.topLeft, const Offset(92, 11));
      expect(row.info.top, 31);
      expect(row.link, const Rect.fromLTWH(92, 55, 268 - 102, 16));
    });

    test('a stack takes the grouped paddings, pulls rows up 6 and adds the '
        'extra line for views, signature or edited', () {
      final block = _stack(
        _desktop,
        _input([
          _file('a'),
          _image('b'),
        ], chrome: const MediaLayoutChrome(hasFooterInfo: true)),
      );
      expect(_cell(block, 'a'), const Rect.fromLTWH(0, 0, 268, 54));
      expect(_row(block, 'a').leading, const Rect.fromLTWH(12, 5, 44, 44));
      expect(_row(block, 'a').name.top, 9);
      expect(_row(block, 'a').info.top, 31);
      expect(_cell(block, 'b'), const Rect.fromLTWH(0, 48, 268, 78));
      expect(_row(block, 'b').leading, const Rect.fromLTWH(6, 3, 72, 72));
      expect(_row(block, 'b').link?.top, 52);
      expect(block.footer, const Rect.fromLTWH(0, 126, 268, 13));
      expect(block.rect.height, 139);

      final quiet = _stack(_desktop, _input([_file('a'), _image('b')]));
      expect(quiet.footer, isNull);
    });
  });

  group('captions', () {
    test('each file keeps its own caption slot under its row', () {
      final block = _stack(
        _android,
        _input(
          [_file('a'), _file('b')],
          fileCaptionHeights: {const MediaItemId('a'): 30},
        ),
      );
      expect(_row(block, 'a').captionSlot, const Rect.fromLTWH(0, 56, 300, 30));
      expect(_row(block, 'b').captionSlot, isNull);
      // The next row starts under the caption.
      expect(_cell(block, 'b').top, 86);
    });

    test('the last file with its own caption does not carry the time', () {
      final block = _stack(
        _android,
        _input([_file('a')], fileCaptionHeights: {const MediaItemId('a'): 20}),
      );
      expect(_row(block, 'a').carriesTime, isFalse);
      expect(block.rect.height, 56 + 20);
    });
  });

  group('strings', () {
    test('the size comes from the host strings', () {
      final step = _android.layoutStep as MediaLayoutPolicy;
      final policy = _android.copyWith(
        layoutStep: step.copyWith(
          fileStack: step.fileStack.copyWith(
            strings: MediaFileStrings.english.copyWith(
              size: (bytes) => '$bytes octets',
              info: (size, extension) => '${extension ?? ''} · ${size ?? ''}',
            ),
          ),
        ),
      );
      expect(
        _row(_stack(policy, _input([_file('f')])), 'f').infoText,
        'PDF · 2048 octets',
      );
    });

    test('English sizes', () {
      const strings = MediaFileStrings.english;
      expect(strings.size(512), '512 B');
      expect(strings.size(1536), '1.5 KB');
      expect(strings.size(3 * 1024 * 1024), '3.0 MB');
      expect(strings.size(5 * 1024 * 1024 * 1024 ~/ 4), '1.25 GB');
      expect(strings.progress('1.0 MB', '3.0 MB'), '1.0 MB / 3.0 MB');
      expect(strings.info(null, 'ZIP'), 'ZIP');
      expect(MediaFileStackPolicy.extensionOf('archive.tar.gz'), 'GZ');
      expect(MediaFileStackPolicy.extensionOf('.hidden'), isNull);
      expect(MediaFileStackPolicy.extensionOf('README'), isNull);
    });
  });

  group('policy', () {
    test('copyWith replaces one value and keeps the rest', () {
      const base = MediaFileStackPolicy.android();
      final changed = base.copyWith(pullUp: 9);
      expect(changed.pullUp, 9);
      expect(changed.pullUpWithThumbnail, base.pullUpWithThumbnail);
      expect(changed, isNot(base));
      expect(base.copyWith(), base);
    });

    test('a transition keeps each row\'s geometry and moves the footer', () {
      const chrome = MediaLayoutChrome(hasFooterInfo: true);
      final a = _desktop.layout(
        _input([_file('a'), _file('b')], chrome: chrome),
      );
      final b = _desktop.layout(
        _input([_file('a'), _file('b'), _file('c')], chrome: chrome),
      );
      final mid = MediaLayout.lerp(a, b, 0.5);
      final stack = mid.blocks.single as MediaBlock$FileStack;
      final end = b.blocks.single as MediaBlock$FileStack;
      final start = a.blocks.single as MediaBlock$FileStack;
      expect(stack.rows, end.rows);
      expect(stack.footer, Rect.lerp(start.footer, end.footer, 0.5));
    });

    test('a layout of files is a value', () {
      final input = _input([_file('a'), _image('b')]);
      expect(_android.layout(input), _android.layout(input));
    });
  });

  group('diagnostics', () {
    test('a file stack reports layoutComputed and no file name', () {
      final recorder = RecordingDiagnostics.install();
      _android.layout(
        _input([
          _file('a', name: 'private-report.pdf'),
          MediaItem(
            id: const MediaItemId('c'),
            kind: const MediaItemKind.custom('poll'),
            descriptor: const ContentDescriptor(
              key: ContentKey.document('c'),
              fileName: 'private-poll.bin',
            ),
          ),
        ]),
      );
      expect(
        recorder.whereOp(MediaOp.layoutComputed).single.fields,
        containsPair('blocks', 'fileStack'),
      );
      expect(recorder.whereOp(MediaOp.unknownKind), hasLength(1));
      for (final event in recorder.events) {
        for (final value in event.fields.values) {
          expect('$value', isNot(contains('private')));
        }
      }
    });
  });
}

extension on MediaLayoutInput {
  MediaLayoutInput withContentWidth(double width) => MediaLayoutInput(
    items: items,
    availableWidth: availableWidth,
    maxContentWidth: width,
    captionPosition: captionPosition,
    captionWidth: captionWidth,
    correlation: correlation,
  );
}
