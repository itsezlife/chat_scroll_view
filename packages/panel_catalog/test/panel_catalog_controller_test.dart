/// The attach-and-position controller without a viewport.
///
/// **Seam:** [PanelCatalogController] driven against a
/// [FakeCatalogScrollPosition] standing in for the bound render object, and
/// observed through its public offset, flags and `events` Observable.
library;

import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/testing.dart';

void main() {
  late PanelCatalogController controller;
  late List<PanelCatalogScrollEvent> events;

  setUp(() {
    controller = PanelCatalogController();
    events = [];
    controller.events.addListener(events.add);
  });
  tearDown(() => controller.dispose());

  group('while no viewport is attached', () {
    test('jumpTo commits the target and publishes the jump', () {
      controller.jumpTo(120);

      expect(controller.offset, 120);
      expect(events, hasLength(2));
      expect(events[0], isA<PanelCatalogProgrammaticJump>());
      expect((events[0] as PanelCatalogProgrammaticJump).offset, 120);
      expect(events[1], isA<PanelCatalogOffsetChanged>());
      expect((events[1] as PanelCatalogOffsetChanged).delta, 120);
    });

    test('jumpTo to the current offset is silent', () {
      controller.jumpTo(0);

      expect(events, isEmpty);
    });

    test('scrollBy adds to the committed offset and publishes it', () {
      controller
        ..scrollBy(30)
        ..scrollBy(-10);

      expect(controller.offset, 20);
      expect(
        events.whereType<PanelCatalogViewportScrolled>().map((e) => e.delta),
        [30, -10],
      );
    });

    test('scrollBy(0) is silent', () {
      controller.scrollBy(0);

      expect(events, isEmpty);
    });

    test('animateTo commits the target at once and completes', () async {
      await controller.animateTo(300);

      expect(controller.offset, 300);
      expect(events.whereType<PanelCatalogProgrammaticJump>(), hasLength(1));
    });

    test('animateTo within half a pixel of the offset does nothing', () async {
      await controller.animateTo(0.4);

      expect(controller.offset, 0);
      expect(events, isEmpty);
    });

    test('jumpToSection stays pending and is not an active jump', () {
      var done = false;
      unawaited(controller.jumpToSection(3).then((_) => done = true));

      expect(controller.isSectionJumpActive, isFalse);
      expect(done, isFalse);
      expect(events, isEmpty);
    });

    test('the extents are zero', () {
      expect(controller.viewportExtent, 0);
      expect(controller.contentExtent, 0);
      expect(controller.maxScrollExtent, 0);
      expect(controller.hasPosition, isFalse);
    });
  });

  group('attaching a viewport', () {
    test('applies the pending section jump and completes with it', () async {
      final position = FakeCatalogScrollPosition();
      var done = false;
      unawaited(controller.jumpToSection(3).then((_) => done = true));

      controller.attach(position);
      expect(position.commands, ['jumpToSection(3)']);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);

      position.completeMotion();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
    });

    test('a later unbound jumpToSection retargets the same request', () async {
      final position = FakeCatalogScrollPosition();
      final first = controller.jumpToSection(1);
      final second = controller.jumpToSection(4);

      expect(identical(first, second), isTrue);
      controller.attach(position);
      expect(position.commands, ['jumpToSection(4)']);
      position.completeMotion();
      await first;
    });

    test('the committed offset is what the position starts from', () {
      controller.jumpTo(240);

      final position = FakeCatalogScrollPosition(pixels: controller.offset);
      controller.attach(position);

      expect(controller.offset, 240);
    });

    test('the position owns the offset, the extents and the jump flag', () {
      final position = FakeCatalogScrollPosition(
        pixels: 50,
        viewportExtent: 400,
        contentExtent: 1000,
      );
      controller.attach(position);

      expect(controller.hasPosition, isTrue);
      expect(controller.offset, 50);
      expect(controller.viewportExtent, 400);
      expect(controller.contentExtent, 1000);
      expect(controller.maxScrollExtent, 600);

      position.pixels = 75;
      position.isSectionJumpActive = true;
      expect(controller.offset, 75);
      expect(controller.isSectionJumpActive, isTrue);
    });

    test('commands go to the position and the controller adds no events', () {
      final position = FakeCatalogScrollPosition();
      controller.attach(position);

      controller
        ..jumpTo(10)
        ..scrollBy(5);
      controller.animateTo(
        90,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      controller.jumpToSection(2);

      expect(position.commands, [
        'jumpTo(10.0)',
        'scrollBy(5.0)',
        'animateTo(90.0)',
        'jumpToSection(2)',
      ]);
      expect(events, isEmpty);
    });

    test(
      'a second jumpToSection while one is active returns the same future',
      () {
        final position = FakeCatalogScrollPosition();
        controller.attach(position);

        final first = controller.jumpToSection(2);
        final second = controller.jumpToSection(5);

        expect(identical(first, second), isTrue);
        expect(position.commands, ['jumpToSection(2)']);
      },
    );
  });

  group('detaching a viewport', () {
    test('keeps the offset the position had reached', () {
      final position = FakeCatalogScrollPosition(pixels: 10);
      controller.attach(position);
      position.pixels = 333;

      controller.detach(position);

      expect(controller.hasPosition, isFalse);
      expect(controller.offset, 333);
      expect(controller.isSectionJumpActive, isFalse);
    });

    test('a position that is not the attached one is ignored', () {
      final attached = FakeCatalogScrollPosition(pixels: 10);
      controller.attach(attached);

      controller.detach(FakeCatalogScrollPosition(pixels: 99));

      expect(controller.hasPosition, isTrue);
      expect(controller.offset, 10);
    });

    test('commands after detach commit again', () {
      final position = FakeCatalogScrollPosition();
      controller.attach(position);
      controller.detach(position);

      controller.jumpTo(70);

      expect(position.commands, isEmpty);
      expect(controller.offset, 70);
    });
  });

  group('events', () {
    test('a listener may remove itself and add another while it runs', () {
      final heard = <String>[];
      void next(PanelCatalogScrollEvent _) => heard.add('next');
      void once(PanelCatalogScrollEvent _) {
        heard.add('once');
        controller.events
          ..removeListener(once)
          ..addListener(next);
      }

      controller.events.addListener(once);
      controller.jumpTo(1); // two events: jump and offset
      controller.jumpTo(2);

      expect(heard, ['once', 'next', 'next', 'next']);
    });

    test('the same listener twice is called once per event', () {
      var calls = 0;
      void listener(PanelCatalogScrollEvent _) => calls++;
      controller.events
        ..addListener(listener)
        ..addListener(listener);

      controller.jumpTo(1);

      expect(calls, 2); // jump and offset, once each
    });
  });

  group('dispose', () {
    test('commands become silent no-ops and the events stop', () async {
      controller.dispose();

      controller
        ..jumpTo(10)
        ..scrollBy(10);
      await controller.animateTo(50);
      await controller.jumpToSection(1);

      expect(controller.offset, 0);
      expect(events, isEmpty);
      expect(controller.isDisposed, isTrue);
    });

    test('completes a pending section jump', () async {
      final pending = controller.jumpToSection(2);

      controller.dispose();

      await pending;
    });

    test('is idempotent and leaves an attached position alone', () {
      final position = FakeCatalogScrollPosition(pixels: 5);
      controller.attach(position);

      controller
        ..dispose()
        ..dispose();
      controller.detach(position);

      expect(position.commands, isEmpty);
    });

    test('a listener added after dispose is never called', () {
      controller.dispose();
      var calls = 0;
      controller.events.addListener((_) => calls++);

      controller.jumpTo(5);

      expect(calls, 0);
    });
  });
}
