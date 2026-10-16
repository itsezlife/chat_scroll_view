import 'dart:async';

import 'package:chrome_foundation/src/glass/shader/glass_shaders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';

/// Makes glass shader loading fail with [error], as it does in a unit test
/// whose bundle has no shader assets; [GlassShaders.debugReset] puts the real
/// loader back after the test.
void failGlassShaders(Object error) {
  GlassShaders.loader = () => Future.error(error);
  addTearDown(GlassShaders.debugReset);
}

/// A [testWidgets] for a glass surface that is not about shader loading: the
/// programs never arrive, so the surface stays on the path it starts on (the
/// real loader is slow and then fails here, long after these tests have read
/// what they need).
@isTest
void testGlassWidgets(String description, WidgetTesterCallback body) =>
    testWidgets(description, (tester) async {
      GlassShaders.loader = () => Completer<GlassShaderPrograms>().future;
      addTearDown(GlassShaders.debugReset);
      await body(tester);
    });
