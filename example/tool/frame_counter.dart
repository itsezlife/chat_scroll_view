/// The frame counter clips: each frame carries its index, in a binary bar a
/// screen recording can be read by and as a big number a person can read.
///
///   dart run tool/frame_counter.dart make [OUT_DIR]
///   dart run tool/frame_counter.dart read RECORDING [--fps N] [--width W]
///
/// `make` writes the nine clips of the demo's frame counter pack (GIF, WebP
/// and MP4, each at 10, 15 and 25 fps) into OUT_DIR, by default
/// `assets/frame_counter/`. It needs `ffmpeg` (with `libx264`) and `gif2webp`
/// on the PATH: this ffmpeg has no WebP encoder, so the WebP is the GIF
/// re-encoded, frame for frame.
///
/// `read` reads the bar of every frame counter clip on screen in each frame of
/// a screen recording, and prints, for each clip, every return: the frame it
/// left on, the first frame back, and the steps of the index after it, with
/// how long each frame stayed. The recording is resampled to N frames a second
/// (60 by default) and scaled to W pixels wide (360 by default) first.
///
/// ## The frame (192 x 144)
///
/// ```text
///  0                                                          191
///  +------------------------------------------------------------+  0
///  |  key colour band                                           |
///  |   +----+----+----+----+----+----+----+----+----+----+      |  8
///  |   | c1 | c0 | b7 | b6 | b5 | b4 | b3 | b2 | b1 | b0 |      |
///  |   +----+----+----+----+----+----+----+----+----+----+      | 32
///  |                                                            |
///  +------------------------------------------------------------+ 40
///  |                                                            |
///  |          [ 7-seg ]   [ 7-seg ]   [ 7-seg ]                 | 52..132
///  |          hundreds      tens        units                   |
///  +------------------------------------------------------------+ 144
/// ```
///
/// - **Band**, y 0 to 39, the whole width: the key colour of the clip's rate,
///   so the reader finds the bar and knows the rate: magenta (255, 0, 255) at
///   10 fps, green (0, 224, 0) at 15, orange (255, 160, 0) at 25.
/// - **Bar**, ten cells of 16 x 24 from x 16 (cell i spans x 16 + 16i to
///   31 + 16i), y 8 to 31: white is 1, black is 0. The first two cells are
///   the clip's format (`c1 c0`: 0 GIF, 1 WebP, 2 MP4), the other eight the
///   frame's index in the clip, most significant bit first.
/// - **Number**, y 52 to 131 on a dark grey ground: the same index as three
///   seven-segment digits 40 x 80 (segments 8 thick), from x 24, 52 apart.
///
/// Every colour is flat and the cells are wide, so the bar survives a GIF
/// palette, 4:2:0 chroma and a screen recording's compression, and still
/// reads when the clip is drawn at half its size.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

// --- Layout ---

const int _width = 192;
const int _height = 144;
const int _bandHeight = 40;
const int _cellLeft = 16;
const int _cellWidth = 16;
const int _cellTop = 8;
const int _cellHeight = 24;
const int _formatBits = 2;
const int _indexBits = 8;
const int _cells = _formatBits + _indexBits;

const int _digitTop = 52;
const int _digitLeft = 24;
const int _digitPitch = 52;
const int _digitWidth = 40;
const int _digitHeight = 80;
const int _segment = 8;

/// A clip rate and the colour of its band.
typedef _Rate = ({int fps, int seconds, List<int> rgb, String name});

const List<_Rate> _rates = [
  (fps: 10, seconds: 6, rgb: [255, 0, 255], name: 'magenta'),
  (fps: 15, seconds: 6, rgb: [0, 224, 0], name: 'green'),
  (fps: 25, seconds: 4, rgb: [255, 160, 0], name: 'orange'),
];

const List<String> _formats = ['gif', 'webp', 'mp4'];

// The seven segments of a digit, as rectangles within its 40 x 80 box:
// (left, top, right, bottom), right and bottom exclusive.
const Map<String, List<int>> _segments = {
  'a': [0, 0, _digitWidth, _segment],
  'b': [_digitWidth - _segment, 0, _digitWidth, _digitHeight ~/ 2],
  'c': [_digitWidth - _segment, _digitHeight ~/ 2, _digitWidth, _digitHeight],
  'd': [0, _digitHeight - _segment, _digitWidth, _digitHeight],
  'e': [0, _digitHeight ~/ 2, _segment, _digitHeight],
  'f': [0, 0, _segment, _digitHeight ~/ 2],
  'g': [
    0,
    _digitHeight ~/ 2 - _segment ~/ 2,
    _digitWidth,
    _digitHeight ~/ 2 + _segment ~/ 2,
  ],
};

