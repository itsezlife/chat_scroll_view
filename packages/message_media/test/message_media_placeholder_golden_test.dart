@Tags(<String>['golden'])
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

Widget _box({required Widget child, double width = 420, double height = 480}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF121215),
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ColoredBox(
              color: const Color(0xFF121215),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );

void main() {
  // Golden baselines are Linux-only (same policy as example goldens).
  final skipGoldens = !Platform.isLinux;

  group('message_media placeholder goldens', () {
    testWidgets('single 16:9', (tester) async {
      await tester.pumpWidget(
        _box(
          child: const MessageMediaPlaceholder.single(
            aspectRatio: 16 / 9,
            maxWidth: 300,
          ),
        ),
      );
      await expectLater(
        find.byType(MessageMediaPlaceholder),
        matchesGoldenFile('goldens/single_16x9.png'),
      );
    }, skip: skipGoldens);

    testWidgets('album 2× square', (tester) async {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
      );
      await tester.pumpWidget(
        _box(child: MessageMediaPlaceholder.mosaic(mosaic: mosaic)),
      );
      await expectLater(
        find.byType(MessageMediaPlaceholder),
        matchesGoldenFile('goldens/album_2_square.png'),
      );
    }, skip: skipGoldens);

    testWidgets('album 2× wide stacked', (tester) async {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 2),
          GroupedMediaMember(aspectRatio: 2),
        ],
      );
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
      );
      await tester.pumpWidget(
        _box(child: MessageMediaPlaceholder.mosaic(mosaic: mosaic)),
      );
      await expectLater(
        find.byType(MessageMediaPlaceholder),
        matchesGoldenFile('goldens/album_2_wide_stacked.png'),
      );
    }, skip: skipGoldens);

    testWidgets('album 3× first wide', (tester) async {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 1.5),
          GroupedMediaMember(aspectRatio: 1),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
      );
      await tester.pumpWidget(
        _box(
          height: 560,
          child: MessageMediaPlaceholder.mosaic(mosaic: mosaic),
        ),
      );
      await expectLater(
        find.byType(MessageMediaPlaceholder),
        matchesGoldenFile('goldens/album_3_first_wide.png'),
      );
    }, skip: skipGoldens);

    testWidgets('album 3× first narrow sibling', (tester) async {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 0.5),
          GroupedMediaMember(aspectRatio: 1),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
      );
      await tester.pumpWidget(
        _box(
          height: 560,
          child: MessageMediaPlaceholder.mosaic(mosaic: mosaic),
        ),
      );
      await expectLater(
        find.byType(MessageMediaPlaceholder),
        matchesGoldenFile('goldens/album_3_first_narrow.png'),
      );
    }, skip: skipGoldens);

    testWidgets('album awkward forceCalc', (tester) async {
      final grouped = GroupedMessages.calculate(
        members: const [
          GroupedMediaMember(aspectRatio: 2.5),
          GroupedMediaMember(aspectRatio: 2.5),
          GroupedMediaMember(aspectRatio: 1),
        ],
      );
      final mosaic = MosaicLayout.project(
        positions: grouped.positions,
        mosaicWidth: 300,
      );
      await tester.pumpWidget(
        _box(
          height: 560,
          child: MessageMediaPlaceholder.mosaic(mosaic: mosaic),
        ),
      );
      await expectLater(
        find.byType(MessageMediaPlaceholder),
        matchesGoldenFile('goldens/album_awkward.png'),
      );
    }, skip: skipGoldens);
  });
}
