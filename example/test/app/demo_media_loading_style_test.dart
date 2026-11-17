/// The app's look of loading media, and the chat kinds' download tags.
///
/// **Seam:** [DemoMediaLoadingStyle] under a [ChromeThemeScope], read back
/// through `MediaLoadingStyleScope.resolve`; [ChatKind] by value.
library;

import 'package:chat_scroll_view_example/src/app/demo_media_loading_style.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_kind.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';

void main() {
  group('DemoMediaLoadingStyle', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      testWidgets('takes colours and text from the chrome tokens, the rest '
          'from the platform (${platform.name})', (tester) async {
        late MediaLoadingStyle resolved;
        late ChromeThemeData theme;
        await tester.pumpWidget(
          Theme(
            data: ThemeData(platform: platform),
            child: ChromeThemeScope(
              palette: const ChromePalette.dark(),
              child: DemoMediaLoadingStyle(
                child: Builder(
                  builder: (context) {
                    theme = ChromeThemeScope.of(context);
                    resolved = MediaLoadingStyleScope.resolve(context);
                    return const SizedBox();
                  },
                ),
              ),
            ),
          ),
        );

        final base = MediaLoadingStyle.forPlatform(platform);
        expect(resolved.stages.outlineFill, theme.placeholder.skeleton);
        expect(
          resolved.badge.background,
          theme.palette.shadow.withValues(alpha: base.badge.background.a),
        );
        expect(
          resolved.badge.textStyle.fontSize,
          base.badge.textStyle.fontSize,
        );
        expect(resolved.badge.textStyle.color, base.badge.textStyle.color);
        // Geometry and timing stay the platform's.
        expect(resolved.status, base.status);
        expect(resolved.stages.stageFade, base.stages.stageFade);
        expect(resolved.badge.offset, base.badge.offset);
      });
    }
  });

  group('ChatKind', () {
    test('tags each kind with the well-known class of its conversation', () {
      expect(
        ChatKind.privateChat.downloadContext,
        AutoDownloadContext.privateChats,
      );
      expect(ChatKind.group.downloadContext, AutoDownloadContext.groups);
      expect(ChatKind.channel.downloadContext, AutoDownloadContext.channels);
    });
  });
}