// The segments lit for each digit.
const List<String> _digits = [
  'abcdef',
  'bc',
  'abdeg',
  'abcdg',
  'bcfg',
  'acdfg',
  'acdefg',
  'abc',
  'abcdefg',
  'abcdfg',
];

Future<void> main(List<String> args) async {
  switch (args) {
    case ['make']:
      await _make('assets/frame_counter');
    case ['make', final out]:
      await _make(out);
    case ['read', final recording, ...final rest]:
      await _read(recording, rest);
    default:
      stderr.writeln(
        'usage: dart run tool/frame_counter.dart make [OUT_DIR]\n'
        '       dart run tool/frame_counter.dart read RECORDING '
        '[--fps N] [--width W]',
      );
      exitCode = 64;
  }
}

// --- make ---

// The geq expression of one channel: [band] in the band, the bar's bits in
// white and black, the digits light on a dark ground.
String _channel(int band, int format) {
  // Ten cells: the format's two bits, then the index's eight.
  const cell = 'floor((X-$_cellLeft)/$_cellWidth)';
  const inBar =
      'between(X,$_cellLeft,${_cellLeft + _cells * _cellWidth - 1})'
      '*between(Y,$_cellTop,${_cellTop + _cellHeight - 1})';
  final bit =
      'if(lt($cell,$_formatBits),'
      'mod(floor($format/pow(2,${_formatBits - 1}-$cell)),2),'
      'mod(floor(N/pow(2,${_cells - 1}-$cell)),2))';
  final lit = <String>[];
  for (var d = 0; d < 3; d++) {
    final left = _digitLeft + d * _digitPitch;
    final value = 'mod(floor(N/${math.pow(10, 2 - d)}),10)';
    for (final MapEntry(key: name, value: r) in _segments.entries) {
      var mask = 0;
      for (var v = 0; v < 10; v++) {
        if (_digits[v].contains(name)) mask |= 1 << v;
      }
      lit.add(
        'between(X,${left + r[0]},${left + r[2] - 1})'
        '*between(Y,${_digitTop + r[1]},${_digitTop + r[3] - 1})'
        '*mod(floor($mask/pow(2,$value)),2)',
      );
    }
  }
  return 'if(lt(Y,$_bandHeight),'
      'if($inBar,255*$bit,$band),'
      'if(gt(${lit.join('+')},0),235,48))';
}

Future<void> _make(String out) async {
  await Directory(out).create(recursive: true);
  for (final rate in _rates) {
    final frames = rate.fps * rate.seconds;
    for (final (format, name) in _formats.indexed) {
      final geq = [
        for (final (i, c) in ['r', 'g', 'b'].indexed)
          "$c='${_channel(rate.rgb[i], format)}'",
      ].join(':');
      final source =
          'color=c=black:s=${_width}x$_height:r=${rate.fps}:d=${rate.seconds},'
          'format=rgb24,geq=$geq';
      final base = '$out/counter_${rate.fps}fps';
      switch (name) {
        case 'mp4':
          await _run('ffmpeg', [
            ...['-hide_banner', '-loglevel', 'error', '-y'],
            ...['-f', 'lavfi', '-i', source],
            ...['-frames:v', '$frames', '-c:v', 'libx264', '-preset', 'slow'],
            ...['-crf', '26', '-g', '${rate.fps * 2}', '-pix_fmt', 'yuv420p'],
            ...['-movflags', '+faststart', '-an', '$base.mp4'],
          ]);
        case 'gif' || 'webp':
          final gif = name == 'gif' ? '$base.gif' : '$base.webp.gif';
          await _run('ffmpeg', [
            ...['-hide_banner', '-loglevel', 'error', '-y'],
            ...['-f', 'lavfi', '-i', source],
            ...['-frames:v', '$frames'],
            ...[
              '-vf',
              'split[a][b];[a]palettegen=max_colors=8:reserve_transparent=0[p];'
                  '[b][p]paletteuse=dither=none',
            ],
            ...['-loop', '0', gif],
          ]);
          if (name == 'webp') {
            await _run('gif2webp', [
              '-quiet',
              '-min_size',
              gif,
              '-o',
              '$base.webp',
            ]);
            await File(gif).delete();
          }
      }
    }
  }
  for (final file in Directory(
    out,
  ).listSync()..sort((a, b) => a.path.compareTo(b.path))) {
    if (file is File && !file.path.endsWith('.md')) {
      stdout.writeln('${file.path}  ${file.lengthSync() ~/ 1024} KB');
    }
  }
}

