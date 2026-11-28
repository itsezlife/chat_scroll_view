/// A message whose body has both a part that paints no text (media, a
/// registered `ChatNonTextBody`) and a text body (its caption): a link in
/// the caption activates as a link, and the media's part still activates as
/// a body part.
///
/// **Seam:** [ChatSelectionController] and a mounted [ChatScrollView] whose
/// row stacks a fake non-text body over a [ChatMarkdownBody] for the same
/// message id; observed through the interactions.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

const _mediaPart = #media;

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    final ids = messages.map((m) => m.id).toList()..sort();
    seedBoundaries(
      oldestKnownId: ids.first,
      newestKnownId: ids.last,
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

/// The media of a message: one `activate` part over its whole box, and no
/// hit outside it.
class _MediaBody extends StatefulWidget {
  const _MediaBody({required this.selection, required this.messageId});

  final ChatSelectionController selection;
  final int messageId;

  @override
  State<_MediaBody> createState() => _MediaBodyState();
}

class _MediaBodyState extends State<_MediaBody> implements ChatNonTextBody {
  Object? _token;

  @override
  void initState() {
    super.initState();
    _token = widget.selection.putNonTextBody(widget.messageId, this);
  }

  @override
  void dispose() {
    widget.selection.removeNonTextBody(widget.messageId, token: _token);
    super.dispose();
  }

  @override
  Rect? get globalBounds => switch (context.findRenderObject()) {
    final RenderBox box when box.hasSize && box.attached =>
      box.localToGlobal(Offset.zero) & box.size,
    _ => null,
  };

  @override
  ChatInlineHit? inlineHitAt(Offset globalOffset) {
    final bounds = globalBounds;
    if (bounds == null || !bounds.contains(globalOffset)) return null;
    return ChatInlineHit.bodyPart(
      messageId: widget.messageId,
      partId: _mediaPart,
      role: ChatBodyPartRole.activate,
      rect: bounds,
    );
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(key: ValueKey('media'), width: 200, height: 120);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ChatSelectionInteraction> heard;
  late ChatSelectionController selection;

  Future<void> pumpCaptioned(
    WidgetTester tester, {
    required ChatSelectionPolicy policy,
  }) async {
    heard = [];
    final dataSource = _LoadedSource([_msg(1)]);
    final controller = ChatScrollController();
    selection = ChatSelectionController(
      policy: policy,
      onInteraction: heard.add,
    );
    addTearDown(controller.dispose);
    addTearDown(selection.dispose);
    addTearDown(dataSource.dispose);
    selection.putBody(1, Markdown.fromString('[Auto Docs](https://auto.com)'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatScrollView(
              dataSource: dataSource,
              controller: controller,
              selectionController: selection,
              messageBuilder: (context, id, message, status, runLayout) =>
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MediaBody(selection: selection, messageId: id),
                        ChatMarkdownBody(controller: selection, messageId: id),
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Offset linkPoint() {
    final surface = selection.surfaceFor(1)!;
    final boxes = surface.localBoxesForRange(0, 0, 9);
    return (surface as RenderBox).localToGlobal(boxes.first.center);
  }

  /// The middle of the media, which sits right above the caption.
  Offset mediaPoint() {
    final caption = selection.surfaceFor(1)! as RenderBox;
    return caption.localToGlobal(const Offset(100, -60));
  }

  List<String> links() => [
    for (final i in heard)
      if (i case ChatLinkActivated(:final messageId, :final url))
        '$messageId $url',
  ];

  List<Object> parts() => [
    for (final i in heard)
      if (i case ChatBodyPartActivated(:final partId)) partId,
  ];

  for (final (name, platform, policy, kind) in [
    (
      'mobile',
      TargetPlatform.iOS,
      const ChatSelectionPolicy.mobile(),
      PointerDeviceKind.touch,
    ),
    (
      'desktop',
      TargetPlatform.macOS,
      const ChatSelectionPolicy.desktop(),
      PointerDeviceKind.mouse,
    ),
  ]) {
    group(name, () {
      testWidgets(
        'a tap on a link in the caption activates the link',
        (tester) async {
          await pumpCaptioned(tester, policy: policy);

          expect(
            selection.resolveInlineHit(1, linkPoint()),
            isA<ChatInlineHit$Link>(),
          );
          await tester.tapAt(linkPoint(), kind: kind);
          await tester.pumpAndSettle();

          expect(links(), ['1 https://auto.com']);
          expect(parts(), isEmpty);
        },
        variant: TargetPlatformVariant.only(platform),
      );

      testWidgets(
        'a tap on the media still activates its part',
        (tester) async {
          await pumpCaptioned(tester, policy: policy);

          await tester.tapAt(mediaPoint(), kind: kind);
          await tester.pumpAndSettle();

          expect(parts(), [_mediaPart]);
          expect(links(), isEmpty);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    });
  }
}
