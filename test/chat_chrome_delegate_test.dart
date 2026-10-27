import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter_test/flutter_test.dart';

const ChatFloatingHeaderZone _header = ChatFloatingHeaderZone(
  restTop: 10,
  extent: 30,
);

ChatRowChromeEffect _resolve(
  ChatRowChromeDelegate delegate, {
  required double top,
  ChatFloatingHeaderZone header = _header,
}) => delegate.resolve(
  ChatRowChromeMetrics(top: top, extent: 30, header: header),
);

ChatFloatingHeaderEffect _resolveHeader(
  ChatDayHeaderDelegate delegate, {
  double? lead,
  double activity = 1,
}) => delegate.resolveFloatingHeader(
  ChatDayHeaderMetrics(
    restTop: 10,
    extent: 30,
    leadingSeparatorTop: lead,
    activity: activity,
  ),
);

void main() {
  group('row chrome delegates', () {
    test('opaque ignores the header', () {
      const delegate = ChatRowChromeDelegate.opaque();
      expect(_resolve(delegate, top: -100), ChatRowChromeEffect.visible);
      expect(_resolve(delegate, top: 10), ChatRowChromeEffect.visible);
    });

    test('fadeUnderHeader fades over the band above the header bottom', () {
      const delegate = ChatRowChromeDelegate.fadeUnderHeader();
      // Header bottom = 40.
      expect(_resolve(delegate, top: 40).opacity, 1);
      expect(_resolve(delegate, top: 30).opacity, closeTo(0.5, 1e-9));
      final gone = _resolve(delegate, top: 20);
      expect(gone.opacity, 0);
      expect(gone.hitTestable, isFalse);
    });

    test('fadeUnderHeader follows a pushed header bottom', () {
      const delegate = ChatRowChromeDelegate.fadeUnderHeader();
      const pushed = ChatFloatingHeaderZone(
        restTop: 10,
        extent: 30,
        offset: -10,
      );
      expect(_resolve(delegate, top: 30, header: pushed).opacity, 1);
    });

    test('fadeUnderHeader stays visible with no header', () {
      const delegate = ChatRowChromeDelegate.fadeUnderHeader();
      expect(
        _resolve(delegate, top: -50, header: ChatFloatingHeaderZone.none),
        ChatRowChromeEffect.visible,
      );
    });

    test('hideUnderHeader hides from the rest line up', () {
      const delegate = ChatRowChromeDelegate.hideUnderHeader();
      expect(_resolve(delegate, top: 11), ChatRowChromeEffect.visible);
      expect(_resolve(delegate, top: 10), ChatRowChromeEffect.hidden);
      expect(_resolve(delegate, top: -5), ChatRowChromeEffect.hidden);
      expect(
        _resolve(delegate, top: -5, header: ChatFloatingHeaderZone.none),
        ChatRowChromeEffect.visible,
      );
    });

    test('built-in delegates are value-equal', () {
      expect(
        const ChatRowChromeDelegate.fadeUnderHeader(band: 12),
        const ChatFadeUnderHeaderRowChrome(band: 12),
      );
      expect(
        const ChatRowChromeDelegate.fadeUnderHeader(band: 12),
        isNot(const ChatRowChromeDelegate.fadeUnderHeader()),
      );
      expect(
        const ChatFadingDayHeader().inlineSeparator,
        const ChatRowChromeDelegate.fadeUnderHeader(),
      );
    });
  });

  group('ChatFadingDayHeader', () {
    const delegate = ChatFadingDayHeader();

    test('never moves', () {
      expect(_resolveHeader(delegate, lead: 25).offset, 0);
      expect(_resolveHeader(delegate, lead: 100).offset, 0);
    });

    test('follows activity unless a separator is under its zone', () {
      expect(_resolveHeader(delegate, activity: 0.25).opacity, 0.25);
      expect(_resolveHeader(delegate, lead: 100, activity: 0.25).opacity, 0.25);
      // Rest 10 + extent 30: a separator above 40 fades under the header.
      expect(_resolveHeader(delegate, lead: 39, activity: 0).opacity, 1);
    });

    test('holds activity only while a separator is under its zone', () {
      expect(_resolveHeader(delegate, lead: 39).holdsActivity, isTrue);
      expect(_resolveHeader(delegate, lead: 40).holdsActivity, isFalse);
      expect(_resolveHeader(delegate).holdsActivity, isFalse);
    });

    test('hidesWhenIdle false keeps it opaque and never holds', () {
      const opaque = ChatFadingDayHeader(hidesWhenIdle: false);
      expect(_resolveHeader(opaque, activity: 0).opacity, 1);
      expect(_resolveHeader(opaque, lead: 39).holdsActivity, isFalse);
    });
  });

  group('ChatPushingDayHeader', () {
    const delegate = ChatPushingDayHeader();

    test('rests while the next separator is at least one extent below', () {
      expect(_resolveHeader(delegate, lead: 40).offset, 0);
      expect(_resolveHeader(delegate).offset, 0);
    });

    test('is pushed so its bottom touches the rising separator', () {
      expect(_resolveHeader(delegate, lead: 30).offset, -10);
      expect(_resolveHeader(delegate, lead: 11).offset, closeTo(-29, 1e-9));
    });

    test('snaps back and holds once the separator reaches the rest line', () {
      final held = _resolveHeader(delegate, lead: 10, activity: 0);
      expect(held.offset, 0);
      expect(held.opacity, 1);
      expect(held.hitTestable, isTrue);
      expect(held.holdsActivity, isTrue);
    });

    test('hides with activity while not standing in for a separator', () {
      final idle = _resolveHeader(delegate, lead: 30, activity: 0);
      expect(idle.opacity, 0);
      expect(idle.hitTestable, isFalse);
      expect(idle.holdsActivity, isFalse);
    });

    test('inline separators hide under the header', () {
      expect(
        delegate.inlineSeparator,
        const ChatRowChromeDelegate.hideUnderHeader(),
      );
    });
  });
}
