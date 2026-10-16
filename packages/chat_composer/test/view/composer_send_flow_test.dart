import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

// The host side of a send: it owns the busy flag and decides, from the text,
// whether the one trailing action is send or voice. The composer only lays
// the spec out and publishes the text.
class _Host extends StatefulWidget {
  const _Host({required this.controller, required this.onSend});

  final ComposerController controller;
  final Future<void> Function(String text) onSend;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var _busy = false;

  @override
  void initState() {
    super.initState();
    widget.controller.text.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.text.removeListener(_onText);
    super.dispose();
  }

  void _onText() => setState(() {});

  Future<void> _send() async {
    final text = widget.controller.text.text.trim();
    if (_busy || text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSend(text);
      widget.controller.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.text.trim().isNotEmpty;
    return ComposerView(
      controller: widget.controller,
      spec: ComposerSpec(
        busy: _busy,
        actions: [
          ActionDescriptor(
            id: 'primary',
            icon: hasText ? ChromeIconId.send : ChromeIconId.voice,
            semanticLabel: hasText ? 'Send' : 'Record voice message',
            primary: hasText,
            onTap: hasText ? _send : () {},
          ),
        ],
      ),
    );
  }
}

void main() {
  late ComposerController controller;

  setUp(() => controller = ComposerController());
  tearDown(() => controller.dispose());

  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(String) onSend,
  ) => tester.pumpWidget(
    composerHarness(_Host(controller: controller, onSend: onSend)),
  );

  Finder primary() => find.byKey(const ValueKey<String>('primary'));

  Future<void> tapPrimary(WidgetTester tester) async {
    await tester.tap(primary());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('sends the trimmed text and clears on success', (tester) async {
    String? sent;
    await pumpHost(tester, (text) async => sent = text);

    await tester.enterText(find.byType(TextField), '  hello world  ');
    await tester.pump();
    await tapPrimary(tester);

    expect(sent, 'hello world');
    expect(controller.text.text, isEmpty);
  });

  testWidgets('whitespace-only text offers voice, not send', (tester) async {
    var invoked = false;
    await pumpHost(tester, (_) async => invoked = true);

    await tester.enterText(find.byType(TextField), '   \n  ');
    await tester.pump();
    await tapPrimary(tester);

    expect(invoked, isFalse);
  });

  testWidgets('keeps the text and the send action after a failure', (
    tester,
  ) async {
    var attempts = 0;
    Object? asyncError;
    await runZonedGuarded(() async {
      await pumpHost(tester, (text) async {
        attempts++;
        if (attempts == 1) throw Exception('network');
      });

      await tester.enterText(find.byType(TextField), 'retry me');
      await tester.pump();
      await tapPrimary(tester);

      expect(attempts, 1);
      expect(controller.text.text, 'retry me');

      await tapPrimary(tester);

      expect(attempts, 2);
      expect(controller.text.text, isEmpty);
    }, (error, stack) => asyncError = error);

    expect(asyncError, isA<Exception>());
  });

  testWidgets('a second tap while the first send is in flight is ignored', (
    tester,
  ) async {
    final gate = Completer<void>();
    var attempts = 0;
    await pumpHost(tester, (text) {
      attempts++;
      return gate.future;
    });

    await tester.enterText(find.byType(TextField), 'once');
    await tester.pump();
    await tapPrimary(tester);
    await tapPrimary(tester);

    expect(attempts, 1);

    gate.complete();
    await tester.pump();
  });
}