Future<void> _run(String executable, List<String> args) async {
  final result = await Process.run(executable, args);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      args,
      '${result.stderr}',
      result.exitCode,
    );
  }
}

// --- read ---

/// One clip's bar found in a frame of the recording.
typedef _Seen = ({int format, int index});

Future<void> _read(String recording, List<String> options) async {
  var fps = 60;
  var width = 360;
  for (var i = 0; i + 1 < options.length; i += 2) {
    switch (options[i]) {
      case '--fps':
        fps = int.parse(options[i + 1]);
      case '--width':
        width = int.parse(options[i + 1]);
    }
  }
  final probe = await Process.run('ffprobe', [
    ...['-v', 'error', '-select_streams', 'v:0'],
    ...['-show_entries', 'stream=width,height', '-of', 'csv=p=0', recording],
  ]);
  final [sourceWidth, sourceHeight] = '${probe.stdout}'
      .trim()
      .split(',')
      .map(int.parse)
      .toList();
  // Even, as the scaler wants.
  final height = (sourceHeight * width / sourceWidth / 2).round() * 2;
  final decoder = await Process.start('ffmpeg', [
    ...['-hide_banner', '-loglevel', 'error', '-i', recording],
    ...['-vf', 'fps=$fps,scale=$width:$height:flags=area'],
    ...['-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
  ]);
  unawaited(stderr.addStream(decoder.stderr));

  final frameBytes = width * height * 3;
  final tracks = SplayTreeMap<String, List<int?>>();
  var frame = 0;
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in decoder.stdout) {
    buffer.add(chunk);
    if (buffer.length < frameBytes) continue;
    var bytes = buffer.takeBytes();
    var at = 0;
    while (bytes.length - at >= frameBytes) {
      final seen = _scan(
        Uint8List.sublistView(bytes, at, at + frameBytes),
        width,
        height,
      );
      // A clip seen for the first time had no bar in the frames before.
      for (final key in seen.keys) {
        tracks.putIfAbsent(key, () => List.filled(frame, null, growable: true));
      }
      for (final MapEntry(:key, value: track) in tracks.entries) {
        track.add(seen[key]?.index);
      }
      frame++;
      at += frameBytes;
    }
    bytes = Uint8List.sublistView(bytes, at);
    buffer.add(bytes);
  }
  await decoder.exitCode;
  stdout.writeln('$frame frames at $fps fps, read at ${width}x$height');
  for (final MapEntry(:key, value: track) in tracks.entries) {
    _report(key, track, fps);
  }
}

// The clips found in one frame, by "<format>@<fps>".
Map<String, _Seen> _scan(Uint8List rgb, int width, int height) {
  final found = <String, _Seen>{};
  for (final rate in _rates) {
    final mask = Uint8List(width * height);
    for (var p = 0, i = 0; p < mask.length; p++, i += 3) {
      if ((rgb[i] - rate.rgb[0]).abs() < 70 &&
          (rgb[i + 1] - rate.rgb[1]).abs() < 70 &&
          (rgb[i + 2] - rate.rgb[2]).abs() < 70) {
        mask[p] = 1;
      }
    }
    for (final box in _components(mask, width, height)) {
      final seen = _readBar(rgb, width, box);
      if (seen == null) continue;
      found['${_formats[seen.format]}@${rate.fps}'] = seen;
    }
  }
  return found;
}

typedef _Box = ({int left, int top, int right, int bottom, int count});

// The bounding boxes of the 4-connected regions of [mask] big enough to be a
// band. Clears the mask as it goes.
List<_Box> _components(Uint8List mask, int width, int height) {
  final boxes = <_Box>[];
  final stack = <int>[];
  for (var start = 0; start < mask.length; start++) {
    if (mask[start] == 0) continue;
    var (left, top, right, bottom, count) = (width, height, 0, 0, 0);
    mask[start] = 0;
    stack.add(start);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final x = p % width;
      final y = p ~/ width;
      count++;
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
      if (x > 0 && mask[p - 1] == 1) {
        mask[p - 1] = 0;
        stack.add(p - 1);
      }
      if (x + 1 < width && mask[p + 1] == 1) {
        mask[p + 1] = 0;
        stack.add(p + 1);
      }
      if (y > 0 && mask[p - width] == 1) {
        mask[p - width] = 0;
        stack.add(p - width);
      }
      if (y + 1 < height && mask[p + width] == 1) {
        mask[p + width] = 0;
        stack.add(p + width);
      }
    }
    if (count >= 60) {
      boxes.add((
        left: left,
        top: top,
        right: right + 1,
        bottom: bottom + 1,
        count: count,
      ));
    }
  }
  return boxes;
}

