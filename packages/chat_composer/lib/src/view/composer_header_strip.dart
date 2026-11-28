import 'dart:async';

import 'package:chat_composer/src/spec/composer_header.dart';
import 'package:chat_composer/src/view/composer_button.dart';
import 'package:chat_composer/src/view/composer_metrics.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/gestures.dart' show PointerEnterEvent, PointerExitEvent;
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
    if (header case ComposerHeader$Attachment(
      :final icon,
      :final title,
      :final removeLabel,
      :final onRemove,
    )) {
      return _AttachmentStrip(
        icon: icon,
        title: title,
        removeLabel: removeLabel,
        onRemove: onRemove,
      );
    }
    if (header case final ComposerHeader$LinkPreview link) {
      return _LinkPreviewStrip(header: link);
    }
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
        // Drawn by _LinkPreviewStrip, which guards its taps.
        ComposerHeader$LinkPreview() => const SizedBox.shrink(),
        ComposerHeader$Suggestion(:final builder) => builder(context),
        ComposerHeader$Attachment() => const SizedBox.shrink(),
      };

  /// How long after an accepted tap a link preview strip ignores the next
  /// one, on its open action and its dismiss control alike: a burst of taps
  /// opens the options or dismisses once.
  static const Duration tapGuard = ChromeTapTiming.repeatGuard;

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
                  style: _titleStyle(context, tokens),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _subtitleStyle(context, tokens),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _titleStyle(BuildContext context, ComposerTokens tokens) =>
    ChromeTypography.of(context).copyWith(
      color: tokens.replyName,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.1,
    );

TextStyle _subtitleStyle(BuildContext context, ComposerTokens tokens) =>
    ChromeTypography.of(
      context,
    ).copyWith(color: tokens.replyText, fontSize: 13, height: 1.1);

/// The strip of a [ComposerHeader$LinkPreview]: a thumbnail or glyph, the
/// page's two lines, the dismiss control; a tap opens the host's options.
///
/// Both taps go through one time window ([ComposerHeaderStrip.tapGuard]):
/// without it a double tap on the cross would dismiss twice (the second
/// landing on whatever the host shows next), and one on the body would open
/// the options twice.
class _LinkPreviewStrip extends StatefulWidget {
  const _LinkPreviewStrip({required this.header});

  final ComposerHeader$LinkPreview header;

  @override
  State<_LinkPreviewStrip> createState() => _LinkPreviewStripState();
}

class _LinkPreviewStripState extends State<_LinkPreviewStrip> {
  Timer? _$guard;

  static const double _thumbnail = 34;

  bool _accept() {
    if (_$guard != null) return false;
    _$guard = Timer(ComposerHeaderStrip.tapGuard, () => _$guard = null);
    return true;
  }

  void _open() {
    final onOpen = widget.header.onOpen;
    if (onOpen == null || !_accept()) return;
    if (context.findRenderObject() case final RenderBox box
        when box.hasSize && box.attached) {
      onOpen(box.localToGlobal(Offset.zero) & box.size);
    }
  }

  // Whether an enter was reported, so a leave is reported once after it.
  bool _$hovered = false;

  void _hoverEntered(PointerEnterEvent event) {
    final onHover = widget.header.onHover;
    if (onHover == null ||
        ChromeInputClass.fromPointerKind(event.kind) !=
            ChromeInputClass.mouse) {
      return;
    }
    if (context.findRenderObject() case final RenderBox box
        when box.hasSize && box.attached) {
      _$hovered = true;
      onHover(box.localToGlobal(Offset.zero) & box.size);
    }
  }

  void _hoverExited(PointerExitEvent event) {
    if (!_$hovered) return;
    _$hovered = false;
    widget.header.onHover?.call(null);
  }

  void _dismiss() {
    final onDismiss = widget.header.onDismiss;
    if (onDismiss == null || !_accept()) return;
    onDismiss();
  }

  @override
  void dispose() {
    _$guard?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    final strings = ChromeStringsScope.composerOf(context);
    final tokens = ChromeThemeScope.composerOf(context);
    final thumbnail = switch ((header.page, header.thumbnail)) {
      (final page?, final builder?) when page.photo != null => builder(
        context,
        page,
        const Size.square(_thumbnail),
      ),
      _ => null,
    };
    final title = header.title;
    final preview = header.preview;
    final content = Row(
      children: [
        const SizedBox(width: ComposerHeaderStrip._edgePad),
        switch (thumbnail) {
          final thumbnail? => ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(4)),
            child: SizedBox.square(dimension: _thumbnail, child: thumbnail),
          ),
          null => ChromeIcon(
            header.icon,
            size: ComposerHeaderStrip._glyph,
            color: tokens.replyLine,
          ),
        },
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
                style: _titleStyle(context, tokens),
              ),
              const SizedBox(height: 2),
              Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _subtitleStyle(context, tokens),
              ),
            ],
          ),
        ),
      ],
    );
    final strip = SizedBox(
      height: ComposerMetrics.headerHeight,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              liveRegion: true,
              button: header.onOpen != null,
              label: '$title, $preview',
              excludeSemantics: true,
              onTap: header.onOpen == null ? null : _open,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: header.onOpen == null ? null : _open,
                child: content,
              ),
            ),
          ),
          if (header.onDismiss != null)
            ComposerButton(
              icon: ChromeIconId.close,
              semanticLabel: strings.dismissHeaderAction,
              onTap: _dismiss,
              iconSize: ComposerHeaderStrip._closeGlyph,
              width: ComposerMetrics.headerHeight,
              height: ComposerMetrics.headerHeight - 2,
            )
          else
            const SizedBox(width: ComposerHeaderStrip._edgePad),
        ],
      ),
    );
    if (header.onHover == null) return strip;
    return MouseRegion(
      onEnter: _hoverEntered,
      onExit: _hoverExited,
      child: strip,
    );
  }
}

class _AttachmentStrip extends StatelessWidget {
  const _AttachmentStrip({
    required this.icon,
    required this.title,
    required this.removeLabel,
    required this.onRemove,
  });

  final ChromeIconId icon;
  final String title;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = ChromeThemeScope.composerOf(context);
    return SizedBox(
      height: ComposerMetrics.headerHeight,
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
            child: Semantics(
              container: true,
              liveRegion: true,
              label: title,
              excludeSemantics: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tokens.replyName,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: removeLabel,
            excludeSemantics: true,
            onTap: onRemove,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: ComposerMetrics.headerHeight,
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ComposerHeaderStrip._edgePad,
                    ),
                    child: Text(
                      removeLabel,
                      maxLines: 1,
                      style: TextStyle(
                        color: tokens.replyLine,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
