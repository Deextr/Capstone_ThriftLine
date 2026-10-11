import 'package:intl/intl.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 0,
);

String formatCurrency(double amount) => _currencyFormat.format(amount);

String formatCentavos(int centavos) => formatCurrency(centavos / 100);

final _adminReportMoneyFormat = NumberFormat.currency(
  locale: 'en_PH',
  symbol: '₱',
  decimalDigits: 2,
);

/// Orders/payments report detail cells (always real ₱, not mojibake from legacy SQL).
String formatAdminReportPesoAmount(String raw) {
  var s = raw.trim();
  if (s.isEmpty || s == '—') return raw;
  s = s.replaceAll('\u20B1', '').replaceAll('â‚±', '').replaceAll('₱', '').trim();
  s = s.replaceAll(',', '');
  final amount = double.tryParse(s);
  if (amount == null) return raw;
  return _adminReportMoneyFormat.format(amount);
}

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

/// Admin tables: always include year (e.g. Oct 7, 2026).
String formatAdminTableDate(DateTime dateTime) => formatFullDate(dateTime);

/// Admin tables when time matters (e.g. audit logs).
String formatAdminTableDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${DateFormat('MMM d, yyyy').format(local)} · '
      '${DateFormat('h:mm a').format(local)}';
}

/// Marketplace admin reports (Manila): OCT 3, 2026 6:35 AM
String formatAdminReportDateTime(DateTime dateTime) {
  final pht = toPhilippinesTime(dateTime);
  final month = DateFormat('MMM').format(pht).toUpperCase();
  return '$month ${DateFormat('d, yyyy h:mm a').format(pht)}';
}

/// Philippine Time (UTC+8) for admin order tables (Davao / national scope).
DateTime toPhilippinesTime(DateTime dateTime) =>
    dateTime.toUtc().add(const Duration(hours: 8));

String formatAdminPhilippinesDate(DateTime dateTime) =>
    DateFormat('MMM d, yyyy').format(toPhilippinesTime(dateTime));

String formatAdminPhilippinesTime(DateTime dateTime) =>
    DateFormat('h:mm a').format(toPhilippinesTime(dateTime));

String formatTimeOfDay(DateTime dateTime) =>
    DateFormat('h:mm a').format(dateTime.toLocal());

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
