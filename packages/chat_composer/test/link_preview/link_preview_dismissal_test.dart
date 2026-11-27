/// `LinkPreviewDismissal`: each policy's rule table, the state's round trip
/// and the per-platform default.
///
/// **Seam:** the headless type's public inputs (`dismiss`, `edited`,
/// `linksRead`, `sent`) and answers (`searchEnabled`, `allows`,
/// `disabledUrls`, `state`), plus the events it reports.
library;

import 'dart:convert';

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final _a = Uri.parse('https://a.example/page');
final _b = Uri.parse('https://b.example/');

LinkPreviewDismissal _dismissal(
  LinkPreviewDismissalPolicy policy, {
  LinkPreviewDismissalState? restored,
}) => LinkPreviewDismissal(
  policy: policy,
  restored: restored,
  correlation: () => const ChatCorrelation(chatId: 'chat-1'),
);

void main() {
  group('fieldUntilBigEdit', () {
    const policy = LinkPreviewDismissalPolicy.fieldUntilBigEdit;

    test('the cross turns search off for the field', () {
      final dismissal = _dismissal(policy)..dismiss(_a);

      expect(dismissal.searchEnabled, isFalse);
      expect(dismissal.allows(_a), isFalse);
      expect(dismissal.allows(_b), isFalse);
    });

    // Each row: the text before and after one edit, and whether search
    // comes back. A deletion of more than one character, an insertion of
    // more than two, or an empty field turn it on again.
    final rows = <(String, String, String, bool)>[
      ('one character typed', 'see x', 'see xy', false),
      ('two characters typed', 'see x', 'see xyz', false),
      ('three characters typed', 'see x', 'see xyzw', true),
      ('one character deleted', 'see xy', 'see x', false),
      ('two characters deleted', 'see xyz', 'see x', true),
      (
        'a word replaced by one of the same length',
        'see abc',
        'see xyz',
        false,
      ),
      ('a short word replaced by a long one', 'see a', 'see wxyz', true),
      ('the field emptied', 'x', '', true),
      ('a deletion in the middle', 'abcdef', 'abef', true),
    ];
    for (final (name, before, after, resets) in rows) {
      test('$name: ${resets ? 'search on' : 'still off'}', () {
        final dismissal = _dismissal(policy)..dismiss(_a);

        final changed = dismissal.edited(before, after);

        expect(dismissal.searchEnabled, resets);
        expect(changed, resets);
      });
    }

    test('a send turns search on', () {
      final dismissal = _dismissal(policy)..dismiss(_a);

      dismissal.sent();

      expect(dismissal.searchEnabled, isTrue);
    });

    test('a text without links does not reset it', () {
      final dismissal = _dismissal(policy)..dismiss(_a);

      dismissal.linksRead(const []);

      expect(dismissal.searchEnabled, isFalse);
    });
  });

  group('perUrl', () {
    const policy = LinkPreviewDismissalPolicy.perUrl;

    test('the cross disables that URL only', () {
      final dismissal = _dismissal(policy)..dismiss(_a);

      expect(dismissal.searchEnabled, isTrue);
      expect(dismissal.allows(_a), isFalse);
      expect(dismissal.allows(_b), isTrue);
      expect(dismissal.disabledUrls, {_a});
    });

    test('URLs add up', () {
      final dismissal = _dismissal(policy)
        ..dismiss(_a)
        ..dismiss(_b);

      expect(dismissal.disabledUrls, {_a, _b});
    });

    test('edits and a text without links keep the set', () {
      final dismissal = _dismissal(policy)
        ..dismiss(_a)
        ..edited('a long text', '')
        ..linksRead(const []);

      expect(dismissal.disabledUrls, {_a});
    });

    test('a send clears the set', () {
      final dismissal = _dismissal(policy)
        ..dismiss(_a)
        ..sent();

      expect(dismissal.disabledUrls, isEmpty);
      expect(dismissal.allows(_a), isTrue);
    });
  });

  group('untilNoLinks', () {
    const policy = LinkPreviewDismissalPolicy.untilNoLinks;

    test('the cross removes the preview while the text has links', () {
      final dismissal = _dismissal(policy)
        ..dismiss(_a)
        ..linksRead([_b])
        ..edited('see https://a', 'see https://a and more text');

      expect(dismissal.searchEnabled, isFalse);
      expect(dismissal.allows(_b), isFalse);
    });

    test('a text with no link turns it on again', () {
      final dismissal = _dismissal(policy)..dismiss(_a);

      final changed = dismissal.linksRead(const []);

      expect(changed, isTrue);
      expect(dismissal.searchEnabled, isTrue);
    });

    test('a send turns it on again', () {
      final dismissal = _dismissal(policy)
        ..dismiss(_a)
        ..sent();

      expect(dismissal.searchEnabled, isTrue);
    });
  });

  group('state', () {
    for (final policy in LinkPreviewDismissalPolicy.values) {
      test('${policy.name} survives a JSON round trip', () {
        final dismissal = _dismissal(policy)
          ..dismiss(_a)
          ..dismiss(_b);

        final json = jsonDecode(jsonEncode(dismissal.state.toJson()));
        final restored = _dismissal(
          policy,
          restored: LinkPreviewDismissalState.fromJson(json),
        );

        expect(restored.state, dismissal.state);
        expect(restored.searchEnabled, dismissal.searchEnabled);
        expect(restored.allows(_a), dismissal.allows(_a));
        expect(restored.allows(_b), dismissal.allows(_b));
      });
    }

    test('a fresh dismissal has nothing to keep', () {
      final dismissal = _dismissal(LinkPreviewDismissalPolicy.perUrl);

      expect(dismissal.state.isClear, isTrue);
    });

    test('a state of another policy starts clear', () {
      final perUrl = _dismissal(LinkPreviewDismissalPolicy.perUrl)..dismiss(_a);

      final field = _dismissal(
        LinkPreviewDismissalPolicy.fieldUntilBigEdit,
        restored: perUrl.state,
      );

      expect(field.searchEnabled, isTrue);
      expect(field.state.isClear, isTrue);
    });

    test('an unreadable state reads as null', () {
      expect(LinkPreviewDismissalState.fromJson('nope'), isNull);
      expect(LinkPreviewDismissalState.fromJson({'policy': 'other'}), isNull);
      expect(
        LinkPreviewDismissalState.fromJson({
          'policy': 'perUrl',
          'urls': [1, 'https://a.example/page'],
        }),
        LinkPreviewDismissalState(
          policy: LinkPreviewDismissalPolicy.perUrl,
          disabledUrls: {_a},
        ),
      );
    });

    test('restore replaces the state', () {
      final dismissal = _dismissal(LinkPreviewDismissalPolicy.perUrl)
        ..restore(
          LinkPreviewDismissalState(
            policy: LinkPreviewDismissalPolicy.perUrl,
            disabledUrls: {_b},
          ),
        );

      expect(dismissal.disabledUrls, {_b});
    });
  });

  group('per-platform default', () {
    final rows = <(TargetPlatform, bool, LinkPreviewDismissalPolicy)>[
      (TargetPlatform.android, false, .fieldUntilBigEdit),
      (TargetPlatform.fuchsia, false, .fieldUntilBigEdit),
      (TargetPlatform.iOS, false, .perUrl),
      (TargetPlatform.macOS, false, .untilNoLinks),
      (TargetPlatform.windows, false, .untilNoLinks),
      (TargetPlatform.linux, false, .untilNoLinks),
      // The web takes the mobile form of the browser's family.
      (TargetPlatform.iOS, true, .perUrl),
      (TargetPlatform.macOS, true, .fieldUntilBigEdit),
    ];
    for (final (platform, isWeb, expected) in rows) {
      test('${platform.name}${isWeb ? ' (web)' : ''}: ${expected.name}', () {
        expect(
          LinkPreviewDismissalPolicy.forPlatform(platform, isWeb: isWeb),
          expected,
        );
      });
    }
  });

  group('diagnostics', () {
    late RecordingDiagnostics diagnostics;
    setUp(() => diagnostics = RecordingDiagnostics.install());

    test('the cross reports its policy and scope, never the URL', () {
      _dismissal(LinkPreviewDismissalPolicy.perUrl).dismiss(_a);
      _dismissal(LinkPreviewDismissalPolicy.fieldUntilBigEdit).dismiss(_a);

      expect(diagnostics.whereOp(LinkPreviewDismissalOp.dismissed), [
        isChatEvent(
          level: ChatEventLevel.info,
          category: ChatEventCategory.linkPreview,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
          fields: {'policy': 'perUrl', 'scope': 'a.example'},
        ),
        isChatEvent(fields: {'policy': 'fieldUntilBigEdit', 'scope': 'field'}),
      ]);
    });

    test('each reset reports its trigger', () {
      _dismissal(LinkPreviewDismissalPolicy.fieldUntilBigEdit)
        ..dismiss(_a)
        ..edited('abc', 'abcdefg')
        ..dismiss(_a)
        ..edited('abc', '')
        ..dismiss(_a)
        ..sent();
      _dismissal(LinkPreviewDismissalPolicy.untilNoLinks)
        ..dismiss(_a)
        ..linksRead(const []);

      expect(
        diagnostics
            .whereOp(LinkPreviewDismissalOp.dismissalReset)
            .map((event) => event.fields['trigger']),
        ['bigEdit', 'empty', 'send', 'noLinks'],
      );
    });

    test('nothing to reset reports nothing', () {
      _dismissal(LinkPreviewDismissalPolicy.fieldUntilBigEdit)
        ..edited('abc', '')
        ..sent();

      expect(
        diagnostics.whereOp(LinkPreviewDismissalOp.dismissalReset),
        isEmpty,
      );
    });
  });
}
