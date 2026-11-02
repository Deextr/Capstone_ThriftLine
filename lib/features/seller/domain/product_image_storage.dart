import 'package:flutter/foundation.dart';

const String productImagesBucket = 'product-images';

/// Matches `storage.buckets.file_size_limit` for [productImagesBucket].
const int kProductListingImageMaxBytes = 5242880;

const String kProductListingImageTooLargeMessage =
    'One or more images are too large. Please choose smaller images. Each photo must be under 5 MB.';

const String kProductListingImageUnsupportedFormatMessage =
    'This image format isn\'t supported. Please select another image. Supported formats are JPEG, PNG, and WebP.';

String? _detectMimeTypeFromMagicBytes(Uint8List? bytes) {
  if (bytes == null || bytes.length < 4) return null;
  // JPEG: FF D8 FF
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  // PNG: 89 50 4E 47
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  // WebP: "RIFF" .... "WEBP"
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// Whether [fileName] (or [bytes] when [fileName] has no extension) is allowed
/// in the `product-images` bucket.
bool isSupportedProductListingImageName(String fileName, {Uint8List? bytes}) {
  final lower = fileName.trim().toLowerCase();
  if (lower.isEmpty) {
    return _detectMimeTypeFromMagicBytes(bytes) != null;
  }
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp')) {
    return true;
  }
  // Android/Web content URIs sometimes omit a file extension on XFile.name.
  if (!lower.contains('.')) {
    return _detectMimeTypeFromMagicBytes(bytes) != null;
  }
  return false;
}

/// User-safe message when a picked file fails local validation, or null if valid.
String? productListingImagePickError({
  required String fileName,
  required int byteLength,
  Uint8List? bytes,
}) {
  if (byteLength <= 0) {
    return kProductListingImageUnsupportedFormatMessage;
  }
  final lower = fileName.trim().toLowerCase();
  final hasExplicitExtension = lower.contains('.');
  if (hasExplicitExtension &&
      !isSupportedProductListingImageName(fileName, bytes: bytes)) {
    return kProductListingImageUnsupportedFormatMessage;
  }
  if (byteLength > kProductListingImageMaxBytes) {
    return kProductListingImageTooLargeMessage;
  }
  if (!isSupportedProductListingImageName(fileName, bytes: bytes)) {
    return kProductListingImageUnsupportedFormatMessage;
  }
  return null;
}

String productListingImageContentType(String fileName, {Uint8List? bytes}) {
  final lower = fileName.trim().toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return _detectMimeTypeFromMagicBytes(bytes) ?? 'image/jpeg';
}

String productListingImageStorageExtension(
  String fileName, {
  Uint8List? bytes,
}) {
  final contentType = productListingImageContentType(fileName, bytes: bytes);
  if (contentType == 'image/png') return '.png';
  if (contentType == 'image/webp') return '.webp';
  return '.jpg';
}

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
