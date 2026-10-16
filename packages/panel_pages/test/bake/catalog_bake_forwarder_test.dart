import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';

void main() {
  late EventNotifier<PanelCatalogScrollEvent> events;
  late FakeBakeActivityPort port;

  setUp(() {
    events = EventNotifier<PanelCatalogScrollEvent>();
    port = FakeBakeActivityPort();
    addTearDown(events.dispose);
  });

  CatalogBakeForwarder forward({BakeActivityPort? to}) {
    final forwarder = CatalogBakeForwarder(events: events, port: to ?? port);
    addTearDown(forwarder.dispose);
    return forwarder;
  }

  group('motion', () {
    test('tells the baker at once when the catalogue starts moving', () {
      forward();
      events.publish(const PanelCatalogScrollingChanged(scrolling: true));

      expect(port.isScrolling, isTrue);
    });

    test('tells it again when the catalogue rests', () {
      forward();
      events
        ..publish(const PanelCatalogScrollingChanged(scrolling: true))
        ..publish(const PanelCatalogScrollingChanged(scrolling: false));

      expect(port.isScrolling, isFalse);
    });

    test('does not repeat a report that changes nothing', () {
      forward();
      events
        ..publish(const PanelCatalogScrollingChanged(scrolling: true))
        ..publish(const PanelCatalogScrollingChanged(scrolling: true));

      expect(port.reports, hasLength(1));
    });

    test('is one reporter, the same for every report', () {
      final forwarder = forward();
      events
        ..publish(const PanelCatalogScrollingChanged(scrolling: true))
        ..publish(const PanelCatalogScrollingChanged(scrolling: false));

      expect(port.reports.map((report) => report.$1), everyElement(forwarder));
    });

    test('keeps a shared baker waiting for the surface that still moves', () {
      final other = EventNotifier<PanelCatalogScrollEvent>();
      addTearDown(other.dispose);
      forward();
      CatalogBakeForwarder(events: other, port: port);
      events.publish(const PanelCatalogScrollingChanged(scrolling: true));
      other.publish(const PanelCatalogScrollingChanged(scrolling: true));

      events.publish(const PanelCatalogScrollingChanged(scrolling: false));
      expect(port.isScrolling, isTrue);

      other.publish(const PanelCatalogScrollingChanged(scrolling: false));
      expect(port.isScrolling, isFalse);
    });

    test('is not moved by a near-viewport event', () {
      forward();
      events.publish(
        const PanelCatalogSectionNearViewport('s', CatalogSectionEdge.trailing),
      );

      expect(port.reports, isEmpty);
      expect(port.prioritised, isEmpty);
    });
  });

  group('visible band', () {
    test('asks the baker for the glyphs on screen, top first', () {
      forward();
      events.publish(
        PanelCatalogScrollSettled(const [
          ContentKey.unicode('😀'),
          ContentKey.unicode('👍🏽'),
        ]),
      );

      expect(port.prioritised, [
        ['😀', '👍🏽'],
      ]);
    });

    test('leaves out content that is not a unicode glyph', () {
      forward();
      events.publish(
        PanelCatalogScrollSettled(const [
          ContentKey.document('5368'),
          ContentKey.unicode('😀'),
          ContentKey.external('x'),
        ]),
      );

      expect(port.prioritised, [
        ['😀'],
      ]);
    });
  });

  group('swapping the baker', () {
    test('tells the old one the surface rests and the new one it moves', () {
      final forwarder = forward();
      final next = FakeBakeActivityPort();
      events.publish(const PanelCatalogScrollingChanged(scrolling: true));

      forwarder.port = next;

      expect(port.isScrolling, isFalse);
      expect(next.isScrolling, isTrue);
    });

    test('tells the new baker nothing about motion while at rest', () {
      final forwarder = forward();
      final next = FakeBakeActivityPort();

      forwarder.port = next;

      expect(next.reports, isEmpty);
    });

    test('hands the new baker the band the user is looking at', () {
      final forwarder = forward();
      final next = FakeBakeActivityPort();
      events.publish(
        PanelCatalogScrollSettled(const [ContentKey.unicode('😀')]),
      );

      forwarder.port = next;

      expect(next.prioritised, [
        ['😀'],
      ]);
    });

    test('does not hand over a band that scrolling has left behind', () {
      final forwarder = forward();
      final next = FakeBakeActivityPort();
      events
        ..publish(PanelCatalogScrollSettled(const [ContentKey.unicode('😀')]))
        ..publish(const PanelCatalogScrollingChanged(scrolling: true));

      forwarder.port = next;

      expect(next.prioritised, isEmpty);
    });

    test('works while no baker exists and picks up the one set later', () {
      final forwarder = CatalogBakeForwarder(events: events);
      addTearDown(forwarder.dispose);
      events.publish(const PanelCatalogScrollingChanged(scrolling: true));

      forwarder.port = port;

      expect(port.isScrolling, isTrue);
    });
  });

  group('dispose', () {
    test('tells the baker the surface is not moving', () {
      final forwarder = forward();
      events.publish(const PanelCatalogScrollingChanged(scrolling: true));

      forwarder.dispose();

      expect(port.isScrolling, isFalse);
    });

    test('stops forwarding', () {
      forward().dispose();
      events.publish(const PanelCatalogScrollingChanged(scrolling: true));

      expect(port.reports, isEmpty);
    });
  });
}
