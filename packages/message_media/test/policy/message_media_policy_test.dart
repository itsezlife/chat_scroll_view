/// The policy's platform defaults and its replaceable layout step.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

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

  test('copyWith replaces the layout step whole', () {
    const step = _ConstantStep();
    final policy = const MessageMediaPolicy.android().copyWith(
      layoutStep: step,
    );
    expect(policy.layoutStep, same(step));
    expect(policy.family, MessageMediaPlatform.android);
    expect(
      policy.layout(MediaLayoutInput(items: const [], availableWidth: 300)),
      same(_ConstantStep.result),
    );
  });
}

final class _ConstantStep implements MediaLayoutStep {
  const _ConstantStep();

  static final result = MediaLayout.empty;

  @override
  MediaLayout layout(MediaLayoutInput input) => result;
}
