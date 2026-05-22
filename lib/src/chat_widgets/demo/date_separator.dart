import 'package:flutter/widgets.dart';

/// Day-separator pill for the demo chat.
///
/// One widget for both jobs: the inline divider above the first message of a
/// day, and the floating header pinned to the viewport top.
///
/// Deliberately carries no outer vertical padding. The inline copy and the
/// floating copy are laid out identically, so as the inline divider scrolls up
/// it passes exactly *behind* the floating one — same content, same position —
/// instead of peeking out of a transparent gap above it. Spacing around the
/// pill comes from the neighbouring message bubbles' own padding.
class DateSeparator extends StatelessWidget {
  const DateSeparator({required this.date, super.key});

  /// A date within the day this separator labels.
  final DateTime date;

  @override
  Widget build(BuildContext context) => Center(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE0202124),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(
          _formatDay(date),
          style: const TextStyle(
            color: Color(0xFFE6E6E6),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

const List<String> _months = <String>[
  'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/// Formats [date] as a day label: "Сегодня" / "Вчера" / "5 мая" /
/// "5 мая 2024" (the year is shown only when it differs from the current one).
String _formatDay(DateTime date) {
  final now = DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Сегодня';
  if (diff == 1) return 'Вчера';
  final label = '${date.day} ${_months[date.month - 1]}';
  return date.year == today.year ? label : '$label ${date.year}';
}
