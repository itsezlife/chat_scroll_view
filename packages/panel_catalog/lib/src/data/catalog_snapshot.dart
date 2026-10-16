import 'package:flutter/foundation.dart';
import 'package:panel_catalog/src/model/catalog_section.dart';

/// The immutable contents of one panel surface: its sections in display
/// order.
///
/// A host publishes a snapshot through a `ValueObservable<CatalogSnapshot>`
/// (`content_model`) and the viewport projects the current one. A change of
/// contents is a **new** snapshot, never an edit of the published one, so a
/// reference taken earlier stays valid and a listener always reads a
/// consistent catalog. Several mutations that belong together are published
/// as one snapshot inside the owner's batch, so the viewport relayouts once
/// per logical mutation, not once per leaf.
///
/// Equality is identity: every published snapshot is a different value, and an
/// owner that republishes the same instance does not notify.
///
/// An empty [sections] list is a confirmed empty catalog: the viewport
/// projects zero slots and the content extent collapses to the vertical
/// padding. A separate "loading" state is not modelled here.
@immutable
final class CatalogSnapshot {
  /// Creates a snapshot of [sections], copied into an unmodifiable list.
  CatalogSnapshot(List<CatalogSection> sections)
    : sections = List<CatalogSection>.unmodifiable(sections);

  /// The snapshot with no sections.
  const CatalogSnapshot.empty() : sections = const <CatalogSection>[];

  /// Sections in display order: the first section's header is nearest the
  /// catalog top. Unmodifiable.
  ///
  /// Section ids are unique within one snapshot when hosts key jumps or
  /// chrome by section.
  final List<CatalogSection> sections;
}
