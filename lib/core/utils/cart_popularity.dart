/// Compact cart-add count for product cards. Hides zero.
///
/// Ranges: `1`–`4` exact, then `5+`, `10+`, `50+`.
String? formatCartPopularity(int count) {
  if (count <= 0) return null;
  if (count < 5) return '$count';
  if (count < 10) return '5+';
  if (count < 50) return '10+';
  return '50+';
}
