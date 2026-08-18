import 'package:chat_scroll_view_example/src/features/chat/theme/demo_chat_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demoScrollThemeForWidth follows Material window size classes', () {
    expect(
      identical(demoScrollThemeForWidth(390), DemoChatThemes.compact),
      isTrue,
    );
    expect(
      identical(demoScrollThemeForWidth(700), DemoChatThemes.medium),
      isTrue,
    );
    expect(
      identical(demoScrollThemeForWidth(1200), DemoChatThemes.expanded),
      isTrue,
    );
  });
}
