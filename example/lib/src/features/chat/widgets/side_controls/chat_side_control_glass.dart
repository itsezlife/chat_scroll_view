import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Frosted circle with optional Y-flipped chevron (search-up).
///
/// Optical offset matches Telegram's page-down glass: top pad on the icon,
/// then `scaleY = -1` for search-up. Padding is flipped with the glyph so
/// down sits slightly low and up slightly high — not a mirrored pair with
/// the same post-flip top pad.
class ChatSideControlGlass extends StatelessWidget {
  /// Creates the glass chevron face.
  const ChatSideControlGlass({
    required this.size,
    required this.iconColor,
    required this.glassColor,
    required this.flipIconY,
    this.iconPaddingTop = 2,
    this.iconWidth = 17,
    this.iconHeight = 10,
    super.key,
  });

  /// Circle diameter.
  final double size;

  /// Chevron tint.
  final Color iconColor;

  /// Frosted fill.
  final Color glassColor;

  /// When true, flips the chevron (search-up).
  final bool flipIconY;

  /// Optical top pad for the down chevron (flips with [flipIconY]).
  final double iconPaddingTop;

  /// Asset width.
  final double iconWidth;

  /// Asset height.
  final double iconHeight;

  @override
  Widget build(BuildContext context) {
    // Pad first, then flip — same order as Telegram ImageView padding +
    // `scaleY = -1`, so search-up's optical bias points tip-ward.
    Widget icon = Padding(
      padding: EdgeInsets.only(top: iconPaddingTop),
      child: Image.asset(
        'assets/chat/pagedown.webp',
        width: iconWidth,
        height: iconHeight,
        color: iconColor,
        colorBlendMode: BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stack) => Icon(
          Icons.keyboard_arrow_down_rounded,
          size: iconWidth,
          color: iconColor,
        ),
      ),
    );
    if (flipIconY) {
      icon = Transform.flip(flipY: true, child: icon);
    }
    return ClipOval(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: glassColor.withValues(alpha: 0.72),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
