import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  late StreamController<PanelCatalogScrollEvent> events;
  late List<PageScrollActivity> reports;
  late bool atEdge;
  late PageScrollReporter reporter;

  setUp(() {
    events = StreamController<PanelCatalogScrollEvent>.broadcast(sync: true);
    reports = [];
    atEdge = false;
    reporter = PageScrollReporter(
      events: events.stream,
      report: reports.add,
      atEdge: () => atEdge,
    );
    addTearDown(events.close);
  });

  group('a finger on the content', () {
    test('reports every step of a drag with its delta', () {
      events
        ..add(const PanelCatalogUserDragStart())
        ..add(const PanelCatalogViewportScrolled(12))
        ..add(const PanelCatalogViewportScrolled(-5));

      expect(reports, [const PageScrollDrag(12), const PageScrollDrag(-5)]);
    });

    test('reports the coasting after release as a fling', () {
      events
        ..add(const PanelCatalogUserDragStart())
        ..add(const PanelCatalogViewportScrolled(8))
        ..add(const PanelCatalogUserDragEnd(900))
        ..add(const PanelCatalogFlingStart(900))
        ..add(const PanelCatalogViewportScrolled(30));

      expect(reports, [const PageScrollDrag(8), const PageScrollFling(30)]);
    });

    test('goes back to drag steps once the fling ended', () {
      events
        ..add(const PanelCatalogFlingStart(900))
        ..add(const PanelCatalogFlingEnd())
        ..add(const PanelCatalogViewportScrolled(4));

      expect(reports, [const PageScrollDrag(4)]);
    });

    test('reports a wheel step, which has no drag around it, as a drag', () {
      events.add(const PanelCatalogViewportScrolled(40));

      expect(reports, [const PageScrollDrag(40)]);
    });
  });

  group('rest', () {
    test('reports idle when the catalogue stops moving', () {
      events.add(const PanelCatalogScrollingChanged(scrolling: false));

      expect(reports, [const PageScrollIdle()]);
    });

    test('says whether it rests at an end of the content', () {
      atEdge = true;
      events.add(const PanelCatalogScrollingChanged(scrolling: false));

      expect(reports, [const PageScrollIdle(atEdge: true)]);
    });

    test('says nothing when the catalogue starts moving', () {
      events.add(const PanelCatalogScrollingChanged(scrolling: true));

      expect(reports, isEmpty);
    });
  });

  group('programmatic motion', () {
    test('reports a jump once however many events announce it', () {
      events
        ..add(const PanelCatalogSectionJumpStart(2, 480))
        ..add(const PanelCatalogAnimateStart(480, Duration(milliseconds: 200)))
        ..add(const PanelCatalogOffsetChanged(120, 120))
        ..add(const PanelCatalogOffsetChanged(240, 120));

      expect(reports, [const PageScrollJump()]);
    });

    test('reports the next jump after the previous one came to rest', () {
      events
        ..add(const PanelCatalogProgrammaticJump(300))
        ..add(const PanelCatalogScrollingChanged(scrolling: false))
        ..add(const PanelCatalogProgrammaticJump(0));

      expect(reports, [
        const PageScrollJump(),
        const PageScrollIdle(),
        const PageScrollJump(),
      ]);
    });

    test('a finger takes over from a jump in flight', () {
      events
        ..add(const PanelCatalogSectionJumpStart(1, 200))
        ..add(const PanelCatalogUserDragStart())
        ..add(const PanelCatalogSectionJumpStart(1, 200));

      expect(reports, [const PageScrollJump(), const PageScrollJump()]);
    });

    test('ignores motion events that carry no scrolling', () {
      events
        ..add(const PanelCatalogFocusChanged(null))
        ..add(
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
    events.add(const PanelCatalogViewportScrolled(10));

    expect(reports, isEmpty);
  });
}
