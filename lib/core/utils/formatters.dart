import 'package:intl/intl.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 0,
);

String formatCurrency(double amount) => _currencyFormat.format(amount);

String formatCentavos(int centavos) => formatCurrency(centavos / 100);

/// First name plus last initial for list views. Full names stay on details.
String shortPersonName(String? name, {String fallback = 'Buyer'}) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return fallback;
  if (parts.length == 1) return parts.first;
  final last = parts.last;
  return '${parts.first} ${last[0].toUpperCase()}.';
}

String formatCompactDate(DateTime dateTime, {DateTime? now}) {
  final local = dateTime.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    return 'today';
  }
  return DateFormat('MMM d').format(local);
}

String formatFullDate(DateTime dateTime) =>
    DateFormat('MMM d, yyyy').format(dateTime.toLocal());

String formatRelativeTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d').format(dateTime);
}

String formatPaymentDeadline(DateTime due, {DateTime? now}) {
  final clock = DateFormat('MMM d, h:mm a').format(due.toLocal());
  final left = due.difference(now ?? DateTime.now());
  if (left.isNegative || left.inSeconds <= 0) {
    return 'Payment window ended $clock';
  }
  final hours = left.inHours;
  final minutes = left.inMinutes.remainder(60);
  if (hours > 0) return 'Pay by $clock ($hours h ${minutes} m left)';
  final seconds = left.inSeconds.remainder(60);
  if (minutes > 0) return 'Pay by $clock ($minutes m ${seconds} s left)';
  return 'Pay by $clock (${left.inSeconds} s left)';
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

/// Product-card auction label, e.g. `21h 22m`.
String formatReadableCountdown(Duration remaining) {
  if (remaining.isNegative || remaining.inSeconds <= 0) return 'Ended';
  final days = remaining.inDays;
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes.remainder(60);
  if (days > 0) return '${days}d ${hours % 24}h ${minutes}m';
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m';
  return '${remaining.inSeconds}s';
}
