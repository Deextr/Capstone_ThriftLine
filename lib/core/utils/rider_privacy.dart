String maskRiderName(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'Rider';
  if (parts.length == 1) return parts.first;
  final last = parts.last;
  final initial = last.isEmpty ? '' : '${last[0].toUpperCase()}.';
  return '${parts.first} $initial'.trim();
}

String maskRiderPhone(String? phone, {bool sellerView = false}) {
  final digits = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 4) return sellerView ? (phone ?? '') : '09••• ••• ••••';
  if (sellerView) {
    if (digits.length >= 7) {
      return '${digits.substring(0, 4)}••••${digits.substring(digits.length - 3)}';
    }
    return phone ?? '';
  }
  final last = digits.substring(digits.length - 4);
  return '09••• ••• $last';
}

String formatInspectionRemaining(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return '—';
  final remaining = expiresAt.difference(now ?? DateTime.now());
  if (remaining.isNegative || remaining.inSeconds <= 0) {
    return 'Inspection window ended';
  }
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}
