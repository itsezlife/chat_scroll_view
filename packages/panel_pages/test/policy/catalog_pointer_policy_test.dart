/// What a catalog page offers a mouse for taking content out of the library,
/// on a desktop and in a browser.
///
/// **Seam:** [CatalogPointerPolicy] directly; pure.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';

void main() {
  test('a desktop removes packs from their headers and shows the square '
      'badge', () {
    const policy = CatalogPointerPolicy.desktop();
    expect(policy.packHeaderRemoves, isTrue);
    expect(policy.removeBadge, CatalogLeafRemoveBadge.pointer);
  });

  test('a browser crosses no pack header and shows the round badge', () {
    const policy = CatalogPointerPolicy.web();
    expect(policy.packHeaderRemoves, isFalse);
    expect(policy.removeBadge, CatalogLeafRemoveBadge.web);
  });

  test('the running app is a browser only on the web', () {
    expect(
      CatalogPointerPolicy.current,
      kIsWeb
          ? const CatalogPointerPolicy.web()
          : const CatalogPointerPolicy.desktop(),
    );
  });

  test('equal by variant', () {
    expect(
      const CatalogPointerPolicy.desktop(),
      const CatalogPointerPolicy.desktop(),
    );
    expect(
      const CatalogPointerPolicy.desktop(),
      isNot(const CatalogPointerPolicy.web()),
    );
  });
}