// The bar inside the band [box], or null when the box is not a whole band
// (cut by the screen's edge, covered, or something else of that colour).
_Seen? _readBar(Uint8List rgb, int width, _Box box) {
  final w = box.right - box.left;
  final h = box.bottom - box.top;
  const aspect = _width / _bandHeight;
  if (h < 6 || (w / h - aspect).abs() > aspect * 0.15) return null;
  // The band's own colour covers all of it but the bar.
  const fill = 1 - _cells * _cellWidth * _cellHeight / (_width * _bandHeight);
  if ((box.count / (w * h) - fill).abs() > 0.2) return null;
  var format = 0;
  var index = 0;
  for (var c = 0; c < _cells; c++) {
    final x = box.left + ((_cellLeft + (c + 0.5) * _cellWidth) * w / _width);
    final y = box.top + ((_cellTop + _cellHeight / 2) * h / _bandHeight);
    final i = (y.floor() * width + x.floor()) * 3;
    final luma = (rgb[i] * 299 + rgb[i + 1] * 587 + rgb[i + 2] * 114) ~/ 1000;
    final bit = luma > 128 ? 1 : 0;
    if (c < _formatBits) {
      format = format << 1 | bit;
    } else {
      index = index << 1 | bit;
    }
  }
  if (format >= _formats.length) return null;
  return (format: format, index: index);
}

// Prints [clip]'s returns: where it left, where it came back, and how its
// index moved for the second and a half after.
void _report(String clip, List<int?> track, int fps) {
  final fpsOf = int.parse(clip.split('@').last);
  final length = _rates.firstWhere((r) => r.fps == fpsOf);
  final count = length.fps * length.seconds;
  final frameMs = 1000 / fps;
  // Steps of the index modulo the clip's length, so a loop is a step of one.
  int step(int from, int to) => (to - from) % count;

  stdout.writeln(
    '\n$clip (${length.fps} fps clip, $count frames, '
    'one frame every ${(1000 / length.fps).toStringAsFixed(0)} ms)',
  );
  var returns = 0;
  int? leftAt;
  int? leftIndex;
  for (var t = 0; t < track.length; t++) {
    final index = track[t];
    if (index == null) {
      if (t > 0 && track[t - 1] != null) {
        leftAt = t;
        leftIndex = track[t - 1];
      }
      continue;
    }
    if (leftAt == null || leftIndex == null || t == 0 || track[t - 1] != null) {
      continue;
    }
    // Back after a gap of at least a tenth of a second.
    final away = (t - leftAt) * frameMs;
    if (away < 100) continue;
    returns++;
    final runs = <({int index, double ms})>[];
    for (var u = t; u < track.length && (u - t) * frameMs < 1500; u++) {
      final i = track[u];
      if (i == null) break;
      if (runs.isNotEmpty && runs.last.index == i) {
        runs.last = (index: i, ms: runs.last.ms + frameMs);
      } else {
        runs.add((index: i, ms: frameMs));
      }
    }
    final gaps = [
      for (var r = 1; r < runs.length; r++)
        if (step(runs[r - 1].index, runs[r].index) != 1)
          '+${step(runs[r - 1].index, runs[r].index)} after '
              '${runs[r - 1].index} at ${_sum(runs, r).toStringAsFixed(0)} ms',
    ];
    final holds = [
      // The first and the last run are cut by the return and the window.
      for (var r = 1; r < runs.length - 1; r++)
        if (runs[r].ms > 1.6 * 1000 / length.fps)
          '${runs[r].index} held ${runs[r].ms.toStringAsFixed(0)} ms',
    ];
    stdout
      ..writeln(
        '  return $returns at ${(t * frameMs / 1000).toStringAsFixed(2)} s, '
        'away ${away.toStringAsFixed(0)} ms: left $leftIndex, back '
        '${track[t]}${track[t] == leftIndex ? '' : ' (${step(leftIndex, track[t]!) <= count ~/ 2 ? '+' : '-'}${math.min(step(leftIndex, track[t]!), step(track[t]!, leftIndex))})'}',
      )
      ..writeln('    then: ${runs.map((r) => '${r.index}').join(' ')}')
      ..writeln(
        '    gaps: ${gaps.isEmpty ? 'none' : gaps.join(', ')}; '
        'holds: ${holds.isEmpty ? 'none' : holds.join(', ')}',
      );
  }
  if (returns == 0) stdout.writeln('  no return');
}

double _sum(List<({int index, double ms})> runs, int end) {
  var ms = 0.0;
  for (var r = 0; r < end; r++) {
    ms += runs[r].ms;
  }
  return ms;
}
