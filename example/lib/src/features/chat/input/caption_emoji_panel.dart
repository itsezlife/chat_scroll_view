import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/emoji_panel_page.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';
import 'package:glyph_atlas/glyph_atlas.dart';
import 'package:panel_shell/panel_shell.dart';

/// The attach caption's panel: the chat's emoji page alone, by the chat's
/// path (the same page, catalogue, recents and animated emoji), typing into
/// [caption].
///
/// An emoji picked goes into the caption as the chat's composer takes it (an
/// inline reference over its text) and joins the recents; backspace edits
/// the caption.
class CaptionEmojiPanel extends StatefulWidget {
  /// The emoji page over [services], typing into [caption].
  const CaptionEmojiPanel({
    required this.services,
    required this.caption,
    super.key,
  });

  /// The app's services: the emoji sources, the recents, the preferences.
  final AppServices services;

  /// Where picks go.
  final ComposerController caption;

  @override
  State<CaptionEmojiPanel> createState() => _CaptionEmojiPanelState();
}

class _CaptionEmojiPanelState extends State<CaptionEmojiPanel> {
  SchedulerBakeFrameSource? _frames;
  PanelShellController? _shell;
  StreamSubscription<PanelEvent>? _events;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shell != null) return;
    final frames = _frames = SchedulerBakeFrameSource(view: View.of(context));
    final shell = _shell = PanelShellController(
      pages: [
        EmojiPanelPage.of(
          services: widget.services,
          frames: frames,
          // In the keyboard's place: on screen already, mounted at once.
          deferChrome: () => false,
        ),
      ],
      preferences: widget.services.preferences,
    );
    _events = shell.events.listen(_onEvent);
  }

  void _onEvent(PanelEvent event) {
    switch (event) {
      case ContentPicked(:final key, :final recentsKind, :final source):
        final text = switch (key) {
          ContentKey$Unicode(:final sequence) => sequence,
          _ => AnimatedEmojiPack.of(key)?.sequence,
        };
        if (text == null) return;
        unawaited(HapticFeedback.selectionClick());
        widget.caption.insertContent(
          InlineContentRef(key: key, alternativeText: text),
        );
        unawaited(
          widget.services.recents.record(
            key,
            kind: recentsKind,
            source: source,
          ),
        );
      case BackspaceRequested():
        unawaited(HapticFeedback.selectionClick());
        widget.caption.backspace();
      default:
        break;
    }
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _shell?.dispose();
    _frames?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PanelShell(controller: _shell!);
}
