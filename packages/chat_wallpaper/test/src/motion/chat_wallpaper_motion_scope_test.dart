import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _wallpaper = ChatWallpaper.solid(Color(0xFF1D2D3C));

Widget _scope({required Widget child, bool disableAnimations = false}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ChatWallpaperMotionScope(child: child),
      ),
    );

List<ChatWallpaperMotionController?> _viewMotions(WidgetTester tester) => tester
    .widgetList<ChatWallpaperView>(find.byType(ChatWallpaperView))
    .map((view) => view.motion)
    .toList();

ChatWallpaperMotionController _scopedMotion(WidgetTester tester) =>
    ChatWallpaperMotionScope.of(tester.element(find.byType(_ThreadHost).first));

void main() {
  group('ChatWallpaperMotionScope', () {
    testWidgets('gives every view under it the same controller', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scope(
          child: const Column(
            children: [
              Expanded(child: _ThreadHost()),
              Expanded(child: _ThreadHost()),
            ],
          ),
        ),
      );

      final motions = _viewMotions(tester);
      expect(motions, hasLength(4));
      expect(motions.toSet(), {_scopedMotion(tester)});
    });

    testWidgets('a re-mounted host sees the phase the last shift left', (
      tester,
    ) async {
      await tester.pumpWidget(_scope(child: const _ThreadHost()));
      final motion = _scopedMotion(tester);
      expect(motion.advance(), isTrue);
      await tester.pump();
      await tester.pump(
        ChatWallpaperMotionController.shiftDuration +
            const Duration(milliseconds: 1),
      );

      await tester.pumpWidget(_scope(child: const SizedBox.shrink()));
      await tester.pumpWidget(_scope(child: const _ThreadHost()));

      expect(_viewMotions(tester), everyElement(same(motion)));
      expect(motion.phase, 7);
      expect(motion.progress, 1);
    });

    testWidgets('mirrors the reduced-motion setting from MediaQuery', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scope(disableAnimations: true, child: const _ThreadHost()),
      );
      final motion = _scopedMotion(tester);
      expect(motion.disableAnimations, isTrue);

      await tester.pumpWidget(_scope(child: const _ThreadHost()));
      expect(_scopedMotion(tester), same(motion));
      expect(motion.disableAnimations, isFalse);
    });

    testWidgets('disposes its controller with itself, even mid-run', (
      tester,
    ) async {
      await tester.pumpWidget(_scope(child: const _ThreadHost()));
      final motion = _scopedMotion(tester)..advance();
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());

      expect(() => motion.addListener(() {}), throwsFlutterError);
    });

    testWidgets(
      'resolves from a descendant initState, registering no dependency',
      (tester) async {
        await tester.pumpWidget(_scope(child: const _InitStateReader()));

        final reader = tester.state<_InitStateReaderState>(
          find.byType(_InitStateReader),
        );
        expect(
          reader.motion,
          same(ChatWallpaperMotionScope.of(reader.context)),
        );
      },
    );

    testWidgets('has no controller outside a scope', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        Builder(
          builder: (built) {
            context = built;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(ChatWallpaperMotionScope.maybeOf(context), isNull);
      expect(() => ChatWallpaperMotionScope.of(context), throwsFlutterError);
    });
  });
}

/// A thread-like host: a background and a copy over it, both moving with the
/// scope's controller.
class _ThreadHost extends StatelessWidget {
  const _ThreadHost();

  @override
  Widget build(BuildContext context) {
    final motion = ChatWallpaperMotionScope.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ChatWallpaperView(wallpaper: _wallpaper, motion: motion),
        ChatWallpaperView(wallpaper: _wallpaper, motion: motion),
      ],
    );
  }
}

class _InitStateReader extends StatefulWidget {
  const _InitStateReader();

  @override
  State<_InitStateReader> createState() => _InitStateReaderState();
}

class _InitStateReaderState extends State<_InitStateReader> {
  late final ChatWallpaperMotionController motion;

  @override
  void initState() {
    super.initState();
    motion = ChatWallpaperMotionScope.of(context);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
