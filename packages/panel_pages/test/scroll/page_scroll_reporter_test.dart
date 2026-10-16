import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  late EventNotifier<PanelCatalogScrollEvent> events;
  late List<PageScrollActivity> reports;
  late bool atEdge;
  late PageScrollReporter reporter;

  setUp(() {
    events = EventNotifier<PanelCatalogScrollEvent>();
    reports = [];
    atEdge = false;
    reporter = PageScrollReporter(
      events: events,
      report: reports.add,
      atEdge: () => atEdge,
    );
    addTearDown(events.dispose);
  });

  group('a finger on the content', () {
    test('reports every step of a drag with its delta', () {
      events
        ..publish(const PanelCatalogUserDragStart())
        ..publish(const PanelCatalogViewportScrolled(12))
        ..publish(const PanelCatalogViewportScrolled(-5));

      expect(reports, [const PageScrollDrag(12), const PageScrollDrag(-5)]);
    });

    test('reports the coasting after release as a fling', () {
      events
        ..publish(const PanelCatalogUserDragStart())
        ..publish(const PanelCatalogViewportScrolled(8))
        ..publish(const PanelCatalogUserDragEnd(900))
        ..publish(const PanelCatalogFlingStart(900))
        ..publish(const PanelCatalogViewportScrolled(30));

      expect(reports, [const PageScrollDrag(8), const PageScrollFling(30)]);
    });

    test('goes back to drag steps once the fling ended', () {
      events
        ..publish(const PanelCatalogFlingStart(900))
        ..publish(const PanelCatalogFlingEnd())
        ..publish(const PanelCatalogViewportScrolled(4));

      expect(reports, [const PageScrollDrag(4)]);
    });

    test('reports a wheel step, which has no drag around it, as a drag', () {
      events.publish(const PanelCatalogViewportScrolled(40));

      expect(reports, [const PageScrollDrag(40)]);
    });
  });

  group('rest', () {
    test('reports idle when the catalogue stops moving', () {
      events.publish(const PanelCatalogScrollingChanged(scrolling: false));

      expect(reports, [const PageScrollIdle()]);
    });

    test('says whether it rests at an end of the content', () {
      atEdge = true;
      events.publish(const PanelCatalogScrollingChanged(scrolling: false));

      expect(reports, [const PageScrollIdle(atEdge: true)]);
    });

    test('says nothing when the catalogue starts moving', () {
      events.publish(const PanelCatalogScrollingChanged(scrolling: true));

      expect(reports, isEmpty);
    });
  });

  group('programmatic motion', () {
    test('reports a jump once however many events announce it', () {
      events
        ..publish(const PanelCatalogSectionJumpStart(2, 480))
        ..publish(
          const PanelCatalogAnimateStart(480, Duration(milliseconds: 200)),
        )
        ..publish(const PanelCatalogOffsetChanged(120, 120))
        ..publish(const PanelCatalogOffsetChanged(240, 120));

      expect(reports, [const PageScrollJump()]);
    });

    test('reports the next jump after the previous one came to rest', () {
      events
        ..publish(const PanelCatalogProgrammaticJump(300))
        ..publish(const PanelCatalogScrollingChanged(scrolling: false))
        ..publish(const PanelCatalogProgrammaticJump(0));

      expect(reports, [
        const PageScrollJump(),
        const PageScrollIdle(),
        const PageScrollJump(),
      ]);
    });

    test('a finger takes over from a jump in flight', () {
      events
        ..publish(const PanelCatalogSectionJumpStart(1, 200))
        ..publish(const PanelCatalogUserDragStart())
        ..publish(const PanelCatalogSectionJumpStart(1, 200));

      expect(reports, [const PageScrollJump(), const PageScrollJump()]);
    });

    test('ignores motion events that carry no scrolling', () {
      events
        ..publish(const PanelCatalogFocusChanged(null))
        ..publish(
          const PanelCatalogSectionNearViewport(
            'a',
            CatalogSectionEdge.leading,
          ),
        );

      expect(reports, isEmpty);
    });
  });

  test('stops reporting after dispose', () {
    reporter.dispose();
    events.publish(const PanelCatalogViewportScrolled(10));

    expect(reports, isEmpty);
  });
}
