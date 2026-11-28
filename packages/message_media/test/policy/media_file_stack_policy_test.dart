/// The file stack through `MessageMediaPolicy.layout`: each platform's row
/// geometry, bubble width, stacking, time, caption slots and footer.
///
/// **Seam:** `MessageMediaPolicy.layout` with the file stack's text measure
/// replaced by a fixed one (10 per name glyph, 6 per info glyph), so the
/// numbers do not depend on a font.
library;

import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

import '../support/media_scopes.dart';

/// A measure of fixed glyph widths: a name glyph is 10 wide and its line
/// 20 high, an info glyph 6 wide and its line 16 high. A name is told from
/// an info line by its type: 14 or more, or a weight above normal (the
/// desktop's 13 semibold name).
final class _FixedMeasure implements MediaTextMeasure {
  const _FixedMeasure();

  @override
  MediaTextSize measure(
    InlineSpan text, {
    required TextScaler scaler,
    double maxWidth = double.infinity,
    int maxLines = 1,
    bool ellipsis = false,
  }) {
    final plain = text.toPlainText();
    final style = text.style;
    final isName =
        (style?.fontSize ?? 0) >= 14 ||
        (style?.fontWeight ?? FontWeight.normal) != FontWeight.normal;
    if (!isName) return MediaTextSize(width: plain.length * 6.0, height: 16);
    final natural = plain.length * 10.0;
    final lines = maxWidth.isInfinite || natural <= maxWidth
        ? 1
        : (natural / maxWidth).ceil().clamp(1, maxLines);
    return MediaTextSize(
      width: lines == 1 ? natural : maxWidth,
      height: lines * 20.0,
      lines: lines,
    );
  }
}

final _text = MediaScopes.text.copyWith(measure: const _FixedMeasure());

