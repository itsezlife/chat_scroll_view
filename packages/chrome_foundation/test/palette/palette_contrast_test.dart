import 'dart:ui';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// One drawn pairing: [ink] painted over [fill], itself painted over
/// [backdrop].
typedef _Pair = ({
  String name,
  Color ink,
  Color fill,
  Color backdrop,
  double minimum,
});

void main() {
  final palettes = {
    'light': const ChromePalette.light(),
    'dark': const ChromePalette.dark(),
    'high contrast light': const ChromePalette.highContrastLight(),
    'high contrast dark': const ChromePalette.highContrastDark(),
  };

  for (final MapEntry(key: name, value: palette) in palettes.entries) {
    group('$name palette', () {
      final data = ChromeThemeData.fromPalette(palette);
      for (final pair in _pairs(data)) {
        test('${pair.name} reaches ${pair.minimum}:1', () {
          final ratio = ChromeContrast.ratio(
            pair.ink,
            pair.fill,
            backdrop: pair.backdrop,
          );
          expect(ratio, greaterThanOrEqualTo(pair.minimum));
        });
      }
    });
  }

  for (final name in ['high contrast light', 'high contrast dark']) {
    group('$name palette text', () {
      final data = ChromeThemeData.fromPalette(palettes[name]!);
      for (final pair in _pairs(data).where((p) => p.minimum == _text)) {
        test('${pair.name} reaches the AAA 7:1', () {
          final ratio = ChromeContrast.ratio(
            pair.ink,
            pair.fill,
            backdrop: pair.backdrop,
          );
          expect(ratio, greaterThanOrEqualTo(7));
        });
      }
    });
  }
}

const _text = ChromeContrast.minimumText;
const _icon = ChromeContrast.minimumIcon;

/// Every text and icon pairing the token groups draw.
List<_Pair> _pairs(ChromeThemeData d) {
  _Pair on(
    String name,
    Color ink,
    Color fill, {
    required double min,
    Color? backdrop,
  }) => (
    name: name,
    ink: ink,
    fill: fill,
    backdrop: backdrop ?? const Color(0xFFFFFFFF),
    minimum: min,
  );

  final composerBg = d.composer.background;
  final panelBg = d.panel.background;
  return [
    on('composer text', d.composer.text, composerBg, min: _text),
    on('composer reply name', d.composer.replyName, composerBg, min: _text),
    on('composer reply text', d.composer.replyText, composerBg, min: _text),
    on('composer cursor', d.composer.cursor, composerBg, min: _icon),
    on('composer reply line', d.composer.replyLine, composerBg, min: _icon),
    on('panel section title', d.panel.sectionTitle, panelBg, min: _text),
    on(
      'panel tooltip text on its fill',
      d.panel.tooltipText,
      d.panel.tooltipFill,
      backdrop: panelBg,
      min: _text,
    ),
    on(
      'panel search text on its pill',
      d.panel.searchText,
      d.panel.searchFill,
      backdrop: panelBg,
      min: _text,
    ),
    on(
      'panel search icon on its pill',
      d.panel.searchIcon,
      d.panel.searchFill,
      backdrop: panelBg,
      min: _icon,
    ),
    on('panel idle category icon', d.panel.categoryIcon, panelBg, min: _icon),
    on(
      'panel idle category icon on the pinned strip',
      d.panel.categoryIcon,
      d.panel.stripFill,
      backdrop: panelBg,
      min: _icon,
    ),
    on(
      'panel selected category icon on its selector on the pinned strip',
      d.panel.categoryIconSelected,
      d.panel.tabSelector,
      backdrop: Color.alphaBlend(d.panel.stripFill, panelBg),
      min: _icon,
    ),
    on(
      'panel selected category icon',
      d.panel.categoryIconSelected,
      panelBg,
      min: _icon,
    ),
    on(
      'panel selected category icon on its selector',
      d.panel.categoryIconSelected,
      d.panel.tabSelector,
      backdrop: panelBg,
      min: _icon,
    ),
    on('panel tab underline', d.panel.tabSelectorLine, panelBg, min: _icon),
    on('empty-state text', d.placeholder.emptyState, panelBg, min: _text),
    on(
      'field hint on composer',
      d.placeholder.fieldHint,
      composerBg,
      min: _text,
    ),
    on(
      'field hint on the search pill',
      d.placeholder.fieldHint,
      d.panel.searchFill,
      backdrop: panelBg,
      min: _text,
    ),
    on('composer action icon', d.action.icon, composerBg, min: _icon),
    on('backspace on panel', d.action.backspace, panelBg, min: _icon),
    on(
      'backspace on floating fill',
      d.action.backspace,
      d.action.floatingFill,
      min: _icon,
    ),
    on('send fill on composer', d.action.send, composerBg, min: _icon),
    on('send glyph on send fill', d.action.onSend, d.action.send, min: _text),
    on(
      'floating label on fill',
      d.action.floatingLabel,
      d.action.floatingFill,
      min: _text,
    ),
    on(
      'floating label on selected capsule',
      d.action.floatingLabel,
      d.action.floatingSelectedFill,
      min: _text,
    ),
    on(
      'floating muted label on fill',
      d.action.floatingLabelMuted,
      d.action.floatingFill,
      min: _text,
    ),
  ];
}
