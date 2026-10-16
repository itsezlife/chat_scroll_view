import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/common/widgets/listen_value_builder.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/emoji_panel_page.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_shell/panel_shell.dart';

/// The panel on a bare scaffold: no chat, no composer, no backend.
///
/// It composes what the chat screen composes (`EmojiPanelPage`, the keyboard
/// replacement presentation over the shell) and nothing else, so the bare
/// scenarios measure the panel and the chat scenarios measure what the chat
/// adds around it.
final class PanelHarness {
  PanelHarness._(
    this.services,
    this.presentation,
    this._shell,
    this._keyboard,
    this._ime,
    this._window,
    this._frames,
  );

  /// The services the panel draws on; created and disposed with the harness.
  final AppServices services;

  /// Opens and closes the panel.
  final PanelPresentationController presentation;

  final PanelShellController _shell;
  final KeyboardReplacementStrategy _keyboard;
  final ImeInput _ime;
  final listen.ValueNotifier<PanelWindow> _window;
  final SchedulerBakeFrameSource _frames;

  /// The height the bare panel opens at: a stored keyboard height, as a device
  /// that has shown its keyboard once has.
  static const double panelHeight = 380;

  /// Mounts the panel. [glyphCache] and [glyphArtVersion] give the emoji atlas
  /// a persistent cache; without a cache it bakes in memory, and without an
  /// art version the probe's fingerprint is the cache's.
  static Future<PanelHarness> start(
    WidgetTester tester, {
    GlyphCacheStore? glyphCache,
    GlyphArtVersionSource? glyphArtVersion,
  }) async {
    final services = await AppServices.create(
      keyValueStore: FakeKeyValueStore(),
      glyphCache: glyphCache,
      glyphArtVersion: glyphArtVersion,
    );
    await services.keyboardHeights.record(
      PanelOrientation.portrait,
      panelHeight,
    );
    final view = tester.view;
    final size = view.physicalSize / view.devicePixelRatio;
    final window = listen.ValueNotifier<PanelWindow>(
      PanelWindow(width: size.width, height: size.height),
    );
    final ime = ImeInput();
    final frames = SchedulerBakeFrameSource(view: view);
    final keyboard = KeyboardReplacementStrategy(
      ime: ime,
      heights: services.keyboardHeights,
      window: window,
    );
    late final PanelPresentationController presentation;
    final shell = PanelShellController(
      pages: [
        EmojiPanelPage.of(
          services: services,
          frames: frames,
          deferChrome: () =>
              presentation.state.value.kind is KeyboardReplacement &&
              !keyboard.keyboardIsUp,
        ),
      ],
      preferences: services.preferences,
    );
    presentation = PanelPresentationController(
      shell: shell,
      policy: const PanelPresentationPolicy$Mobile(),
      strategies: [keyboard],
      window: window.value,
    );
    // The same view for every build: the strategy keeps the shell mounted.
    final panel = RepaintBoundary(
      child: PanelPresentationView(controller: presentation),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ListenValueBuilder<PanelOccupancy>(
              listenable: presentation.occupancy,
              builder: (context, occupancy) =>
                  SizedBox(height: occupancy.bottom, child: panel),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return PanelHarness._(
      services,
      presentation,
      shell,
      keyboard,
      ime,
      window,
      frames,
    );
  }

  /// Opens the panel, as a tap on its button would.
  void open() => presentation.show();

  /// Unmounts the panel, then frees what the harness made, in the reverse of
  /// the order it made it (the services last).
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    presentation.dispose();
    _keyboard.dispose();
    _shell.dispose();
    _window.dispose();
    _ime.dispose();
    _frames.dispose();
    services.dispose();
  }
}
