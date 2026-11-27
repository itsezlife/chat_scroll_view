import 'package:chat_scroll_view_example/src/features/chat/data/bundled_pack_source.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// One picture of [DemoPhotos]: a JPEG in the app bundle, standing in for a
/// photo a backend serves.
@immutable
final class DemoPhoto implements BundledItem {
  const DemoPhoto._(
    this.name, {
    required int width,
    required int height,
    required this.byteSize,
  }) : _width = width,
       _height = height;

  /// The file's name, without its extension.
  final String name;

  /// Its size in bytes.
  final int byteSize;

  final int _width;
  final int _height;

  /// The name a message sends it under.
  String get fileName => '$name.jpg';

  @override
  ContentKey get key => ContentKey.document('demo-photo:$name');

  /// A still with its size, byte size, file name and media type: what a
  /// backend says of a photo.
  @override
  ContentDescriptor get descriptor => ContentDescriptor(
    key: key,
    mediaForm: MediaForm.still,
    size: ContentSize(_width, _height),
    byteSize: byteSize,
    fileName: fileName,
    mimeType: 'image/jpeg',
  );

  @override
  String get assetPath => 'assets/media_photos/$fileName';
}

/// The pictures the demo chat's media messages send, generated for it from
/// synthetic sources (`assets/media_photos/README.md`), of eight
/// proportions so single boxes and albums lay out every shape.
abstract final class DemoPhotos {
  /// 3:2.
  static const harbour = DemoPhoto._(
    'harbour',
    width: 1280,
    height: 853,
    byteSize: 26794,
  );

  /// 2:3.
  static const cliff = DemoPhoto._(
    'cliff',
    width: 720,
    height: 1080,
    byteSize: 17392,
  );

  /// Square.
  static const meadow = DemoPhoto._(
    'meadow',
    width: 900,
    height: 900,
    byteSize: 16454,
  );

  /// A panorama, 8:3.
  static const skyline = DemoPhoto._(
    'skyline',
    width: 1600,
    height: 600,
    byteSize: 15200,
  );

  /// A tall strip, 5:14.
  static const tower = DemoPhoto._(
    'tower',
    width: 500,
    height: 1400,
    byteSize: 15620,
  );

  /// A small picture, 240 x 180.
  static const pebble = DemoPhoto._(
    'pebble',
    width: 240,
    height: 180,
    byteSize: 2965,
  );

  /// 4:3.
  static const dunes = DemoPhoto._(
    'dunes',
    width: 1200,
    height: 900,
    byteSize: 20699,
  );

  /// 4:5.
  static const lagoon = DemoPhoto._(
    'lagoon',
    width: 1080,
    height: 1350,
    byteSize: 28473,
  );

  /// Every picture.
  static const List<DemoPhoto> all = [
    harbour,
    cliff,
    meadow,
    skyline,
    tower,
    pebble,
    dunes,
    lagoon,
  ];

  static final Map<ContentKey, DemoPhoto> _byKey = {
    for (final photo in all) photo.key: photo,
  };

  /// The picture of [key], or null for content that is not one.
  static DemoPhoto? of(ContentKey key) => _byKey[key];

  /// The descriptor of every picture, for the host's asset pipeline.
  static Iterable<ContentDescriptor> get descriptors =>
      all.map((photo) => photo.descriptor);
}
