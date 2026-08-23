import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Horizontal spring-shake driven by [hits] (stiffness 600, 10 logical-px kick).
class CapHitShake extends StatefulWidget {
  /// Shakes [child] each time [hits] increments.
  const CapHitShake({
    required this.hits,
    required this.child,
    this.onHit,
    super.key,
  });

  /// Generation counter — any increment triggers a shake.
  final ValueListenable<int> hits;

  /// Content to translate.
  final Widget child;

  /// Optional extra reaction (haptic). Called when the spring starts.
  final Future<void> Function()? onHit;

  @override
  State<CapHitShake> createState() => _CapHitShakeState();
}

class _CapHitShakeState extends State<CapHitShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 600,
    damping: 24.5,
  );

  @override
  void initState() {
    super.initState();
    _c = AnimationController.unbounded(vsync: this);
    widget.hits.addListener(_onHit);
  }

  @override
  void didUpdateWidget(CapHitShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.hits, widget.hits)) {
      oldWidget.hits.removeListener(_onHit);
      widget.hits.addListener(_onHit);
    }
  }

  @override
  void dispose() {
    widget.hits.removeListener(_onHit);
    _c.dispose();
    super.dispose();
  }

  void _onHit() {
    final onHit = widget.onHit;
    if (onHit != null) unawaited(onHit());
    _c
      ..value = 0
      ..animateWith(SpringSimulation(_spring, 0, 0, -250));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, child) =>
        Transform.translate(offset: Offset(_c.value, 0), child: child),
    child: widget.child,
  );
}
