/// The pack sheet's routes as the host sees them.
///
/// **Seam:** [PackSheet.show] over a navigator under the chrome scopes, with
/// a host page holding a focused text field (the composer's) and a keyboard
/// in the view insets; observed through the sheet's text style, the field's
/// focus, where the sheet sits and whether the route is still up.
library;

import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

void main() {
  late BuildContext home;
  late FocusNode field;
  late TextEditingController text;
  const sheet = Key('sheet');
  const keyboard = 300.0;

  Future<void> pumpHome(WidgetTester tester, {double insets = 0}) {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    field = FocusNode();
    text = TextEditingController();
    addTearDown(field.dispose);
    addTearDown(text.dispose);
    return tester.pumpWidget(
      PanelShellTestScope(
        size: const Size(400, 800),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(viewInsets: EdgeInsets.only(bottom: insets)),
            child: DefaultTextStyle(
              style: const TextStyle(
                fontFamily: 'Fallback',
                decoration: TextDecoration.underline,
              ),
              child: Navigator(
                onGenerateRoute: (_) => PageRouteBuilder<void>(
                  pageBuilder: (context, _, _) => DefaultTextStyle(
                    style: const TextStyle(
                      fontFamily: 'HostFont',
                      fontSize: 14,
                    ),
                    child: Builder(
                      builder: (context) {
                        home = context;
                        return Align(
                          alignment: Alignment.topCenter,
                          child: EditableText(
                            controller: text,
                            focusNode: field,
                            style: const TextStyle(),
                            cursorColor: const Color(0xFF000000),
                            backgroundCursorColor: const Color(0xFF000000),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, PanelArrangement arrangement) async {
    unawaited(
      PackSheet.show(
        home,
        arrangement: arrangement,
        builder: (_) =>
            const SizedBox(key: sheet, height: 200, child: Text('baby_yoda')),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final arrangement in PanelArrangement.values) {
    group('under ${arrangement.name}', () {
      testWidgets('the text takes the host font and the chrome colour', (
        tester,
      ) async {
        await pumpHome(tester);
        await open(tester, arrangement);

        final style = DefaultTextStyle.of(
          tester.element(find.text('baby_yoda')),
        ).style;
        final palette = ChromeThemeScope.of(home).palette;
        expect(style.fontFamily, 'HostFont');
        expect(style.color, palette.onSurface);
        expect(style.decoration, TextDecoration.none);
      });

      testWidgets('the focused field keeps focus', (tester) async {
        await pumpHome(tester, insets: keyboard);
        field.requestFocus();
        await tester.pump();

        await open(tester, arrangement);

        expect(field.hasFocus, isTrue);
      });

      testWidgets('back still dismisses the sheet', (tester) async {
        await pumpHome(tester);
        await open(tester, arrangement);

        await Navigator.maybePop(home);
        await tester.pumpAndSettle();

        expect(find.byKey(sheet), findsNothing);
      });

      testWidgets('a tap on the barrier dismisses the sheet', (tester) async {
        await pumpHome(tester);
        await open(tester, arrangement);

        await tester.tapAt(const Offset(200, 5));
        await tester.pumpAndSettle();

        expect(find.byKey(sheet), findsNothing);
      });
    });
  }

  testWidgets('the bottom sheet sits on the keyboard', (tester) async {
    await pumpHome(tester, insets: keyboard);
    await open(tester, PanelArrangement.touch);

    expect(tester.getBottomLeft(find.byKey(sheet)).dy, 800 - keyboard);
  });

  testWidgets('the box centres above the keyboard', (tester) async {
    await pumpHome(tester, insets: keyboard);
    await open(tester, PanelArrangement.pointer);

    expect(tester.getCenter(find.byKey(sheet)).dy, (800 - keyboard) / 2);
  });
}
