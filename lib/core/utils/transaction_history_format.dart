import 'package:intl/intl.dart';

import 'formatters.dart';

/// Section header for chronologically grouped transaction lists (e.g. Today, Oct 12).
String transactionHistoryDateGroupHeader(DateTime dateTime, {DateTime? now}) {
  final local = dateTime.toLocal();
  final clock = (now ?? DateTime.now()).toLocal();
  final today = DateTime(clock.year, clock.month, clock.day);
  final day = DateTime(local.year, local.month, local.day);
  final yesterday = today.subtract(const Duration(days: 1));

  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  if (local.year == clock.year) {
    return DateFormat('MMMM d').format(local);
  }
  return DateFormat('MMMM d, yyyy').format(local);
}

/// Time shown on list rows when the day is already grouped in a header.
String formatTransactionHistoryListTime(DateTime dateTime) =>
    formatTimeOfDay(dateTime);

/// Order reference for list and detail rows.
String formatTransactionOrderReference(String orderNumber) {
  final trimmed = orderNumber.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.startsWith('#') ? trimmed : '#$trimmed';
}

/// Only allow network URLs suitable for product thumbnails.
String? sanitizeTransactionProductImageUrl(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  return uri.toString();
}
