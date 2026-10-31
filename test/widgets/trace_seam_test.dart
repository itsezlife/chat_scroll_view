import 'dart:developer' as developer;

import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/util/trace_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart' as vm;
import 'package:vm_service/vm_service_io.dart' as vm_io;

import '../chat_message.dart';

class _Source extends ChatDataSource {
  _Source(int count) {
    upsertMessages(<IChatMessage>[
      for (var i = 0; i < count; i++)
        UserChatMessage(
          id: i,
          sender: 'User',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'content $i',
        ),
    ]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
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

/// The default build compiles every section away; the capture test runs only
/// in a build with `--dart-define=chat_scroll_view.trace=phase` (or `fine`):
///
///     flutter test --enable-vmservice --dart-define=chat_scroll_view.trace=phase test/widgets/trace_seam_test.dart
void main() {
  test(
    'the trace gate defaults to off',
    () => expect(Trace.level, TraceLevel.off),
    skip: Trace.level != TraceLevel.off ? 'built with tracing' : null,
  );

  test('section names are unique and share one namespace', () {
    final labels = TraceSection.values.map((s) => s.label).toList();
    expect(labels.toSet().length, labels.length);
    expect(labels, everyElement(startsWith('chat_scroll_view.')));
  });

  testWidgets(
    'a traced scroll records the layout, tick and paint sections by name',
    (tester) async {
      final info = (await tester.runAsync(
        () => developer.Service.controlWebServer(enable: true),
      ))!;
      final uri = info.serverWebSocketUri;
      expect(uri, isNotNull, reason: 'VM service unavailable');
      final service = await tester.runAsync(
        () => vm_io.vmServiceConnectUri(uri!.toString()),
      );
      addTearDown(() => service!.dispose());
      await tester.runAsync(() async {
        await service!.setVMTimelineFlags(<String>['Dart']);
        await service.clearVMTimeline();
      });

      final controller = ChatScrollController()..jumpTo(59);
      final ds = _Source(60);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatScrollView(
              reverse: true,
              dataSource: ds,
              controller: controller,
              messageBuilder: (context, id, message, status, runLayout) =>
                  SizedBox(height: 60, child: Text('msg-$id')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.fling(
        find.byType(ChatScrollView),
        const Offset(0, 400),
        2000,
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));

      final names = <String>{};
      await tester.runAsync(() async {
        final timeline = await service!.getVMTimeline();
        for (final e in timeline.traceEvents ?? const <vm.TimelineEvent>[]) {
          final name = e.json?['name'];
          if (name is String) names.add(name);
        }
      });
      for (final s in <TraceSection>[
        TraceSection.layoutMode,
        TraceSection.layoutFanOut,
        TraceSection.layoutClamp,
        TraceSection.layoutPublish,
        TraceSection.tickTier1,
        TraceSection.paintMessages,
      ]) {
        expect(names, contains(s.label));
      }
      expect(names, contains(TraceSection.childBuild.label));
      expect(
        names.contains(TraceSection.childLayout.label),
        Trace.level == TraceLevel.fine,
      );
    },
    // Needs --dart-define=chat_scroll_view.trace=phase.
    skip: Trace.level == TraceLevel.off,
  );
}
