import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// Temporary debug logger for emoji / keyboard-slot wiring.
///
/// Prefer structured [PanelCatalogDevLog] loggers for catalog audit:
///
/// | Filter name            | Source                          |
/// | ---------------------- | ------------------------------- |
/// | `PanelCatalogLayout`   | slot projection, extent, window |
/// | `PanelCatalogBinding`  | sync window, readiness counts   |
/// | `PanelCatalogScroll`   | section jump, offset            |
/// | `PanelCatalogPaint`    | placeholder vs content counts   |
/// | `KeyboardPanel`        | emoji page, data-source, search |
///
/// Enabled in debug builds by default ([kPanelCatalogDevLog]). Silence with
/// `--dart-define=PANEL_CATALOG_DEV_LOG=false`.
void chatChromeLog(String message) {
  if (!kDebugMode) return;
  dev.log(message, name: 'chat_chrome');
}
