import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selected_page persists across store reloads', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      KeyboardPanelStore.selectedPageKey: KeyboardPanelTab.stickers.prefsPage,
    });
    final store = KeyboardPanelStore(defaultHeight: 200);
    await store.load();
    expect(store.selectedPage, KeyboardPanelTab.stickers.prefsPage);

    await store.setSelectedPage(KeyboardPanelTab.emoji.prefsPage);

    final reloaded = KeyboardPanelStore(defaultHeight: 200);
    await reloaded.load();
    expect(reloaded.selectedPage, KeyboardPanelTab.emoji.prefsPage);
  });
}
