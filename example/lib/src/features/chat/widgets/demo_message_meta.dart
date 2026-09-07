import 'package:flutter/material.dart';

/// Time (+ optional “edited” + delivery ticks) for the change-transition meta
/// slot. [editedOpacity] is visual only — when [edited] is true the label
/// always occupies layout width so the bubble stays final during morph.
class DemoMessageMeta extends StatelessWidget {
  /// Creates the demo meta row.
  const DemoMessageMeta({
    required this.createdAt,
    required this.color,
    required this.showStatus,
    required this.edited,
    this.editedOpacity = 1,
    super.key,
  });

  /// Timestamp for the time label.
  final DateTime createdAt;

  /// Meta color.
  final Color color;

  /// When true, show outgoing delivery ticks.
  final bool showStatus;

  /// When true, show the edited label (subject to [editedOpacity]).
  final bool edited;

  /// Opacity of the “edited” prefix (0→1 during edited-enter).
  final double editedOpacity;

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(createdAt);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (edited) ...<Widget>[
          Opacity(
            opacity: editedOpacity.clamp(0.0, 1.0),
            child: Text(
              'edited',
              style: TextStyle(color: color, fontSize: 11, height: 1),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(time, style: TextStyle(color: color, fontSize: 11, height: 1)),
        if (showStatus) ...<Widget>[
          const SizedBox(width: 3),
          Icon(Icons.done_all, size: 14, color: color),
        ],
      ],
    );
  }
}
