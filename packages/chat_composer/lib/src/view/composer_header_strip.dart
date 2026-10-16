import 'package:chat_composer/src/spec/composer_header.dart';
import 'package:chat_composer/src/view/composer_button.dart';
import 'package:chat_composer/src/view/composer_metrics.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The strip a [ComposerHeader] draws: a glyph, two lines of text and a
/// dismiss control, or the host's own content for a suggestion.
///
/// Transparent, because it sits under the glass island; an opaque fill would
/// paint over the glass. Laid out with start and end edges, so it mirrors in
/// right-to-left text. The text is a live region, so assistive technology
/// reads a reply or an edit when it appears.
class ComposerHeaderStrip extends StatelessWidget {
  /// The strip for [header].
  const ComposerHeaderStrip({required this.header, super.key});

  /// What the strip shows.
  final ComposerHeader header;

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.composerOf(context);
    final dismiss = header.onDismiss;
    return SizedBox(
      height: ComposerMetrics.headerHeight,
      child: Row(
        children: [
          Expanded(child: _content(context, strings)),
          if (dismiss != null)
            ComposerButton(
              icon: ChromeIconId.close,
              semanticLabel: strings.dismissHeaderAction,
              onTap: dismiss,
              iconSize: _closeGlyph,
              width: ComposerMetrics.headerHeight,
              height: ComposerMetrics.headerHeight - 2,
            )
          else
            const SizedBox(width: _edgePad),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, ComposerStrings strings) =>
      switch (header) {
        ComposerHeader$Reply(:final name, :final preview) => _TextStrip(
          icon: ChromeIconId.reply,
          title: strings.replyTo(name),
          subtitle: preview,
        ),
        ComposerHeader$Edit(:final preview) => _TextStrip(
          icon: ChromeIconId.edit,
          title: strings.editingMessage,
          subtitle: preview,
        ),
        ComposerHeader$Forward(:final icon, :final title, :final preview) =>
          _TextStrip(icon: icon, title: title, subtitle: preview),
        ComposerHeader$LinkPreview(:final icon, :final title, :final preview) =>
          _TextStrip(icon: icon, title: title, subtitle: preview),
        ComposerHeader$Suggestion(:final builder) => builder(context),
      };

  static const double _edgePad = 12;
  static const double _glyph = 20;
  static const double _glyphGap = 10;
  static const double _closeGlyph = 22;
}

class _TextStrip extends StatelessWidget {
  const _TextStrip({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final ChromeIconId icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.composerOf(context);
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title, $subtitle',
      excludeSemantics: true,
      child: Row(
        children: [
          const SizedBox(width: ComposerHeaderStrip._edgePad),
          ChromeIcon(
            icon,
            size: ComposerHeaderStrip._glyph,
            color: tokens.replyLine,
          ),
          const SizedBox(width: ComposerHeaderStrip._glyphGap),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.replyName,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tokens.replyText,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
