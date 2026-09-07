import 'package:intl/intl.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'en_PH',
  symbol: 'â‚±',
  decimalDigits: 0,
);

String formatCurrency(double amount) => _currencyFormat.format(amount);

String formatRelativeTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(dateTime);
}

String formatCountdown(Duration remaining) {
  if (remaining.isNegative || remaining.inSeconds <= 0) return 'Ended';
  final days = remaining.inDays;
  final hours = (remaining.inHours % 24).toString().padLeft(2, '0');
  final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
  if (days > 0) {
    return '${days}d $hours:$minutes';
  }
  return '$hours:$minutes';
}
