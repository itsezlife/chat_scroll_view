import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> _actionIds(List<ChatMessageMenuItem> items) => [
  for (final item in items)
    if (item case ChatMessageMenuAction(:final id)) id,
];

Map<String, String> _actionLabels(List<ChatMessageMenuItem> items) => {
  for (final item in items)
    if (item case ChatMessageMenuAction(:final id, :final label)) id: label,
};

ChatMessageMenuRequest _request({
  required int messageId,
  ChatMessageMenuPointState pointState = ChatMessageMenuPointState.inside,
  ChatMessageMenuMembership membership = ChatMessageMenuMembership.idle,
  bool hasTextSelection = false,
  bool overlapsTextSelection = false,
  String? selectedTextSnapshot,
  List<int>? selectUpToIds,
  ChatInlineHit? inlineHit,
}) => ChatMessageMenuRequest(
  messageId: messageId,
  slotGlobal: const Rect.fromLTWH(0, 0, 100, 40),
  tapGlobal: const Offset(10, 10),
  pointState: pointState,
  membership: membership,
  hasTextSelection: hasTextSelection || overlapsTextSelection,
  overlapsTextSelection: overlapsTextSelection,
  selectedTextSnapshot: selectedTextSnapshot,
  selectUpToIds: selectUpToIds,
  inlineHit: inlineHit,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(r'MessageMenuCatalog ($Mobile)', () {
    const policy = ChatSelectionPolicy.mobile();

    test('idle: Reply→Copy→Forward→Pin→Edit→Delete; no Select', () {
      expect(
        _actionIds(MessageMenuCatalog.itemsFor(_request(messageId: 1), policy)),
        <String>[
          MessageMenuActionId.reply,
          MessageMenuActionId.copy,
          MessageMenuActionId.forward,
          MessageMenuActionId.pin,
          MessageMenuActionId.edit,
          MessageMenuActionId.delete,
        ],
      );
    });

    test('outside still keeps full idle rows', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(messageId: 1, pointState: ChatMessageMenuPointState.outside),
          policy,
        ),
      );
      expect(ids, contains(MessageMenuActionId.reply));
      expect(ids, isNot(contains(MessageMenuActionId.select)));
    });

    test(
      'idle: live text omits whole-message Copy (text chrome owns range)',
      () {
        final ids = _actionIds(
          MessageMenuCatalog.itemsFor(
            _request(
              messageId: 1,
              hasTextSelection: true,
              overlapsTextSelection: true,
              selectedTextSnapshot: 'hi',
            ),
            policy,
          ),
        );
        expect(ids, isNot(contains(MessageMenuActionId.copySelected)));
        expect(ids, isNot(contains(MessageMenuActionId.copy)));
        expect(ids, isNot(contains(MessageMenuActionId.select)));
      },
    );

    test('upon-selected: bulk labels + Reply; no Select', () {
      final items = MessageMenuCatalog.itemsFor(
        _request(
          messageId: 2,
          membership: ChatMessageMenuMembership.uponSelected,
        ),
        policy,
      );
      expect(_actionIds(items), <String>[
        MessageMenuActionId.reply,
        MessageMenuActionId.copy,
        MessageMenuActionId.forward,
        MessageMenuActionId.delete,
        MessageMenuActionId.clearSelection,
      ]);
      final labels = _actionLabels(items);
      expect(labels[MessageMenuActionId.copy], 'Copy Selected as Text');
      expect(labels[MessageMenuActionId.forward], 'Forward Selected');
      expect(labels[MessageMenuActionId.delete], 'Delete Selected');
      expect(labels[MessageMenuActionId.clearSelection], 'Clear Selection');
    });

    test('link hit prefixes Copy link', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(
            messageId: 1,
            inlineHit: const ChatInlineHit.link(
              messageId: 1,
              title: 'ex',
              url: 'https://example.com',
            ),
          ),
          policy,
        ),
      );
      expect(ids.first, MessageMenuActionId.copyLink);
    });

    test('reactions strip is non-empty', () {
      expect(MessageMenuCatalog.reactionsFor(policy), isNotEmpty);
    });
  });

  group(r'MessageMenuCatalog ($Desktop)', () {
    const policy = ChatSelectionPolicy.desktop();

    test('idle inside: Select at end; Edit before Pin/Copy', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(_request(messageId: 1), policy),
      );
      expect(ids.last, MessageMenuActionId.select);
      expect(
        ids.indexOf(MessageMenuActionId.edit),
        lessThan(ids.indexOf(MessageMenuActionId.pin)),
      );
      expect(
        ids.indexOf(MessageMenuActionId.pin),
        lessThan(ids.indexOf(MessageMenuActionId.copy)),
      );
    });

    test('outside: Select only', () {
      expect(
        _actionIds(
          MessageMenuCatalog.itemsFor(
            _request(
              messageId: 1,
              pointState: ChatMessageMenuPointState.outside,
            ),
            policy,
          ),
        ),
        <String>[MessageMenuActionId.select],
      );
    });

    test('membership elsewhere without chain: Select only', () {
      expect(
        _actionIds(
          MessageMenuCatalog.itemsFor(
            _request(
              messageId: 2,
              membership: ChatMessageMenuMembership.elsewhere,
            ),
            policy,
          ),
        ),
        <String>[MessageMenuActionId.select],
      );
    });

    test('membership elsewhere with chain: Select + Select up to', () {
      expect(
        _actionIds(
          MessageMenuCatalog.itemsFor(
            _request(
              messageId: 5,
              membership: ChatMessageMenuMembership.elsewhere,
              selectUpToIds: const <int>[3, 4, 5],
            ),
            policy,
          ),
        ),
        <String>[MessageMenuActionId.select, MessageMenuActionId.selectUpTo],
      );
    });

    test('over-selection: bulk labels + Reply; no Select', () {
      final items = MessageMenuCatalog.itemsFor(
        _request(
          messageId: 2,
          membership: ChatMessageMenuMembership.uponSelected,
        ),
        policy,
      );
      expect(_actionIds(items), <String>[
        MessageMenuActionId.reply,
        MessageMenuActionId.copy,
        MessageMenuActionId.forward,
        MessageMenuActionId.delete,
        MessageMenuActionId.clearSelection,
      ]);
      final labels = _actionLabels(items);
      expect(labels[MessageMenuActionId.copy], 'Copy Selected as Text');
      expect(labels[MessageMenuActionId.forward], 'Forward Selected');
      expect(labels[MessageMenuActionId.delete], 'Delete Selected');
    });

    test('text upon: Copy Selected Text; no whole-message Copy', () {
      final items = MessageMenuCatalog.itemsFor(
        _request(
          messageId: 1,
          overlapsTextSelection: true,
          selectedTextSnapshot: 'hi',
        ),
        policy,
      );
      final ids = _actionIds(items);
      expect(ids, contains(MessageMenuActionId.copySelected));
      expect(ids, isNot(contains(MessageMenuActionId.copy)));
      expect(ids, contains(MessageMenuActionId.select));
      expect(
        ids.indexOf(MessageMenuActionId.reply),
        lessThan(ids.indexOf(MessageMenuActionId.copySelected)),
      );
      expect(
        _actionLabels(items)[MessageMenuActionId.copySelected],
        'Copy Selected Text',
      );
    });

    test('text selected but not upon: neither Copy nor Copy Selected Text', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(messageId: 1, hasTextSelection: true),
          policy,
        ),
      );
      expect(ids, isNot(contains(MessageMenuActionId.copy)));
      expect(ids, isNot(contains(MessageMenuActionId.copySelected)));
      expect(ids, contains(MessageMenuActionId.reply));
      expect(ids, contains(MessageMenuActionId.select));
    });

    test('link hit prefixes Copy link', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(
            messageId: 1,
            inlineHit: const ChatInlineHit.link(
              messageId: 1,
              title: 'ex',
              url: 'https://example.com',
            ),
          ),
          policy,
        ),
      );
      expect(ids.first, MessageMenuActionId.copyLink);
    });

    test('excludeActionIds drops Reply and Forward', () {
      final ids = _actionIds(
        MessageMenuCatalog.itemsFor(
          _request(messageId: 1),
          policy,
          excludeActionIds: const [
            MessageMenuActionId.reply,
            MessageMenuActionId.forward,
          ],
        ),
      );
      expect(ids, isNot(contains(MessageMenuActionId.reply)));
      expect(ids, isNot(contains(MessageMenuActionId.forward)));
      expect(ids, contains(MessageMenuActionId.copy));
      expect(ids, contains(MessageMenuActionId.select));
    });

    test('reactions strip is empty (hover strip elsewhere)', () {
      expect(MessageMenuCatalog.reactionsFor(policy), isEmpty);
    });
  });
}
