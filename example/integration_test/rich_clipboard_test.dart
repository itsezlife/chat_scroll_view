import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rich_clipboard/rich_clipboard.dart';

/// The `RichClipboard` contract against the real system clipboard, through
/// the plugin's native code on the device it runs on. "Another app" copying
/// plain text is Flutter's own plain-text clipboard.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  RichClipboardContract.run(
    () => RichClipboardHarness(
      clipboard: const SystemRichClipboard(),
      putPlainText: (text) => Clipboard.setData(ClipboardData(text: text)),
    ),
  );
}
