import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  const thumbs = ContentKey.unicode('1F44D');

  test('events with the same parts are equal', () {
    expect(
      const ContentPicked(key: thumbs, kind: SemanticKind.unicodeEmoji),
      const ContentPicked(key: thumbs, kind: SemanticKind.unicodeEmoji),
    );
    expect(
      const ActionInvoked(pageId: 'a', actionId: 'b').hashCode,
      const ActionInvoked(pageId: 'a', actionId: 'b').hashCode,
    );
    expect(const PageChanged('a'), const PageChanged('a'));
    expect(const BackspaceRequested(), const BackspaceRequested());
    expect(const SearchOpened(), const SearchOpened());
    expect(const SearchClosed(), const SearchClosed());
    expect(
      const ClearRecentsRequested(kind: SemanticKind.sticker),
      const ClearRecentsRequested(kind: SemanticKind.sticker),
    );
    expect(
      const ContentCopyRequested(key: thumbs, kind: SemanticKind.unicodeEmoji),
      const ContentCopyRequested(key: thumbs, kind: SemanticKind.unicodeEmoji),
    );
    expect(
      const RecentRemoveRequested(
        key: thumbs,
        kind: SemanticKind.unicodeEmoji,
      ).hashCode,
      const RecentRemoveRequested(
        key: thumbs,
        kind: SemanticKind.unicodeEmoji,
      ).hashCode,
    );
  });

  test('events that differ in a part are not equal', () {
    expect(
      const ContentPicked(key: thumbs, kind: SemanticKind.unicodeEmoji),
      isNot(
        const ContentPicked(
          key: thumbs,
          kind: SemanticKind.unicodeEmoji,
          source: PickSource.search,
        ),
      ),
    );
    expect(const PageChanged('a'), isNot(const PageChanged('b')));
    expect(const SearchOpened(), isNot(const SearchClosed()));
    expect(
      const ContentCopyRequested(key: thumbs, kind: SemanticKind.unicodeEmoji),
      isNot(
        const RecentRemoveRequested(
          key: thumbs,
          kind: SemanticKind.unicodeEmoji,
        ),
      ),
    );
  });

  test('a handler can switch over the whole family exhaustively', () {
    String describe(PanelEvent event) => switch (event) {
      ContentPicked() => 'picked',
      BackspaceRequested() => 'backspace',
      ActionInvoked() => 'action',
      ClearRecentsRequested() => 'clear',
      ContentCopyRequested() => 'copy',
      RecentRemoveRequested() => 'remove',
      PageChanged() => 'page',
      SearchOpened() => 'opened',
      SearchClosed() => 'closed',
    };

    expect(describe(const SearchClosed()), 'closed');
  });
}
