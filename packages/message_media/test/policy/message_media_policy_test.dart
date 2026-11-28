/// The policy's platform defaults and its replaceable layout step.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

import '../support/media_scopes.dart';

void main() {
  test('each family carries its own layout defaults', () {
    const android = MessageMediaPolicy.android();
    expect(android.family, MessageMediaPlatform.android);
    expect(android.layoutStep, isA<MediaLayoutPolicy>());
    expect(
      (android.layoutStep as MediaLayoutPolicy).box,
      isA<MediaBoxSizing$Android>(),
    );
    const ios = MessageMediaPolicy.ios();
    expect(ios.family, MessageMediaPlatform.ios);
    expect(
      (ios.layoutStep as MediaLayoutPolicy).box,
      isA<MediaBoxSizing$IOS>(),
    );
    const desktop = MessageMediaPolicy.desktop();
    expect(desktop.family, MessageMediaPlatform.desktop);
    expect(
      (desktop.layoutStep as MediaLayoutPolicy).box,
      isA<MediaBoxSizing$Desktop>(),
    );
  });

  test(
    'forPlatform maps Android and iOS to their own, the rest to desktop',
    () {
      expect(
        MessageMediaPolicy.forPlatform(TargetPlatform.android).family,
        MessageMediaPlatform.android,
      );
      expect(
        MessageMediaPolicy.forPlatform(TargetPlatform.iOS).family,
        MessageMediaPlatform.ios,
      );
      for (final platform in const [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          MessageMediaPolicy.forPlatform(platform).family,
          MessageMediaPlatform.desktop,
        );
      }
    },
  );

  test('platform() follows the running platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(MessageMediaPolicy.platform().family, MessageMediaPlatform.ios);
  });

  MediaLayoutInput empty() => MediaLayoutInput(
    text: MediaScopes.text,
    items: const [],
    availableWidth: 300,
  );

  test('copyWith replaces the layout step whole', () {
    final step = _ConstantStep();
    final policy = const MessageMediaPolicy.android().copyWith(
      layoutStep: step,
    );
    expect(policy.layoutStep, same(step));
    expect(policy.family, MessageMediaPlatform.android);
    expect(policy.layout(empty()), same(_ConstantStep.result));
  });

  test('a host step keeps the file rows and the card the policy holds: it '
      'is handed them, and the cells draw by the same', () {
    final step = _ConstantStep();
    const rows = MediaFileStackPolicy.ios();
    const card = LinkPreviewCardPolicy.desktop();
    final policy = const MessageMediaPolicy.android().copyWith(
      layoutStep: step,
      fileStack: rows,
      linkPreview: card,
    );
    policy.layout(empty());
    expect(step.fileStacks, [same(rows)]);
    expect(step.cards, [same(card)]);
    expect(policy.fileStack, same(rows));
    expect(policy.linkPreview, same(card));
  });
}

final class _ConstantStep implements MediaLayoutStep {
  _ConstantStep();

  static final result = MediaLayout.empty;

  final fileStacks = <MediaFileStackPolicy>[];
  final cards = <LinkPreviewCardPolicy>[];

  @override
  MediaLayout layout(
    MediaLayoutInput input, {
    required MediaFileStackPolicy fileStack,
    required LinkPreviewCardPolicy linkPreview,
  }) {
    fileStacks.add(fileStack);
    cards.add(linkPreview);
    return result;
  }
}
