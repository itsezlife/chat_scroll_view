import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The C entry points of a texture host over plain memory
/// (`fake_texture_table.c` next to this file), compiled for this machine:
/// what a render isolate locks and posts through, without a platform.
///
/// The technique of `frame_texture`'s own tests, with a table of the
/// decoder's own: a decoder never depends on the plugin.
final class TextureTable {
  TextureTable._(DynamicLibrary library)
    : entryPoints = FrameTextureEntryPoints(
        lock: library.lookup<Void>('fake_texture_lock').address,
        post: library.lookup<Void>('fake_texture_post').address,
      ),
      _new = library
          .lookupFunction<
            Int64 Function(Int32, Int32, Int32, Int32),
            int Function(int, int, int, int)
          >('fake_texture_new'),
      _pixels = library
          .lookupFunction<
            Pointer<Uint8> Function(Int64),
            Pointer<Uint8> Function(int)
          >('fake_texture_pixels'),
      _stride = library
          .lookupFunction<Int32 Function(Int64), int Function(int)>(
            'fake_texture_stride',
          ),
      _posts = library.lookupFunction<Int32 Function(Int64), int Function(int)>(
        'fake_texture_posts',
      ),
      _isLocked = library
          .lookupFunction<Int32 Function(Int64), int Function(int)>(
            'fake_texture_is_locked',
          ),
      _refuse = library
          .lookupFunction<Void Function(Int64, Int32), void Function(int, int)>(
            'fake_texture_refuse',
          );

  /// Compiles the table once per test process, or answers null with the
  /// reason in [skipReason] when this machine has no C compiler.
  static TextureTable? compile() => _compiled ??= _compile();
  static TextureTable? _compiled;

  /// Why [compile] answered null, for a skip message.
  static String skipReason = '';

  static TextureTable? _compile() {
    final source = _source();
    final out = Directory.systemTemp.createTempSync('fake_texture_table');
    final library =
        '${out.path}/libfake_texture_table'
        '${Platform.isMacOS ? '.dylib' : '.so'}';
    final ProcessResult result;
    try {
      result = Process.runSync('cc', [
        '-shared',
        '-fPIC',
        '-std=c11',
        '-Wall',
        '-Werror',
        '-fvisibility=hidden',
        source,
        '-o',
        library,
      ]);
    } on ProcessException catch (error) {
      skipReason = 'no C compiler (cc) here: $error';
      return null;
    }
    if (result.exitCode != 0) {
      fail('compiling the fake texture table failed:\n${result.stderr}');
    }
    return TextureTable._(DynamicLibrary.open(library));
  }

  static String _source() {
    // `flutter test` runs from the package; a workspace run may not.
    const relative = 'test/support/fake_texture_table.c';
    for (final base in [
      Directory.current.path,
      '${Directory.current.path}/packages/lottie_decoder',
    ]) {
      if (File('$base/$relative').existsSync()) return '$base/$relative';
    }
    throw StateError('$relative not found from ${Directory.current.path}');
  }

  /// The lock and post a render isolate calls.
  final FrameTextureEntryPoints entryPoints;

  final int Function(int, int, int, int) _new;
  final Pointer<Uint8> Function(int) _pixels;
  final int Function(int) _stride;
  final int Function(int) _posts;
  final int Function(int) _isLocked;
  final void Function(int, int) _refuse;

  /// A new texture of [width] x [height] pixels, rows padded by [padding]
  /// pixels, every byte [fill]; its id.
  int create(int width, int height, {int padding = 0, int fill = 0}) {
    final id = _new(width, height, padding, fill);
    if (id == 0) throw StateError('the fake texture table is full');
    return id;
  }

  /// Bytes from one row of texture [id] to the next.
  int strideOf(int id) => _stride(id);

  /// The bytes of texture [id], every row with its padding.
  Uint8List pixelsOf(int id, int height) =>
      _pixels(id).asTypedList(strideOf(id) * height);

  /// The four bytes of pixel ([x], [y]) of texture [id].
  List<int> pixelAt(int id, int x, int y) {
    final at = y * strideOf(id) + x * 4;
    return _pixels(id).asTypedList(at + 4).sublist(at);
  }

  /// How many times texture [id] was posted.
  int postsOf(int id) => _posts(id);

  /// Whether texture [id] is locked now.
  bool isLocked(int id) => _isLocked(id) != 0;

  /// Makes every lock of texture [id] fail (or stop failing).
  void refuseLocks(int id, {bool refuse = true}) => _refuse(id, refuse ? 1 : 0);
}

/// A [FrameTextureHost] over a [TextureTable]: real entry points a render
/// isolate can call, textures made at once.
final class TableTextureHost implements FrameTextureHost {
  /// Creates a host over [table] that locks in [format].
  TableTextureHost(this.table, {this.format = FrameTextureFormat.rgba8888});

  /// The table the textures live in.
  final TextureTable table;

  @override
  final FrameTextureFormat format;

  @override
  int get buffersPerTexture => 1;

  @override
  FrameTextureEntryPoints get entryPoints => table.entryPoints;

  @override
  Future<int?> create(int width, int height) async =>
      table.create(width, height, fill: 0x77);

  // The UI isolate never locks here: the render isolates do.
  @override
  FrameTextureTarget? lock(int id) => throw UnimplementedError();

  @override
  void post(int id) => throw UnimplementedError();

  // The table keeps its memory for the process: a test's textures are few.
  @override
  void destroy(int id) {}
}
