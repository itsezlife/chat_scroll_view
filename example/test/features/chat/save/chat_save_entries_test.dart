/// The save entries' defaults: one entry per kind and platform, with its
/// label and destination, and the batches each platform offers.
library;

import 'package:chat_scroll_view_example/src/app/app_platform_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_entries.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_library/mpx_library.dart';

void main() {
  const gallery = SaveDestination.gallery(album: ChatSaveWiring.subfolder);
  const downloads = ChatSaveWiring.downloads;
  const ask = SaveDestination.ask();

  ({String label, SaveDestination destination}) of(ChatSaveEntry entry) =>
      (label: entry.label, destination: entry.destination);

  test('Android saves pictures to the gallery, animations and files to '
      'Downloads', () {
    final entries = ChatSaveEntries.forPlatform(
      const AppPlatformPolicy.android(),
    );
    expect(of(entries.entryOf(MediaItemKind.photo)), (
      label: 'Save to Gallery',
      destination: gallery,
    ));
    expect(of(entries.entryOf(MediaItemKind.video)), (
      label: 'Save to Gallery',
      destination: gallery,
    ));
    expect(of(entries.entryOf(MediaItemKind.animation)), (
      label: 'Save to Downloads',
      destination: downloads,
    ));
    expect(of(entries.entryOf(MediaItemKind.file)), (
      label: 'Save to Downloads',
      destination: downloads,
    ));
    expect(of(entries.entryOf(const MediaItemKind.custom('voice'))), (
      label: 'Save to Downloads',
      destination: downloads,
    ));
  });

  test('iOS saves pictures to the gallery without an album and files to '
      'Files', () {
    final entries = ChatSaveEntries.forPlatform(const AppPlatformPolicy.iOS());
    expect(of(entries.entryOf(MediaItemKind.photo)), (
      label: 'Save Image',
      destination: const SaveDestination.gallery(),
    ));
    expect(of(entries.entryOf(MediaItemKind.video)), (
      label: 'Save Video',
      destination: const SaveDestination.gallery(),
    ));
    expect(of(entries.entryOf(MediaItemKind.animation)), (
      label: 'Save GIF',
      destination: const SaveDestination.gallery(),
    ));
    expect(of(entries.entryOf(MediaItemKind.file)), (
      label: 'Save to Files',
      destination: downloads,
    ));
  });

  test('desktop and the web ask where every kind goes', () {
    for (final platform in [
      const AppPlatformPolicy.desktop(),
      const AppPlatformPolicy.web(),
    ]) {
      final entries = ChatSaveEntries.forPlatform(platform);
      expect(of(entries.entryOf(MediaItemKind.photo)), (
        label: 'Save Image As…',
        destination: ask,
      ));
      expect(of(entries.entryOf(MediaItemKind.video)), (
        label: 'Save As',
        destination: ask,
      ));
      expect(of(entries.entryOf(MediaItemKind.animation)), (
        label: 'Save GIF',
        destination: ask,
      ));
      expect(of(entries.entryOf(MediaItemKind.file)), (
        label: 'Save As',
        destination: ask,
      ));
    }
    expect(
      ChatSaveEntries.forPlatform(const AppPlatformPolicy.web()).platform,
      'web',
    );
  });

  test('only Android saves a message selection of files, to Downloads', () {
    expect(
      of(
        ChatSaveEntries.forPlatform(
          const AppPlatformPolicy.android(),
        ).selection!,
      ),
      (label: 'Save to Downloads', destination: downloads),
    );
    for (final platform in [
      const AppPlatformPolicy.iOS(),
      const AppPlatformPolicy.desktop(),
      const AppPlatformPolicy.web(),
    ]) {
      expect(ChatSaveEntries.forPlatform(platform).selection, isNull);
    }
  });

  test('an album offers the entry its items share, none when they differ', () {
    final entries = ChatSaveEntries.forPlatform(
      const AppPlatformPolicy.android(),
    );
    expect(
      entries.sharedEntryOf([MediaItemKind.photo, MediaItemKind.video]),
      entries.entryOf(MediaItemKind.photo),
    );
    expect(
      entries.sharedEntryOf([MediaItemKind.photo, MediaItemKind.animation]),
      isNull,
    );
    expect(entries.sharedEntryOf(const []), isNull);
  });
}
