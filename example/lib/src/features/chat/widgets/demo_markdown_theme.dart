import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_md/highlight.dart';
import 'package:flutter_md/highlight/all.dart';
import 'package:flutter_md/highlight/themes.dart';

final SyntaxHighlighter _demoMarkdownHighlighter = MarkdownHighlighter(
  languages: allHighlightLanguages,
  theme: HighlightThemes.githubDark,
);

const Map<MD$AlertType, Color> _demoDarkAlertColors = <MD$AlertType, Color>{
  MD$AlertType.note: Color(0xFF2F81F7),
  MD$AlertType.tip: Color(0xFF3FB950),
  MD$AlertType.important: Color(0xFFA371F7),
  MD$AlertType.warning: Color(0xFFD29922),
  MD$AlertType.caution: Color(0xFFF85149),
};

/// Produces a dark [MarkdownThemeData] configured for the chat demo.
MarkdownThemeData demoDarkMarkdownTheme(BuildContext context) {
  final theme = Theme.of(context);
  return MarkdownThemeData.mergeTheme(
    theme,
    highlighter: _demoMarkdownHighlighter,
    alertColors: _demoDarkAlertColors,
    surfaceColor: const Color(0xFF1E1E22),
    highlightBackgroundColor: const Color(0x40FF5722),
    monospaceBackgroundColor: Colors.transparent,
    dividerColor: const Color(0x24FFFFFF),
    linkColor: const Color(0xFF58A6FF),
    spanFilter: (span) => !span.style.contains(MD$Style.image),
  );
}

/// {@template demo_markdown_theme}
/// Applies a dark [MarkdownTheme] configured for the demo app.
/// {@endtemplate}
class DemoMarkdownTheme extends StatelessWidget {
  /// {@macro demo_markdown_theme}
  const DemoMarkdownTheme({required this.child, super.key});

  /// Subtree that reads [MarkdownTheme.of] or renders markdown widgets.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MarkdownTheme(data: demoDarkMarkdownTheme(context), child: child);
}
