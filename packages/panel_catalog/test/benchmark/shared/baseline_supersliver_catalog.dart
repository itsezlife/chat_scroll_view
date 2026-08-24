/// Frozen SuperSliverList + widget-cell catalog body for A/B benches.
///
/// Flat header + row list, [SuperSliverList.builder] with extent estimation,
/// and one [Text] glyph widget per cell. Chrome (strip / search) is omitted so
/// the comparison is body-only against [PanelCatalogViewport].
library;

import 'package:flutter/material.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'bench_widgets.dart';
import 'catalog_presets.dart';

export 'bench_widgets.dart';

// --- Flat list model --------------------------------------------------------

sealed class _FlatItem {
  const _FlatItem();

  const factory _FlatItem.header(String title) = _HeaderItem;
  const factory _FlatItem.row(List<String> glyphs) = _RowItem;
}

final class _HeaderItem implements _FlatItem {
  const _HeaderItem(this.title);
  final String title;
}

final class _RowItem implements _FlatItem {
  const _RowItem(this.glyphs);
  final List<String> glyphs;
}

List<_FlatItem> _flatten(
  List<CatalogSection> sections, {
  required int spanCount,
}) {
  final flat = <_FlatItem>[];
  for (final section in sections) {
    flat.add(_FlatItem.header(section.title));
    final glyphs = [
      for (final leaf in section.leaves)
        if (leaf case UnicodeCatalogLeaf(:final glyph)) glyph,
    ];
    for (var i = 0; i < glyphs.length; i += spanCount) {
      final end = i + spanCount > glyphs.length ? glyphs.length : i + spanCount;
      flat.add(_FlatItem.row(glyphs.sublist(i, end)));
    }
  }
  return flat;
}

double _extentOf(_FlatItem item) => switch (item) {
  _HeaderItem() => kBenchHeaderExtent,
  _RowItem() => kBenchCellExtent,
};

double _contentExtentFor(List<_FlatItem> flat) {
  var y = 0.0;
  for (final item in flat) {
    y += _extentOf(item);
  }
  return y;
}

double _sectionHeaderOffset(List<_FlatItem> flat, int sectionIndex) {
  var section = 0;
  var y = 0.0;
  for (final item in flat) {
    if (item case _HeaderItem()) {
      if (section == sectionIndex) return y;
      section++;
    }
    y += _extentOf(item);
  }
  return y;
}

// --- Catalog body -----------------------------------------------------------

/// Frozen SuperSliverList catalog body for A/B comparison.
class BaselineSuperSliverCatalog extends StatefulWidget {
  const BaselineSuperSliverCatalog({
    required this.sections,
    required this.scrollController,
    this.spanCount = kBenchSpanCount,
    super.key,
  });

  final List<CatalogSection> sections;
  final ScrollController scrollController;
  final int spanCount;

  @override
  State<BaselineSuperSliverCatalog> createState() =>
      BaselineSuperSliverCatalogState();
}

/// Public state for bench offset helpers.
class BaselineSuperSliverCatalogState extends State<BaselineSuperSliverCatalog> {
  late List<_FlatItem> _flat = _flatten(
    widget.sections,
    spanCount: widget.spanCount,
  );

  /// Flattened header+row list length (bench observability).
  int get flatItemCount => _flat.length;

  /// Content extent of the flat list.
  double get contentExtent => _contentExtentFor(_flat);

  /// Content-y of section [sectionIndex] header.
  double headerOffset(int sectionIndex) =>
      _sectionHeaderOffset(_flat, sectionIndex);

  @override
  void didUpdateWidget(BaselineSuperSliverCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections != widget.sections ||
        oldWidget.spanCount != widget.spanCount) {
      _flat = _flatten(widget.sections, spanCount: widget.spanCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flat = _flat;
    final span = widget.spanCount;
    return BenchmarkTimingWrapper(
      child: CustomScrollView(
        controller: widget.scrollController,
        physics: const ClampingScrollPhysics(),
        slivers: [
          SuperSliverList.builder(
            extentEstimation: (index, _) => switch (index) {
              null => kBenchCellExtent,
              final i when i < 0 || i >= flat.length => kBenchCellExtent,
              final i => _extentOf(flat[i]),
            },
            itemCount: flat.length,
            addAutomaticKeepAlives: false,
            itemBuilder: (context, index) {
              return switch (flat[index]) {
                _HeaderItem(:final title) => SizedBox(
                  height: kBenchHeaderExtent,
                  width: double.infinity,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                _RowItem(:final glyphs) => SizedBox(
                  height: kBenchCellExtent,
                  child: Row(
                    children: [
                      for (final glyph in glyphs)
                        BaselineGlyphCell(
                          glyph: glyph,
                          extent: kBenchCellExtent,
                        ),
                      if (glyphs.length < span)
                        Spacer(flex: span - glyphs.length),
                    ],
                  ),
                ),
              };
            },
          ),
        ],
      ),
    );
  }
}
