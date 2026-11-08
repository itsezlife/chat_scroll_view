/// The one disk store of animated media: a folder the tiers keep their files
/// in, kept by time (and by size, when the host sets a limit).
///
/// **Seam:** [MediaDiskCache] over a temporary folder; a file's time is when
/// it was last used, set here by hand to age it.
library;

import 'dart:io';

import 'package:chat_scroll_view_example/src/app/media_disk_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  final now = DateTime(2026, 11, 9, 12);

  setUp(() => root = Directory.systemTemp.createTempSync('media_disk_'));
  tearDown(() => root.deleteSync(recursive: true));

  // A file of [bytes] bytes at [path] under the root, last used [ago].
  void put(String path, {int bytes = 1, Duration ago = Duration.zero}) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(bytes, 0))
      ..setLastModifiedSync(now.subtract(ago));
  }

  // The files left under the root, as paths below it.
  List<String> left() => [
    for (final entry in root.listSync(recursive: true))
      if (entry is File) entry.path.substring(root.path.length + 1),
  ]..sort();

  MediaDiskCache open({int? limitBytes}) =>
      MediaDiskCache(root.path, limitBytes: limitBytes, clock: () => now);

  test('keeps media for one month by default, with no size limit', () {
    final cache = MediaDiskCache(root.path);

    expect(cache.keepFor, const Duration(days: 30));
    expect(cache.limitBytes, isNull);
  });

  test('names a folder per tier under its root', () {
    expect(open().folder('lottie_frames'), '${root.path}/lottie_frames');
  });

  test('a sweep removes what no tier used for the keep period, in every '
      'tier', () async {
    put('giphy/clip_a', ago: const Duration(days: 31));
    put('giphy/clip_b', ago: const Duration(days: 29));
    put('lottie_frames/x.frames', ago: const Duration(days: 40));
    put('lottie_frames/y.frames');

    await open().sweep();

    expect(left(), ['giphy/clip_b', 'lottie_frames/y.frames']);
  });

  test('with no limit, keeps any size used within the period', () async {
    put('giphy/clip_a', bytes: 4096, ago: const Duration(days: 10));
    put('giphy/clip_b', bytes: 4096);

    await open().sweep();

    expect(left(), ['giphy/clip_a', 'giphy/clip_b']);
  });

  test('with a limit, removes the least recently used across the tiers '
      'until the rest fits', () async {
    put('giphy/clip_a', bytes: 4, ago: const Duration(days: 3));
    put('lottie_frames/x.frames', bytes: 4, ago: const Duration(days: 2));
    put('giphy/still_a', bytes: 4, ago: const Duration(days: 1));

    await open(limitBytes: 8).sweep();

    expect(left(), ['giphy/still_a', 'lottie_frames/x.frames']);
  });

  test('a limit spares a file used a moment ago: a write may be landing '
      'it', () async {
    put('giphy/clip_a', bytes: 4, ago: const Duration(seconds: 5));
    put('giphy/clip_b.part', bytes: 4, ago: const Duration(seconds: 1));

    await open(limitBytes: 2).sweep();

    expect(left(), ['giphy/clip_a', 'giphy/clip_b.part']);
  });

  test('a sweep of a root never made finds nothing, and never throws', () {
    expect(
      MediaDiskCache('${root.path}/never', clock: () => now).sweep(),
      completes,
    );
  });

  test('sweeps when started and again every period until disposed', () async {
    final cache = MediaDiskCache(
      root.path,
      sweepEvery: const Duration(milliseconds: 40),
    )..start();
    addTearDown(cache.dispose);
    put('giphy/clip_a', ago: const Duration(days: 60));
    // The first sweep may have run before the file was there; a later one
    // finds it.
    for (var i = 0; i < 50 && left().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(left(), isEmpty);

    cache.dispose();
    put('giphy/clip_b', ago: const Duration(days: 60));
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(left(), ['giphy/clip_b']);
  });

  group('retired folders', () {
    late Directory cache;

    setUp(() {
      cache = Directory.systemTemp.createTempSync('app_cache_');
      for (final path in [
        'giphy_stills/a',
        'giphy_clips/b',
        'lottie_frames/c',
        'media/lottie_frames/d',
        'media/giphy/e',
      ]) {
        File('${cache.path}/$path')
          ..createSync(recursive: true)
          ..setLastModifiedSync(now);
      }
    });
    tearDown(() => cache.deleteSync(recursive: true));

    MediaDiskCache store() => MediaDiskCache(
      '${cache.path}/media',
      retiredFolders: [
        for (final name in ['giphy_stills', 'giphy_clips', 'lottie_frames'])
          '${cache.path}/$name',
      ],
      clock: () => now,
    );

    List<String> entries() => [
      for (final entry in cache.listSync(recursive: true))
        entry.path.substring(cache.path.length + 1),
    ]..sort();

    test('the first sweep deletes them and leaves the store alone', () async {
      await store().sweep();

      expect(entries(), [
        'media',
        'media/giphy',
        'media/giphy/e',
        'media/lottie_frames',
        'media/lottie_frames/d',
      ]);
    });

    test('a sweep when they are already gone is fine', () async {
      await store().sweep();
      await store().sweep();

      expect(entries(), hasLength(5));
    });
  });
}
