import 'dart:async';
import 'dart:typed_data';

import 'package:catalog_assets/src/texture/frame_texture_host.dart';

/// A [FrameTextureHost] over plain memory that records what is asked of it.
///
/// Each texture is a [Uint8List] of `width * height * 4` bytes, rows packed
/// ([rowPadding] bytes apart beyond that, to catch a writer that assumes
/// packed rows); [pixelsOf] gives it to a test as the writer would see it.
/// A target's [FrameTextureTarget.address] is a made-up number, unique per
/// texture, never a real address: nothing native may read it.
///
/// Creation answers on the next microtask, like a platform call; with
/// [holdCreations] it waits until [completeCreations], so a test sees a
/// creation in flight. [refuseCreations] makes [create] answer null, and
/// [refuseLocks] makes [lock] answer null, as a platform that refuses would.
final class FakeFrameTextureHost implements FrameTextureHost {
  /// Creates a host.
  FakeFrameTextureHost({
    this.format = FrameTextureFormat.rgba8888,
    this.buffersPerTexture = 1,
    this.rowPadding = 0,
  });

  @override
  final FrameTextureFormat format;

  @override
  final int buffersPerTexture;

  /// Bytes after each row's pixels.
  final int rowPadding;

  @override
  FrameTextureEntryPoints? get entryPoints => null;

  /// Whether [create] answers null.
  bool refuseCreations = false;

  /// Whether [lock] answers null.
  bool refuseLocks = false;

  /// Whether a creation waits for [completeCreations].
  bool holdCreations = false;

  /// The size of every [create] call, in order, refused ones included.
  final List<({int width, int height})> created = [];

  /// Every id [destroy] was called with, in order.
  final List<int> destroyed = [];

  /// Every id [post] published, in order.
  final List<int> posts = [];

  final Map<int, _FakeTexture> _textures = {};
  final List<Completer<void>> _held = [];
  int _nextId = 1;

  /// The ids of the live textures.
  Iterable<int> get liveIds => _textures.keys;

  /// The bytes of texture [id], rows [FrameTextureTarget.rowStride] apart, or
  /// null for an id that is not live.
  Uint8List? pixelsOf(int id) => _textures[id]?.pixels;

  /// Whether texture [id] is locked now.
  bool isLocked(int id) => _textures[id]?.locked ?? false;

  /// Lets every held creation answer.
  void completeCreations() {
    final held = List<Completer<void>>.of(_held);
    _held.clear();
    for (final completer in held) {
      completer.complete();
    }
  }

  @override
  Future<int?> create(int width, int height) async {
    created.add((width: width, height: height));
    if (holdCreations) {
      final completer = Completer<void>();
      _held.add(completer);
      await completer.future;
    } else {
      await Future<void>.value();
    }
    if (refuseCreations) return null;
    final id = _nextId++;
    final stride = width * 4 + rowPadding;
    _textures[id] = _FakeTexture(width, height, Uint8List(stride * height));
    return id;
  }

  @override
  FrameTextureTarget? lock(int id) {
    final texture = _textures[id];
    if (texture == null || texture.locked || refuseLocks) return null;
    texture.locked = true;
    return FrameTextureTarget(
      address: id << 20,
      rowStride: texture.width * 4 + rowPadding,
      format: format,
      width: texture.width,
      height: texture.height,
    );
  }

  @override
  void post(int id) {
    final texture = _textures[id];
    if (texture == null || !texture.locked) return;
    texture.locked = false;
    posts.add(id);
  }

  @override
  void destroy(int id) {
    if (_textures.remove(id) == null) return;
    destroyed.add(id);
  }
}

final class _FakeTexture {
  _FakeTexture(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final Uint8List pixels;
  bool locked = false;
}
