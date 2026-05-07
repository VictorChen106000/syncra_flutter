import 'package:intl/intl.dart';

class DateFormatter {
  const DateFormatter._();

  static String uploadDate(DateTime value) {
    return DateFormat('MMM d, h:mm a').format(value);
  }
}