const _android = MessageMediaPolicy.android();
const _ios = MessageMediaPolicy.ios();
const _desktop = MessageMediaPolicy.desktop();

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
  text: _text,
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

    test('a single file widens to its caption + 31, never past the '
        'bubble\'s max content width', () {
      final block = _stack(
        _android,
        _input(
          [_file('f')],
          availableWidth: 400,
          captionWidth: 260,
          captionPosition: MediaCaptionPosition.below,
        ).withContentWidth(300),
      );
      expect(block.rect.width, 300);

      final wide = _stack(
        _android,
        _input(
          [_file('f')],
          availableWidth: 400,
          captionWidth: 360,
          captionPosition: MediaCaptionPosition.below,
        ).withContentWidth(380),
      );
      expect(wide.rect.width, 380);
    });

    test('a stack never takes more than the bubble\'s max content width, so '
        'its rows and their options stay inside the bubble', () {
      final block = _stack(
        _android,
        _input([
          _file('a'),
          _image('b'),
        ], availableWidth: 420).withContentWidth(274),
      );
      expect(block.rect.width, 274);
      final first = _cell(block, 'a');
      final options = const MessageMediaPolicy.android().chrome.options
          .affordanceOf(block.cells.first, block)!;
      expect(options.iconRect.right, lessThanOrEqualTo(first.right));
    });

    test('a stack is min(list − 50 − avatar, 300) wide; rows meet, each '
        'giving up 6 (3 with a thumbnail) at a side it shares, so every '
        'control and thumbnail keeps its size inside its row', () {
      final block = _stack(
        _android,
        _input([_file('a'), _image('b'), _file('c')]),
      );
      expect(block.rect.width, 300);
      // A lone row's 6 above the control, 3 below it.
      expect(_cell(block, 'a'), const Rect.fromLTWH(0, 0, 300, 53));
      expect(_row(block, 'a').leading, const Rect.fromLTWH(14, 6, 44, 44));
      // 3 above and below the 86 thumbnail.
      expect(_cell(block, 'b'), const Rect.fromLTWH(0, 53, 300, 90));
      expect(_row(block, 'b').leading, const Rect.fromLTWH(4, 2, 86, 86));
      expect(_row(block, 'b').name.top, 10);
      // 7 above the control, a lone row's 6 below it, + 4 for the time.
      expect(_cell(block, 'c'), const Rect.fromLTWH(0, 143, 300, 61));
      expect(_row(block, 'c').leading, const Rect.fromLTWH(14, 7, 44, 44));
      expect(block.rect.height, 204);
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

    test('a stack takes the grouped paddings, its rows meeting, 3 more '
        'above and below it, and adds the extra line for views, signature or '
        'edited', () {
      final block = _stack(
        _desktop,
        _input([
          _file('a'),
          _image('b'),
        ], chrome: const MediaLayoutChrome(hasFooterInfo: true)),
      );
      // 3 + the grouped (12, 5, 10, 5).
      expect(_cell(block, 'a'), const Rect.fromLTWH(0, 0, 268, 57));
      expect(_row(block, 'a').leading, const Rect.fromLTWH(12, 8, 44, 44));
      expect(_row(block, 'a').name.top, 12);
      expect(_row(block, 'a').info.top, 34);
      // The grouped (6, 3, 10, 3) + 3.
      expect(_cell(block, 'b'), const Rect.fromLTWH(0, 57, 268, 81));
      expect(_row(block, 'b').leading, const Rect.fromLTWH(6, 3, 72, 72));
      expect(_row(block, 'b').link?.top, 52);
      expect(block.footer, const Rect.fromLTWH(0, 138, 268, 13));
      expect(block.rect.height, 151);

      final quiet = _stack(_desktop, _input([_file('a'), _image('b')]));
      expect(quiet.footer, isNull);
    });
  });

  group('row slots', () {
    // A disc row, a square thumbnail and a tall one: each row's control or
    // thumbnail is painted inside its own row and the stack, and over no
    // part of another row.
    final items = [
      _file('disc', name: 'notes.txt'),
      _file('square', name: 'diagram.svg', mimeType: 'image/svg+xml'),
      _file('tall', name: 'meadow.jpg', mimeType: 'image/jpeg'),
    ];
    for (final (name, policy) in [
      ('Android', _android),
      ('iOS', _ios),
      ('desktop', _desktop),
    ]) {
      test('$name: every thumbnail sits inside its row and the stack', () {
        final block = _stack(policy, _input(items));
        List<Rect> paintedOf(MediaCell cell) {
          final row = block.rowOf(cell.itemId)!;
          return [
            for (final rect in [row.leading, row.name, row.info])
              rect.shift(cell.rect.topLeft),
          ];
        }

        for (final cell in block.cells) {
          final leading = paintedOf(cell).first;
          expect(
            cell.rect.intersect(leading),
            leading,
            reason: '${cell.itemId} at $leading, its row ${cell.rect}',
          );
          expect(
            block.rect.intersect(leading),
            leading,
            reason: '${cell.itemId} at $leading, the stack ${block.rect}',
          );
          for (final other in block.cells) {
            if (other.itemId == cell.itemId) continue;
            for (final part in paintedOf(other)) {
              expect(
                leading.overlaps(part),
                isFalse,
                reason: '${cell.itemId} at $leading over ${other.itemId} $part',
              );
            }
          }
        }
      });
    }
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
      // The first of two rows: 53 (a lone row's 6 above the control, the
      // grouped 3 below it).
      expect(_row(block, 'a').captionSlot, const Rect.fromLTWH(0, 53, 300, 30));
      expect(_row(block, 'b').captionSlot, isNull);
      // The next row starts under the caption.
      expect(_cell(block, 'b').top, 83);
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
    test('the size and the info line come from the input\'s strings', () {
      final russian = _input([_file('f')]).copyWith(
        text: _text.copyWith(strings: ChromeStringsPresets.russian.media),
      );
      expect(_row(_stack(_android, russian), 'f').infoText, '2.0 КБ PDF');
    });

    test('English sizes', () {
      final strings = MediaScopes.strings;
      expect(strings.size(512), '512 B');
      expect(strings.size(1536), '1.5 KB');
      expect(strings.size(3 * 1024 * 1024), '3.0 MB');
      expect(strings.size(5 * 1024 * 1024 * 1024 ~/ 4), '1.25 GB');
      expect(strings.fileProgress('1.0 MB', '3.0 MB'), '1.0 MB / 3.0 MB');
      expect(strings.fileInfo(null, 'ZIP'), 'ZIP');
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
    text: _text,
    items: items,
    availableWidth: availableWidth,
    maxContentWidth: width,
    captionPosition: captionPosition,
    captionWidth: captionWidth,
    correlation: correlation,
  );
}
