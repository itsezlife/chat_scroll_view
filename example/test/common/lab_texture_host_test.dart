import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/common/scroll_lab.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts the textures created while a surface scrolls', () async {
    final platform = FakeFrameTextureHost();
    final scrolling = ValueNotifier<bool>(false);
    addTearDown(scrolling.dispose);
    final host = LabTextureHost(platform, scrolling);

    await host.create(64, 64);
    scrolling.value = true;
    await host.create(128, 128);
    await host.create(128, 128);

    expect(host.created, 3);
    expect(host.createdWhileScrolling, 2);
    expect(platform.created, hasLength(3));
  });
}
