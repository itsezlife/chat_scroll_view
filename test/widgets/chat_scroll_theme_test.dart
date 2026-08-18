import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_message_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scrollbar.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'c$i',
);

class _Src extends ChatDataSource {
  _Src() {
    upsertMessage(_msg(0));
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: 0,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

Widget _app({
  ChatScrollThemeData? inherited,
  ChatScrollThemeData? extension,
  Color? highlightColor,
}) {
  Widget home = ChatScrollView(
    dataSource: _Src(),
    controller: ChatScrollController()..jumpTo(0),
    highlightColor: highlightColor,
    messageBuilder: (context, id, message, status, runLayout) =>
        const SizedBox(height: 40),
  );
  if (inherited != null) {
    home = ChatScrollTheme(data: inherited, child: home);
  }
  return MaterialApp(
    theme: ThemeData(
      extensions: extension == null
          ? const <ThemeExtension<dynamic>>[]
          : <ThemeExtension<dynamic>>[extension],
    ),
    home: Scaffold(body: SizedBox(width: 400, height: 400, child: home)),
  );
}

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

void main() {
  testWidgets('package defaults apply when nothing is themed', (tester) async {
    await tester.pumpWidget(_app());
    expect(
      _render(tester).highlightColor,
      ChatScrollThemeData.defaultHighlightColor,
    );
    expect(
      _render(tester).highlightDuration,
      ChatScrollThemeData.defaultHighlightDuration,
    );
  });

  testWidgets('ChatScrollTheme inherited highlightColor is used', (
    tester,
  ) async {
    const color = Color(0x80FF00FF);
    await tester.pumpWidget(
      _app(inherited: const ChatScrollThemeData(highlightColor: color)),
    );
    expect(_render(tester).highlightColor, color);
  });

  testWidgets('widget highlightColor beats inherited theme', (tester) async {
    const inherited = Color(0x80FF00FF);
    const local = Color(0x8000FF00);
    await tester.pumpWidget(
      _app(
        inherited: const ChatScrollThemeData(highlightColor: inherited),
        highlightColor: local,
      ),
    );
    expect(_render(tester).highlightColor, local);
  });

  testWidgets('ThemeData.extension ChatScrollThemeData is used', (
    tester,
  ) async {
    const color = Color(0x80ABCDEF);
    await tester.pumpWidget(
      _app(extension: const ChatScrollThemeData(highlightColor: color)),
    );
    expect(_render(tester).highlightColor, color);
  });

  testWidgets('inherited ChatScrollTheme wins over ThemeData.extension', (
    tester,
  ) async {
    const fromInherited = Color(0x80111111);
    const fromExtension = Color(0x80222222);
    await tester.pumpWidget(
      _app(
        inherited: const ChatScrollThemeData(highlightColor: fromInherited),
        extension: const ChatScrollThemeData(highlightColor: fromExtension),
      ),
    );
    expect(_render(tester).highlightColor, fromInherited);
  });

  testWidgets('messageOf reads inherited message without full resolve', (
    tester,
  ) async {
    const tokens = ChatMessageThemeData(contentMaxWidth: 720);
    late ChatMessageThemeData resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatScrollTheme(
          data: const ChatScrollThemeData(message: tokens),
          child: Builder(
            builder: (context) {
              resolved = ChatScrollTheme.messageOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(resolved.contentMaxWidth, 720);
  });

  testWidgets('omitted message still reads ChatMessageThemeData extension', (
    tester,
  ) async {
    const layout = ChatMessageThemeData.fallback;
    late ChatMessageThemeData resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [layout]),
        home: Builder(
          builder: (context) {
            resolved = ChatScrollTheme.resolve(context).message!;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resolved.contentMaxWidth, layout.contentMaxWidth);
  });

  testWidgets(
    'omitted scrollbar still reads ChatScrollbarThemeData extension',
    (tester) async {
      const bar = ChatScrollbarThemeData(trackColor: Color(0xFFFF0000));
      late ChatScrollbarThemeData resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [bar]),
          home: Builder(
            builder: (context) {
              resolved = ChatScrollTheme.resolve(context).scrollbar!;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(resolved.trackColor, bar.trackColor);
    },
  );
}
