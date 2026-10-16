import 'package:flutter/foundation.dart';

const String productImagesBucket = 'product-images';

/// Object key inside [productImagesBucket], or null if [url] is not ours.
@visibleForTesting
String? productImageStoragePathFromPublicUrl(
  String? url, {
  required String sellerId,
}) {
  if (url == null || url.isEmpty || sellerId.isEmpty) return null;
  final marker = '/object/public/$productImagesBucket/';
  final start = url.indexOf(marker);
  if (start < 0) return null;
  final raw = url.substring(start + marker.length).split('?').first;
  if (raw.isEmpty) return null;
  final path = Uri.decodeComponent(raw);
  if (!path.startsWith('$sellerId/')) return null;
  return path;
}

/// Resolves trusted storage paths from [imageUrls] for [sellerId].
List<String> productImageStoragePathsForSeller({
  required Iterable<String?> imageUrls,
  required String sellerId,
}) {
  final paths = <String>[];
  for (final url in imageUrls) {
    final path = productImageStoragePathFromPublicUrl(url, sellerId: sellerId);
    if (path != null) paths.add(path);
  }
  return paths;
}
