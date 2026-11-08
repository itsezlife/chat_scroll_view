import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/media_panel_pages.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/panel_texture_warmer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

PanelPage _page(String id) => PanelPage(
  id: id,
  tab: PanelTab(icon: ChromeIconId(id), labelKey: id),
  builder: (context, host) => const SizedBox(),
);

void main() {
  late FakeFrameTextureHost host;
  late PanelShellController shell;

  setUp(() {
    host = FakeFrameTextureHost();
    final pool = FrameTexturePool(host: host);
    addTearDown(pool.dispose);
    shell = PanelShellController(
      pages: [
        _page('emoji'),
        _page(MediaPanelPages.gifId),
        _page(MediaPanelPages.stickersId),
      ],
      preferences: FakePreferenceStore(),
    );
    addTearDown(shell.dispose);
    final warmer = PanelTextureWarmer(
      shell: shell,
      pool: pool,
      devicePixelRatio: 3,
    );
    addTearDown(warmer.dispose);
  });

  void open() => shell.updatePresence(visible: true, opening: false);

  test('warms the sticker class when the panel opens on the stickers '
      'page', () async {
    shell.selectPage(MediaPanelPages.stickersId);

    open();
    await pumpEventQueue();

    // A sticker is drawn 66 points square: 198 px at 3x, in the 256 class.
    expect(host.created, hasLength(20));
    expect(host.created.toSet(), {(width: 256, height: 256)});
  });

  test('warms the GIF class when the GIF page is selected in the open '
      'panel', () async {
    open();
    await pumpEventQueue();
    expect(host.created, isEmpty, reason: 'the emoji page plays nothing');

    shell.selectPage(MediaPanelPages.gifId);
    await pumpEventQueue();

    // A GIF row is 100 points tall: 300 px at 3x, in the 384 class.
    expect(host.created, hasLength(8));
    expect(host.created.toSet(), {(width: 384, height: 384)});
  });

  test('warms nothing while the panel is hidden', () async {
    shell.selectPage(MediaPanelPages.stickersId);
    await pumpEventQueue();

    expect(host.created, isEmpty);
  });
}
