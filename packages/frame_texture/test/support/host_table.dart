import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_texture/frame_texture.dart';
import 'package:frame_texture/src/ffi_frame_texture_natives.dart';

/// The real texture table (`native/src/frame_texture.c`) compiled for this
/// machine with a fake window (`native/test/fake_window.c`) in place of
/// Android's, and the plugin's side played over a mock channel: what the
/// Kotlin plugin does on a device, minus the producer.
final class HostTable {
  HostTable._(this.library)
    : natives = FfiFrameTextureNatives(library),
      _attach = library
          .lookupFunction<
            Int32 Function(Int64, Pointer<Void>, Int32, Int32),
            int Function(int, Pointer<Void>, int, int)
          >('frame_texture_attach'),
      _detach = library
          .lookupFunction<Void Function(Int64), void Function(int)>(
            'frame_texture_detach',
          ),
      _forget = library
          .lookupFunction<Void Function(Int64), void Function(int)>(
            'frame_texture_forget',
          ),
      _newWindow = library
          .lookupFunction<
            Pointer<Void> Function(Int32),
            Pointer<Void> Function(int)
          >('fake_window_new'),
      liveWindows = library.lookupFunction<Int32 Function(), int Function()>(
        'fake_window_live',
      ),
      _refuseLocks = library
          .lookupFunction<
            Void Function(Pointer<Void>, Int32),
            void Function(Pointer<Void>, int)
          >('fake_window_refuse_locks'),
      _forceFormat = library
          .lookupFunction<
            Void Function(Pointer<Void>, Int32),
            void Function(Pointer<Void>, int)
          >('fake_window_force_format'),
      _posts = library
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('fake_window_posts');

  /// Compiles the table once per test process, or answers null with the
  /// reason when this machine has no C compiler.
  static HostTable? compile() => _compiled ??= _compile();
  static HostTable? _compiled;

  /// Why [compile] answered null, for a skip message.
  static String skipReason = '';

  static HostTable? _compile() {
    final package = _packageRoot();
    final out = Directory.systemTemp.createTempSync('frame_texture_table');
    final library =
        '${out.path}/libframe_texture_host'
        '${Platform.isMacOS ? '.dylib' : '.so'}';
    final ProcessResult result;
    try {
      result = Process.runSync('cc', [
        '-shared',
        '-fPIC',
        '-std=c11',
        '-Wall',
        '-Wextra',
        '-Werror',
        '-fvisibility=hidden',
        '-DFRAME_TEXTURE_TESTING',
        '-I${package.path}/native/include',
        '${package.path}/native/src/frame_texture.c',
        '${package.path}/native/test/fake_window.c',
        if (Platform.isLinux) '-lpthread',
        '-o',
        library,
      ]);
    } on ProcessException catch (error) {
      skipReason = 'no C compiler (cc) here: $error';
      return null;
    }
    if (result.exitCode != 0) {
      // A compiler that is there and fails is a broken table, not a skip.
      fail('compiling the texture table failed:\n${result.stderr}');
    }
    return HostTable._(DynamicLibrary.open(library));
  }

  static Directory _packageRoot() {
    // `flutter test` runs from the package; a workspace run may not.
    var directory = Directory.current;
    while (!File('${directory.path}/native/src/frame_texture.c').existsSync()) {
      final candidate = Directory('${directory.path}/packages/frame_texture');
      if (candidate.existsSync()) return candidate;
      directory = directory.parent;
    }
    return directory;
  }

  final DynamicLibrary library;

  /// The table as the Dart host binds it.
  final FfiFrameTextureNatives natives;

  /// Windows not freed yet: every reference the table took was given back
  /// when it is back to what it was.
  final int Function() liveWindows;

  final int Function(int, Pointer<Void>, int, int) _attach;
  final void Function(int) _detach;
  final void Function(int) _forget;
  final Pointer<Void> Function(int) _newWindow;
  final void Function(Pointer<Void>, int) _refuseLocks;
  final void Function(Pointer<Void>, int) _forceFormat;
  final int Function(Pointer<Void>) _posts;

  /// A new window with [rowPadding] pixels after each row, one reference
  /// held by the caller (as `ANativeWindow_fromSurface` gives).
  Pointer<Void> newWindow({int rowPadding = 0}) => _newWindow(rowPadding);

  /// `frame_texture_attach`: takes over the reference to [window].
  int attach(int id, Pointer<Void> window, int width, int height) =>
      _attach(id, window, width, height);

  /// `frame_texture_detach`.
  void detach(int id) => _detach(id);

  /// `frame_texture_forget`.
  void forget(int id) => _forget(id);

  /// Makes the platform refuse every lock of [window] (or stop refusing).
  void refuseLocks(Pointer<Void> window, {bool refuse = true}) =>
      _refuseLocks(window, refuse ? 1 : 0);

  /// Makes every lock of [window] give a buffer of [format].
  void forceFormat(Pointer<Void> window, int format) =>
      _forceFormat(window, format);

  /// How many buffers of [window] were posted.
  int postsOf(Pointer<Void> window) => _posts(window);
}

/// The plugin's side of the channel, over a [HostTable]: `create` makes a
/// window and attaches it under a new id, `destroy` forgets the id. Ids are
/// unique across every platform of a test run, as the engine's are.
final class FakeTexturePlatform {
  FakeTexturePlatform(this.table, {this.rowPadding = 0});

  final HostTable table;

  /// Pixels after each row of every window it makes.
  final int rowPadding;

  /// Whether `create` answers null, as a platform that cannot make one.
  bool refuseCreations = false;

  /// The windows of the live textures, by id (the table holds the only
  /// reference).
  final Map<int, Pointer<Void>> windows = {};

  /// Every id `destroy` was called with.
  final List<int> destroyed = [];

  static int _nextId = 1;

  static const MethodChannel channel = MethodChannel(
    PlatformFrameTextureHost.channelName,
  );

  /// Answers the channel until the test ends.
  void install() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(channel, _answer);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  /// A host over this platform.
  PlatformFrameTextureHost host() {
    install();
    return PlatformFrameTextureHost(channel: channel, natives: table.natives);
  }

  Future<Object?> _answer(MethodCall call) async {
    switch (call.method) {
      case 'create':
        if (refuseCreations) return null;
        final arguments = call.arguments as Map<Object?, Object?>;
        final width = arguments['width']! as int;
        final height = arguments['height']! as int;
        final id = _nextId++;
        final window = table.newWindow(rowPadding: rowPadding);
        final status = table.attach(id, window, width, height);
        if (status != 0) return null;
        windows[id] = window;
        return id;
      case 'destroy':
        final id = call.arguments as int;
        destroyed.add(id);
        windows.remove(id);
        table.forget(id);
        return null;
    }
    throw MissingPluginException();
  }
}
