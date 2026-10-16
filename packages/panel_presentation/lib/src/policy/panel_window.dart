import 'package:meta/meta.dart';

/// The adaptive **window class** of the host window: how much room the panel
/// has to choose a presentation.
///
/// The breakpoints are the Material window size classes: compact below 600
/// logical pixels of width, medium below 840, expanded from 840.
enum PanelWindowClass {
  /// A phone-width window.
  compact,

  /// A tablet-width or narrowed desktop window.
  medium,

  /// A window wide enough to dock a section beside the content.
  expanded;

  /// The class of a window [width] logical pixels wide.
  static PanelWindowClass fromWidth(double width) {
    if (width >= 840) return expanded;
    if (width >= 600) return medium;
    return compact;
  }

  /// Whether the window is wide enough to dock the panel.
  bool get isWide => this == expanded;
}

/// The size of the host window in logical pixels, with its [windowClass].
///
/// Fed by the host (usually from `MediaQuery.sizeOf`) to the presentation
/// controller; the policy reads the class to pick a kind and the height to
/// size a popup.
@immutable
final class PanelWindow {
  /// A window [width] by [height] logical pixels.
  const PanelWindow({required this.width, required this.height});

  /// The width in logical pixels.
  final double width;

  /// The height in logical pixels.
  final double height;

  /// The class of [width].
  PanelWindowClass get windowClass => PanelWindowClass.fromWidth(width);

  @override
  bool operator ==(Object other) =>
      other is PanelWindow && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PanelWindow(${width}x$height)';
}
