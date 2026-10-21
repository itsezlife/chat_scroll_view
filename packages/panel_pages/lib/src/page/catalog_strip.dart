import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart';
import 'package:meta/meta.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// One section of the catalogue, as the page's top strip sees it.
@immutable
final class CatalogStripEntry {
  /// The entry for [collection], shown as section [sectionId].
  const CatalogStripEntry({required this.sectionId, required this.collection});

  /// Id of the section, the key of a jump to it.
  final String sectionId;

  /// The collection the section shows.
  final Collection collection;

  @override
  bool operator ==(Object other) =>
      other is CatalogStripEntry &&
      other.sectionId == sectionId &&
      other.collection == collection;

  @override
  int get hashCode => Object.hash(sectionId, collection);

  @override
  String toString() => 'CatalogStripEntry($sectionId)';
}

/// What a page's top strip may use of the page: the sections to show and the
/// jump to one.
///
/// The strip is the page's own widget, built by the policy. This handle is its
/// whole connection to the page, so it reaches neither the controller nor the
/// viewport.
abstract interface class CatalogStripHandle {
  /// The sections of the catalogue being browsed, in display order.
  ///
  /// Replaced whole on every change of the catalogue.
  ValueListenable<List<CatalogStripEntry>> get entries;

  /// The scroll events of the catalogue, for a strip that follows its scroll.
  ///
  /// `PanelCatalogCurrentSectionChanged` says which section the user is in.
  Stream<PanelCatalogScrollEvent> get scrollEvents;

  /// The id of the section the catalogue is in now, or null before it has laid
  /// out or while it shows no section.
  ///
  /// For a strip that mounts after the catalogue did and has missed the
  /// event that said it.
  String? get currentSectionId;

  /// Scrolls to the header of section [sectionId]; completes when the motion
  /// ends. Does nothing for an id the catalogue does not hold.
  Future<void> jumpToSection(String sectionId);
}
