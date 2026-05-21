import 'package:intl/intl.dart';

class DateFormatter {
  const DateFormatter._();

  static String uploadDate(DateTime value) {
    return DateFormat('MMM d, h:mm a').format(value);
  }

  /// Compact relative time for list rows: "Just now", "5m ago", "3h ago",
  /// "Yesterday", "4d ago", then an absolute "MMM d" beyond a week.
  static String relativeShort(DateTime value) {
    final diff = DateTime.now().difference(value);
    if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(value);
  }
}
