import 'package:attach_sheet/src/page/attach_page_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The identity of an **attach page** within the sheet.
extension type const AttachPageId(String value) implements String {
  /// The stock Gallery page.
  static const AttachPageId gallery = AttachPageId('gallery');

  /// The stock Files page.
  static const AttachPageId files = AttachPageId('files');
}

/// What a page does with the sheet.
enum AttachPageKind {
  /// Adds items to the sheet's one attach selection (Gallery, Files); the
  /// panel and send menu work for it.
  selection,

  /// Builds its own content and finishes with a payload the host reads
  /// (location, contact, poll, a bot); it may ask for the main button and
  /// hide the panel.
  host,
}

/// The permission a page needs, as the host sees it.
@immutable
final class AttachPagePermission {
  /// A permission that is [granted] now and asked for by [request].
  const AttachPagePermission({required this.granted, required this.request});

  /// Whether the page has its permission; the tab's badge follows it.
  final ValueListenable<bool> granted;

  /// Asks the platform for the permission.
  final Future<void> Function() request;
}

/// The button a host page shows in place of the tab bar.
@immutable
final class AttachMainButton {
  /// A button labelled [label].
  const AttachMainButton({required this.label, required this.onPressed});

  /// Its label.
  final String label;

  /// Called on a tap.
  final VoidCallback onPressed;
}

/// Builds an attach page's content over its [scope].
typedef AttachPageBuilder =
    Widget Function(BuildContext context, AttachPageScope scope);

/// An **attach page**: one page of the sheet under the page contract.
///
/// Built once the first time its tab is shown and kept, with its state, for
/// the rest of the open. Its content scrolls on `scope.scrollController`
/// so the sheet and the page share one drag.
@immutable
final class AttachPage {
  /// A page.
  const AttachPage({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.kind = AttachPageKind.selection,
    this.permission,
  });

  /// Its identity.
  final AttachPageId id;

  /// Its tab's label.
  final String label;

  /// Its tab's icon.
  final Widget icon;

  /// Builds its content.
  final AttachPageBuilder builder;

  /// What it does with the sheet.
  final AttachPageKind kind;

  /// The permission it needs, if any.
  final AttachPagePermission? permission;
}

/// The pages of one open, in tab order, built by the host from its rights.
@immutable
final class AttachPageRegistry {
  /// [pages] in tab order, opening on [initial] (the first page by
  /// default). Throws an [ArgumentError] for no pages, a repeated id, or an
  /// [initial] that is not among them.
  AttachPageRegistry(Iterable<AttachPage> pages, {AttachPageId? initial})
    : pages = List.unmodifiable(pages),
      initial = initial ?? _first(pages) {
    if (this.pages.isEmpty) {
      throw ArgumentError.value(pages, 'pages', 'must not be empty');
    }
    final ids = <AttachPageId>{};
    for (final page in this.pages) {
      if (!ids.add(page.id)) {
        throw ArgumentError.value(page.id, 'pages', 'repeats a page id');
      }
    }
    if (!ids.contains(this.initial)) {
      throw ArgumentError.value(initial, 'initial', 'is not a page');
    }
  }

  static AttachPageId _first(Iterable<AttachPage> pages) =>
      pages.isEmpty ? const AttachPageId('') : pages.first.id;

  /// The pages, in tab order.
  final List<AttachPage> pages;

  /// The page the sheet opens on.
  final AttachPageId initial;

  /// The page [id].
  AttachPage operator [](AttachPageId id) =>
      pages.firstWhere((page) => page.id == id);
}
