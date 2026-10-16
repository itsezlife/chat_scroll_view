import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// Speaks a message to assistive technology.
///
/// The shell announces panel open and close, page changes and search result
/// counts through this seam, with text from the chrome strings. Tests
/// substitute a recorder.
abstract interface class PanelAnnouncer {
  /// Announces [message] for the view and reading direction at [context].
  void announce(BuildContext context, String message);
}

/// The announcer that uses the platform accessibility service.
final class SemanticsServiceAnnouncer implements PanelAnnouncer {
  /// The platform announcer.
  const SemanticsServiceAnnouncer();

  @override
  void announce(BuildContext context, String message) {
    final view = View.maybeOf(context);
    if (view == null) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        view,
        message,
        Directionality.of(context),
      ),
    );
  }
}
