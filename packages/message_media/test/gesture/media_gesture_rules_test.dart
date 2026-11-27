/// The rules under the media's gestures, as plain values: what a tap on
/// each part does per platform, the per-item actions protection allows,
/// the semantics label, and the chat state's origin lookup.
///
/// **Seam:** `MediaGesturePolicy.actionOf`, `MediaItemAction
/// .allowedItemActions` over `ChatProtection`, `MediaSemanticsStrings
/// .label` and `MessageMediaState.rectOf`.
library;

import 'dart:ui' show Rect;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart';

MediaItem _item(MediaItemKind kind) => MediaItem(
  id: const MediaItemId('a'),
  kind: kind,
  descriptor: const ContentDescriptor(key: ContentKey.document('doc-a')),
);

const _waiting = AssetLoadState(
  stage: AssetStage.none,
  transfer: AssetTransfer.awaitingUser(),
);
const _loading = AssetLoadState(
  stage: AssetStage.preview,
  transfer: AssetTransfer.receiving(10, 100),
);
const _failed = AssetLoadState(
  stage: AssetStage.preview,
  transfer: AssetTransfer.failed(AssetFailureKind.transient),
);
const _shown = AssetLoadState(stage: AssetStage.full);

void main() {
  group('actionOf', () {
    test('android: a loading picture opens the viewer; the status control '
        'cancels, downloads, retries', () {
      const policy = MediaGesturePolicy.android();
      expect(
        policy.actionOf(MediaPart.content, _loading),
        MediaPartAction.openViewer,
      );
      expect(
        policy.actionOf(MediaPart.status, _loading),
        MediaPartAction.cancel,
      );
      expect(
        policy.actionOf(MediaPart.status, _waiting),
        MediaPartAction.download,
      );
      expect(
        policy.actionOf(MediaPart.status, _failed),
        MediaPartAction.download,
      );
      expect(
        policy.actionOf(MediaPart.content, _shown),
        MediaPartAction.openViewer,
      );
    });

    for (final policy in const [
      MediaGesturePolicy.ios(),
      MediaGesturePolicy.desktop(),
    ]) {
      test('${policy.loadingTap.name}: the content cancels a load', () {
        expect(
          policy.actionOf(MediaPart.content, _loading),
          MediaPartAction.cancel,
        );
        expect(
          policy.actionOf(MediaPart.content, _waiting),
          MediaPartAction.openViewer,
        );
      });
    }

    test('a spoiler only reveals; the options are the viewport\'s', () {
      const policy = MediaGesturePolicy.desktop();
      for (final state in const [_waiting, _loading, _shown]) {
        expect(
          policy.actionOf(MediaPart.spoiler, state),
          MediaPartAction.reveal,
        );
        expect(policy.actionOf(MediaPart.options, state), MediaPartAction.none);
      }
    });

    test('the presets per family, and the guard window', () {
      expect(
        MessageMediaPolicy.forPlatform(TargetPlatform.android).gestures,
        const MediaGesturePolicy.android(),
      );
      expect(
        const MessageMediaPolicy.ios().gestures.loadingTap,
        MediaLoadingTap.anywhere,
      );
      const desktop = MediaGesturePolicy.desktop();
      expect(desktop.clickCursor, isTrue);
      expect(desktop.hover?.duration, const Duration(milliseconds: 200));
      expect(const MediaGesturePolicy.android().hover, isNull);
      expect(
        const MediaGesturePolicy().activationGuard,
        const Duration(milliseconds: 400),
      );
      expect(
        desktop.copyWith(replaceHover: true).hover,
        isNull,
        reason: 'a host clears the highlight',
      );
    });
  });

  group('allowedItemActions', () {
    Set<MediaItemAction> allowed(
      MediaItemKind kind, {
      ChatProtection protection = const ChatProtection(),
      bool messageProtected = false,
    }) => MediaItemAction.allowedItemActions(
      _item(kind),
      protection: protection,
      messageProtected: messageProtected,
    );

    const leave = {
      MediaItemAction.saveToGallery,
      MediaItemAction.saveToDownloads,
      MediaItemAction.saveAs,
      MediaItemAction.showInFolder,
      MediaItemAction.copyImage,
      MediaItemAction.copyFileName,
      MediaItemAction.share,
    };

    test('an unprotected message offers every action its kind supports', () {
      expect(allowed(MediaItemKind.photo), {
        MediaItemAction.saveToGallery,
        MediaItemAction.saveAs,
        MediaItemAction.showInFolder,
        MediaItemAction.copyImage,
        MediaItemAction.share,
        MediaItemAction.cancelDownload,
      });
      expect(allowed(MediaItemKind.video), {
        MediaItemAction.saveToGallery,
        MediaItemAction.saveAs,
        MediaItemAction.showInFolder,
        MediaItemAction.share,
        MediaItemAction.cancelDownload,
      });
      expect(allowed(MediaItemKind.file), {
        MediaItemAction.saveToDownloads,
        MediaItemAction.saveAs,
        MediaItemAction.showInFolder,
        MediaItemAction.copyFileName,
        MediaItemAction.share,
        MediaItemAction.cancelDownload,
      });
      expect(
        allowed(const MediaItemKind.custom('poll')),
        allowed(MediaItemKind.file),
      );
    });

    test('a protected chat or a protected message leaves no save, copy or '
        'share', () {
      const chat = ChatProtection(copy: false, forward: false, save: false);
      for (final kind in MediaItemKind.builtIns) {
        for (final result in [
          allowed(kind, protection: chat),
          allowed(kind, messageProtected: true),
        ]) {
          expect(result.intersection(leave), isEmpty, reason: '$kind');
          expect(result, {MediaItemAction.cancelDownload});
        }
      }
    });

    test('each flag takes its own actions', () {
      expect(
        allowed(
          MediaItemKind.photo,
          protection: const ChatProtection(copy: false),
        ),
        isNot(contains(MediaItemAction.copyImage)),
      );
      expect(
        allowed(
          MediaItemKind.photo,
          protection: const ChatProtection(copy: false),
        ),
        contains(MediaItemAction.share),
      );
      final noForward = allowed(
        MediaItemKind.photo,
        protection: const ChatProtection(forward: false),
      );
      expect(noForward, isNot(contains(MediaItemAction.share)));
      expect(noForward, contains(MediaItemAction.saveToGallery));
      final noSave = allowed(
        MediaItemKind.file,
        protection: const ChatProtection(save: false),
      );
      expect(noSave, {
        MediaItemAction.copyFileName,
        MediaItemAction.cancelDownload,
      });
    });

    test('capture blocking alone takes nothing', () {
      expect(
        allowed(
          MediaItemKind.photo,
          protection: const ChatProtection(captureBlocked: true),
        ),
        allowed(MediaItemKind.photo),
      );
    });
  });

  group('the semantics label', () {
    test('kind, then duration or size, then progress', () {
      const strings = MediaSemanticsStrings.english;
      expect(strings.label(kind: MediaItemKind.photo), 'Photo');
      expect(
        strings.label(
          kind: MediaItemKind.video,
          duration: const Duration(minutes: 61, seconds: 5),
        ),
        'Video, 1:01:05',
      );
      expect(
        strings.label(
          kind: MediaItemKind.file,
          size: 1536,
          loading: true,
          fraction: 0.25,
        ),
        'File, 1.5 KB, Downloading, 25%',
      );
      expect(
        strings.label(kind: MediaItemKind.animation, loading: true),
        'GIF, Downloading',
      );
      final host = strings.copyWith(kind: (kind) => 'Foto');
      expect(host.label(kind: MediaItemKind.photo), 'Foto');
    });
  });

  group('the origin lookup', () {
    test('asks the mounted views, the latest first, and none after '
        'they leave', () {
      final state = MessageMediaState();
      addTearDown(state.dispose);
      const id = MediaItemId('a');
      const first = Rect.fromLTWH(0, 0, 10, 10);
      const second = Rect.fromLTWH(5, 5, 10, 10);
      Rect? older(MediaItemId item) => item == id ? first : null;
      Rect? newer(MediaItemId item) => item == id ? second : null;

      expect(state.rectOf(id), isNull);
      state
        ..attachOrigins(older)
        ..attachOrigins(newer)
        ..attachOrigins(newer);
      expect(state.rectOf(id), second);
      expect(state.rectOf(const MediaItemId('b')), isNull);
      state.detachOrigins(newer);
      expect(state.rectOf(id), first);
      state.detachOrigins(older);
      expect(state.rectOf(id), isNull);
    });
  });
}
