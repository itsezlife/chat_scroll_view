import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/scrolling_surfaces.dart';
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

/// A chat controller whose scroll events the test sends, as the viewport
/// would.
final class _ScriptedChat extends ChatScrollController {
  final _listeners = <ValueChanged<ChatScrollEvent>>[];

  @override
  void addScrollListener(ValueChanged<ChatScrollEvent> callback) =>
      _listeners.add(callback);

  @override
  void removeScrollListener(ValueChanged<ChatScrollEvent> callback) =>
      _listeners.remove(callback);

  void emit(ChatScrollEvent event) {
    for (final listener in List.of(_listeners)) {
      listener(event);
    }
  }
}

void main() {
  late ScrollingSurfaces surfaces;

  setUp(() {
    surfaces = ScrollingSurfaces();
    addTearDown(surfaces.dispose);
  });

  group('the chat list', () {
    late _ScriptedChat chat;

    setUp(() {
      chat = _ScriptedChat();
      addTearDown(chat.dispose);
      addTearDown(surfaces.followChat(chat));
    });

    test('scrolls from the drag start', () {
      expect(surfaces.value, isFalse);

      chat.emit(const ChatUserDragStart());

      expect(surfaces.value, isTrue);
    });

    test('rests when a drag ends without a fling', () async {
      chat
        ..emit(const ChatUserDragStart())
        ..emit(const ChatUserDragEnd(0));
      await pumpEventQueue();

      expect(surfaces.value, isFalse);
    });

    test('scrolls through the hand-over from drag to fling, until the fling '
        'ends', () async {
      final seen = <bool>[];
      surfaces.addListener(() => seen.add(surfaces.value));

      // The viewport emits the drag end and the fling start in one call.
      chat
        ..emit(const ChatUserDragStart())
        ..emit(const ChatUserDragEnd(900))
        ..emit(const ChatFlingStart(900));
      await pumpEventQueue();
      expect(surfaces.value, isTrue);

      chat.emit(const ChatFlingEnd());
      await pumpEventQueue();

      expect(surfaces.value, isFalse);
      expect(seen, [true, false]);
    });

    test('scrolls while an animated scroll flies', () {
      chat.emit(const ChatAnimateStart(1, Duration.zero));
      expect(surfaces.value, isTrue);

      chat.emit(const ChatAnimateEnd(1));
      return pumpEventQueue().then((_) => expect(surfaces.value, isFalse));
    });

    test('rests once no longer followed', () {
      final other = _ScriptedChat();
      addTearDown(other.dispose);
      final stop = surfaces.followChat(other);
      other.emit(const ChatUserDragStart());

      stop();

      expect(surfaces.value, isFalse);
    });
  });

  group('the panel', () {
    late PanelShellController shell;

    setUp(() {
      shell = PanelShellController(
        pages: [_page('gif'), _page('stickers')],
        preferences: FakePreferenceStore(),
      );
      addTearDown(shell.dispose);
      addTearDown(surfaces.followPanel(shell));
    });

    test('scrolls while its page drags or flings, rests when it is idle', () {
      final gif = shell.hostFor('gif');

      gif.reportScrollActivity(const PageScrollDrag(4));
      expect(surfaces.value, isTrue);
      gif.reportScrollActivity(const PageScrollFling(12));
      expect(surfaces.value, isTrue);

      gif.reportScrollActivity(const PageScrollIdle());
      expect(surfaces.value, isFalse);
    });

    test('rests when another page is selected mid-scroll', () {
      shell.hostFor('gif').reportScrollActivity(const PageScrollFling(12));

      shell.selectPage('stickers');

      expect(surfaces.value, isFalse);
    });

    test('and the chat list scroll together: it rests when both rest', () {
      final chat = _ScriptedChat();
      addTearDown(chat.dispose);
      addTearDown(surfaces.followChat(chat));
      chat.emit(const ChatUserDragStart());
      shell.hostFor('gif').reportScrollActivity(const PageScrollDrag(4));

      shell.hostFor('gif').reportScrollActivity(const PageScrollIdle());
      expect(surfaces.value, isTrue);

      chat.emit(const ChatUserDragEnd(0));
      return pumpEventQueue().then((_) => expect(surfaces.value, isFalse));
    });
  });
}
