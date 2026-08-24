/// Shared catalog size presets for Panel Catalog A/B benches.
///
/// Leaf totals mirror chat-scroll small/medium/large stress bands so reports
/// stay comparable across engines.
library;

import 'package:flutter/painting.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Viewport logical size shared by candidate and baseline harnesses.
const Size kBenchViewportSize = Size(400, 600);

/// Grid columns (Telegram-ish phone keyboard density at 400px).
const int kBenchSpanCount = 8;

/// Fixed cell / row pitch in logical pixels.
const double kBenchCellExtent = 48;

/// Section header height in logical pixels.
const double kBenchHeaderExtent = 32;

/// Small catalog (~64 leaves).
const int kSmallLeafCount = 64;

/// Medium catalog (~512 leaves).
const int kMediumLeafCount = 512;

/// Large catalog (~4096 leaves).
const int kLargeLeafCount = 4096;

/// Leaf-count presets exercised by every A/B scenario.
const List<int> kBenchLeafCounts = [
  kSmallLeafCount,
  kMediumLeafCount,
  kLargeLeafCount,
];

/// Builds deterministic unicode sections totaling approximately [leafCount].
///
/// Eight leaves per section keeps near-path (≤ 9 flat rows) and far-path
/// (beyond gate) targets available at every preset — including the small
/// catalog (64 leaves → 8 sections).
List<CatalogSection> generateCatalogSections(int leafCount) {
  const leavesPerSection = 8;
  final sectionCount = (leafCount / leavesPerSection).ceil().clamp(1, 9999);
  final sections = <CatalogSection>[];
  var remaining = leafCount;
  for (var s = 0; s < sectionCount; s++) {
    final n = remaining < leavesPerSection ? remaining : leavesPerSection;
    remaining -= n;
    sections.add(
      CatalogSection(
        id: 's$s',
        title: 'Section $s',
        leaves: [
          for (var j = 0; j < n; j++)
            CatalogLeaf.unicode(String.fromCharCode(0x1F600 + (j % 80))),
        ],
      ),
    );
    if (remaining <= 0) break;
  }
  return sections;
}
