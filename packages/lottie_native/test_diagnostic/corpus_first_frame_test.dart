// Diagnostic (ticket 57), not in unit_test.dart. Renders every corpus Lottie
// file through the real native binding and counts non-empty frames.
//
//   CORPUS_DIR=/path/to/telegram-stickers flutter test test_diagnostic/corpus_first_frame_test.dart
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';

const _edge = 128;

void main() {
  final dir =
      Platform.environment['CORPUS_DIR'] ??
      '/Users/gothiq2302/Documents/VSCodeProjects/Flutter/chat_scroll_view/'
          '.scratch/native-media-ffi/corpus/telegram-stickers';
  final binding = NativeLottieBinding.probe();

  test('every corpus file renders a non-empty frame at $_edge px', () {
    expect(binding.isAvailable, isTrue, reason: '${binding.availability}');
    final perPack = <String, List<int>>{}; // total, loadFail, blank0, blankAll
    final blanks = <String>[];
    for (final pack in Directory(dir).listSync().whereType<Directory>()) {
      final name = pack.path.split('/').last;
      final c = perPack.putIfAbsent(name, () => [0, 0, 0, 0]);
      for (final f in pack.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.json'),
      )) {
        c[0]++;
        final id = '$name/${f.path.split('/').last}';
        final r = binding.load(
          Uint8List.fromList(utf8.encode(f.readAsStringSync())),
        );
        if (r is! LottieLoaded) {
          c[1]++;
          blanks.add('$id LOAD ${(r as LottieRejected).reason}');
          continue;
        }
        final info = r.info;
        const stride = _edge * 4;
        final buf = calloc<Uint8>(stride * _edge);
        try {
          bool nonEmpty(double frame) {
            final st = binding.renderBatch([
              LottieRenderJob(
                handle: r.handle,
                frame: frame,
                width: _edge,
                height: _edge,
                target: buf,
                strideBytes: stride,
              ),
            ]);
            if (st.single != LottieRenderStatus.ok) return false;
            final px = buf.asTypedList(stride * _edge);
            for (var i = 0; i < px.length; i++) {
              if (px[i] != 0) return true;
            }
            return false;
          }

          if (!nonEmpty(0)) {
            c[2]++;
            blanks.add(
              '$id FRAME0 blank (features ${info.features.bits}, '
              '${info.width}x${info.height}, ${info.frameCount}f)',
            );
          }
          final mid = (info.frameCount / 2).floorToDouble();
          if (!nonEmpty(mid)) {
            c[3]++;
            blanks.add('$id MID blank');
          }
        } finally {
          calloc.free(buf);
          binding.dispose(r.handle);
        }
      }
    }
    perPack.forEach(
      // ignore: avoid_print
      (k, v) => print(
        'PACK $k total=${v[0]} loadFail=${v[1]} frame0Blank=${v[2]} midBlank=${v[3]}',
      ),
    );
    // ignore: avoid_print
    blanks.forEach(print);
    expect(blanks, isEmpty);
  });
}
