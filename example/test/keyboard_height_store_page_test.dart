import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('selected_page persists across store reloads', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'chat_chrome_emoji_selected_page': EmojiPanelTab.stickers.prefsPage,
    });
    final store = KeyboardHeightStore(defaultHeight: 200);
    await store.load();
    expect(store.selectedPage, EmojiPanelTab.stickers.prefsPage);

    await store.setSelectedPage(EmojiPanelTab.emoji.prefsPage);

    final reloaded = KeyboardHeightStore(defaultHeight: 200);
    await reloaded.load();
    expect(reloaded.selectedPage, EmojiPanelTab.emoji.prefsPage);
  });
}
