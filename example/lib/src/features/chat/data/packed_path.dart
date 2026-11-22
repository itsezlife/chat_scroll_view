import 'package:content_model/content_model.dart';
import 'package:mpx_core/mpx_core.dart';

/// The outline of a sticker or custom emoji as the wire packs it, expanded to
/// SVG path data for the media core.
///
/// The core takes only path data in a view box (`ContentPreview.outline`);
/// expanding the wire's packed form is the host's work, done once, where the
/// data layer builds the descriptor.
///
/// ## The packing
///
/// Each byte is one token. The path opens with `M` and closes with `z`;
/// neither is sent.
///
/// | Byte | Token |
/// | --- | --- |
/// | 0 to 63 | the number itself |
/// | 64 to 127 | `-`, then the number `byte & 63` |
/// | 128 to 191 | `,`, then the number `byte & 63` |
/// | 192 to 255 | the character `_table[byte - 192]`: a command letter, a digit that continues the number before it, `-`, `,` or `.` |
///
/// The outline is laid out in a 512 x 512 box. A path with a command the
/// core does not draw (the table's unused slots read as `A`, an arc) gives no
/// preview at all, never a partial shape.
abstract final class PackedPath {
  /// The box every packed outline is laid out in.
  static const ContentSize viewBox = ContentSize(512, 512);

  static const String _table =
      'AACAAAAHAAALMAAAQASTAVAAAZaacaaaahaaalmaaaqastava.az0123456789-,';

  /// [bytes] written out as SVG path data.
  static String expand(List<int> bytes) {
    final path = StringBuffer('M');
    for (final byte in bytes) {
      if (byte >= 192) {
        path.write(_table[byte - 192]);
        continue;
      }
      if (byte >= 128) {
        path.write(',');
      } else if (byte >= 64) {
        path.write('-');
      }
      path.write(byte & 63);
    }
    return (path..write('z')).toString();
  }

  /// The outline preview of [bytes], or null when there are none or the
  /// path does not parse.
  static ContentPreview? outlineOf(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final path = expand(bytes);
    if (SvgPathData.parse(path) == null) return null;
    return ContentPreview.outline(path, viewBox);
  }
}
