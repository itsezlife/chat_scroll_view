import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_input_set.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/chat_bottom_chrome.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';

import 'fake_soft_keyboard.dart';

/// One chat's input set and bottom chrome under the app's scopes, as the chat
/// screen lays them out, over a filler where the chat is.
///
/// The set is created from the first dependencies with the view's size and
/// disposed with the harness, as the screen does. What it sends and edits is
/// logged.
final class InputRig {
  InputRig._(this.services, this.keyboard, this.selection);

  /// The app's services; the rig disposes none of them.
  final AppServices services;

  /// The soft keyboard.
  final FakeSoftKeyboard keyboard;

  /// The chat's selection, to hide the composer.
  final ChatSelectionController selection;

  bool Function()? _failSends;

  /// Bodies sent.
  final List<String> sent = <String>[];

  /// Edits saved, as `id:body`.
  final List<String> edited = <String>[];

  /// Kinds the user was asked to clear and agreed to.
  final List<SemanticKind> clearAsked = <SemanticKind>[];

  /// Media the composer handed over: pasted, or inserted by a keyboard.
  final List<List<PastedMedia>> pastedMedia = <List<PastedMedia>>[];

  /// The set under test, once the first frame is built.
  late ChatInputSet set;

  final GlobalKey _island = GlobalKey();
  final GlobalKey _space = GlobalKey();

  /// Pumps the rig into [tester]. [policy] is the platform's unless given;
  /// [size] is the window.
  static Future<InputRig> pump(
    WidgetTester tester, {
    required AppServices services,
    PanelPresentationPolicy? policy,
    Size size = const Size(400, 800),
    FakeSoftKeyboard? keyboard,
    bool Function()? failSends,
    int? messageLengthLimit = DemoConfig.messageLengthMax,
  }) async {
    final rig = InputRig._(
      services,
      keyboard ?? FakeSoftKeyboard(),
      ChatSelectionController(),
    ).._failSends = failSends;
    addTearDown(() async {
      rig.selection.dispose();
      await rig.keyboard.dispose();
    });
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: _Screen(
          rig: rig,
          policy: policy,
          messageLengthLimit: messageLengthLimit,
        ),
      ),
    );
    return rig;
  }

  /// The composer's text field (the panel's search field is another).
  ///
  /// Found by the focus node it holds: the composer's editable is a leaf
  /// package's type, which a host does not name (and which is not Flutter's
  /// `EditableText`).
  Finder get field => find.byWidgetPredicate(
    (widget) => widget is Focus && widget.focusNode == set.composer.focusNode,
  );

  /// Types [text] into the composer's field as the platform keyboard does.
  ///
  /// `WidgetTester.enterText` needs Flutter's own `EditableText`, which the
  /// composer's field is not.
  Future<void> typeInField(WidgetTester tester, String text) async {
    set.composer.requestFocus();
    await tester.pump();
    tester.testTextInput.enterText(text);
    await tester.pump();
  }

  /// The composer's glass island.
  Finder get island => find.byKey(_island);

  /// The composer's action [id].
  Finder action(String id) => find.byKey(ValueKey<String>(id));

  /// Taps the composer's action [id] and runs a frame.
  Future<void> tapAction(WidgetTester tester, String id) async {
    await tester.tap(action(id));
    await tester.pump();
  }

  /// Runs frames until nothing is moving or [limit] has passed, and for at
  /// least 100 ms: a keyboard reading is confirmed by a timer, not a frame.
  Future<void> settle(
    WidgetTester tester, [
    Duration limit = const Duration(seconds: 3),
  ]) async {
    final start = tester.binding.clock.now();
    final end = start.add(limit);
    final least = start.add(const Duration(milliseconds: 100));
    do {
      await tester.pump(const Duration(milliseconds: 16));
    } while ((tester.binding.hasScheduledFrame ||
            tester.binding.clock.now().isBefore(least)) &&
        tester.binding.clock.now().isBefore(end));
  }
}

class _Screen extends StatefulWidget {
  const _Screen({
    required this.rig,
    required this.policy,
    required this.messageLengthLimit,
  });

  final InputRig rig;
  final PanelPresentationPolicy? policy;
  final int? messageLengthLimit;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  ChatInputSet? _input;

  InputRig get _rig => widget.rig;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final input = _input ??= _rig.set = ChatInputSet(
      services: _rig.services,
      view: View.of(context),
      send: (body) async {
        if (_rig._failSends?.call() ?? false) throw Exception('network');
        _rig.sent.add(body);
      },
      edit: (id, body) async => _rig.edited.add('$id:$body'),
      confirmClearRecents: (kind) async {
        _rig.clearAsked.add(kind);
        return true;
      },
      onPastedMedia: (media) async {
        _rig.pastedMedia.add(media);
        return true;
      },
      keyboard: _rig.keyboard,
      policy: widget.policy,
      messageLengthLimit: widget.messageLengthLimit,
    );
    final safe = MediaQuery.viewPaddingOf(context);
    input
      ..updateEnvironment(
        size: MediaQuery.sizeOf(context),
        safeTop: safe.top,
        safeBottom: safe.bottom,
      )
      ..applyTheme(ChromeThemeScope.composerOf(context));
  }

  @override
  void dispose() {
    _input?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final input = _input!;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        key: _rig._space,
        children: [
          Positioned.fill(
            // The chat gives a docked section its room, as the screen does:
            // only the padding follows the inset, the chat is not rebuilt.
            child: ValueListenableBuilder<double>(
              valueListenable: input.insets.inlineEnd,
              builder: (context, inlineEnd, child) => Padding(
                padding: EdgeInsetsDirectional.only(end: inlineEnd),
                child: child,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatBottomChrome(
                  input: input,
                  selection: _rig.selection,
                  islandKey: _rig._island,
                  anchorSpace: _rig._space,
                ),
              ),
            ),
          ),
          if (!ChatBottomChrome.replacesKeyboard(input))
            Positioned.fill(
              child: PanelPresentationView(controller: input.presentation),
            ),
        ],
      ),
    );
  }
}

/// A unicode emoji key.
ContentKey$Unicode emojiKey(String glyph) => ContentKey$Unicode(glyph);
