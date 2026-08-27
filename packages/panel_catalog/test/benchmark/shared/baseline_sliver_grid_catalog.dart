/// Idiomatic Flutter catalog body: section headers + [SliverGrid] cells.
///
/// Mirrors how most packages build emoji/sticker grids ([CustomScrollView]
/// with [SliverToBoxAdapter] headers and [SliverGrid] per section) — the
/// common alternative to Panel Catalog Viewport, distinct from the frozen
/// SuperSliverList flat header+row baseline.
library;

import 'package:flutter/material.dart';
import 'package:panel_catalog/panel_catalog.dart';

import 'bench_widgets.dart';
import 'catalog_presets.dart';

List<String> _glyphsOf(CatalogSection section) => [
  for (final leaf in section.leaves)
    if (leaf case UnicodeCatalogLeaf(:final glyph)) glyph,
];

/// Content-y of section [sectionIndex] header for jump benches.
double sliverGridHeaderOffset(
  List<CatalogSection> sections, {
  required int sectionIndex,
  required int spanCount,
  double cellExtent = kBenchCellExtent,
  double headerExtent = kBenchHeaderExtent,
}) {
  var y = 0.0;
  for (var s = 0; s < sections.length; s++) {
    if (s == sectionIndex) return y;
    y += headerExtent;
    final rows = (_glyphsOf(sections[s]).length / spanCount).ceil();
    y += rows * cellExtent;
  }
  return y;
}

/// Sectioned [SliverGrid] catalog body for A/B comparison.
class BaselineSliverGridCatalog extends StatefulWidget {
  const BaselineSliverGridCatalog({
    required this.sections,
    required this.scrollController,
    this.spanCount = kBenchSpanCount,
    super.key,
  });

  final List<CatalogSection> sections;
  final ScrollController scrollController;
  final int spanCount;

  @override
  State<BaselineSliverGridCatalog> createState() =>
      BaselineSliverGridCatalogState();
}

/// Public state for bench offset helpers.
class BaselineSliverGridCatalogState extends State<BaselineSliverGridCatalog> {
  /// Content-y of section [sectionIndex] header.
  double headerOffset(int sectionIndex) => sliverGridHeaderOffset(
    widget.sections,
    sectionIndex: sectionIndex,
    spanCount: widget.spanCount,
  );

  @override
  Widget build(BuildContext context) {
    final span = widget.spanCount;
    return BenchmarkTimingWrapper(
      child: CustomScrollView(
        controller: widget.scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          for (final section in widget.sections) ...[
            SliverToBoxAdapter(
              child: SizedBox(
                height: kBenchHeaderExtent,
                width: double.infinity,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      section.title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: span,
                mainAxisExtent: kBenchCellExtent,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final glyphs = _glyphsOf(section);
                  return BaselineGlyphCell(
                    glyph: glyphs[index],
                    extent: kBenchCellExtent,
                  );
                },
                childCount: _glyphsOf(section).length,
                addAutomaticKeepAlives: false,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
