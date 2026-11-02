import 'package:supabase_flutter/supabase_flutter.dart';

const String kListingPublishOfflineMessage =
    'You\'re currently offline. Please reconnect to the internet and try again.';

const String kListingImageUploadFailedMessage =
    'We couldn\'t upload your product images. Please check your internet connection and try again.';

const String kListingPublishFailedMessage =
    'We couldn\'t publish your listing right now. Please try again.';

const String kListingMissingDetailsMessage =
    'Please complete all required product details before publishing.';

const String kListingPublishedSuccessMessage =
    'Your listing has been published successfully!';

bool isPostgrestPermissionDenied(PostgrestException error) {
  final code = error.code?.trim();
  if (code == '42501' || code == '403') return true;
  final message = error.message.toLowerCase();
  return message.contains('permission denied') ||
      message.contains('row-level security') ||
      message.contains('"forbidden"') ||
      message.contains('forbidden');
}

bool isLikelyNetworkError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('socketexception') ||
      text.contains('clientexception') ||
      text.contains('network is unreachable') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('connection closed') ||
      text.contains('connection timed out') ||
      text.contains('timed out') ||
      text.contains('xmlhttprequest error') ||
      text.contains('fetch failed') ||
      text.contains('networkerror') ||
      text.contains('no internet') ||
      text.contains('software caused connection abort');
}

/// User-safe copy for order/purchase list failures (no raw SQL in UI).
String userFacingOrderLoadError(
  Object error, {
  String fallback = 'Unable to load orders. Please try again.',
}) {
  if (error is PostgrestException && isPostgrestPermissionDenied(error)) {
    return 'We couldn\'t load your orders right now. Please try again later.';
  }
  if (isLikelyNetworkError(error)) {
    return 'Unable to load orders. Please check your connection and try again.';
  }
  return fallback;
}

/// User-safe copy for seller listings load failures (no raw SQL in UI).
String userFacingSellerListingsLoadError(
  Object error, {
  String fallback =
      'We couldn\'t load your listings right now. Please try again.',
}) {
  if (isLikelyNetworkError(error)) {
    return kListingPublishOfflineMessage;
  }
  return fallback;
}

bool orderSelectMightNeedShipmentFallback(PostgrestException error) {
  if (!isPostgrestPermissionDenied(error)) return false;
  final message = error.message.toLowerCase();
  return message.contains('shipments');
}

bool isStoragePayloadTooLarge(StorageException error) {
  final code = error.statusCode?.trim();
  if (code == '413') return true;
  final message = error.message.toLowerCase();
  return message.contains('too large') ||
      message.contains('file size') ||
      message.contains('payload') ||
      message.contains('exceeded') ||
      message.contains('maximum allowed size');
}

bool isStorageMimeTypeRejected(StorageException error) {
  final code = error.statusCode?.trim();
  if (code == '415') return true;
  final message = error.message.toLowerCase();
  return message.contains('mime') ||
      message.contains('content type') ||
      message.contains('not allowed') ||
      message.contains('invalid file') ||
      message.contains('unsupported');
}

/// User-safe copy when publishing a seller listing fails (no raw Supabase/SQL).
String userFacingListingPublishError(
  Object error, {
  String fallback = kListingPublishFailedMessage,
}) {
  if (isLikelyNetworkError(error)) {
    return kListingPublishOfflineMessage;
  }
  if (error is StorageException) {
    if (isStoragePayloadTooLarge(error)) {
      return 'One or more images are too large. Please choose smaller images. Each photo must be under 5 MB.';
    }
    if (isStorageMimeTypeRejected(error)) {
      return 'This image format isn\'t supported. Please select another image. Supported formats are JPEG, PNG, and WebP.';
    }
    return kListingImageUploadFailedMessage;
  }
  if (error is PostgrestException) {
    if (isPostgrestPermissionDenied(error)) {
      return 'We couldn\'t publish your listing right now. Please check your seller verification status or sign in again and try again.';
    }
    final message = error.message.toLowerCase();
    if (message.contains('products_description_len') ||
        message.contains('description')) {
      return 'We couldn\'t publish your listing right now. Please check your product description (20 to 2,000 characters) and try again.';
    }
  }
  final text = error.toString();
  if (text.contains('auction_setup_failed')) {
    return 'We couldn\'t publish your listing right now. We couldn\'t set up the auction for this item—please check your auction settings and try again.';
  }
  return fallback;
}

/// Maps upload failures during publish (more specific than generic publish errors).
String userFacingListingImageUploadError(Object error) {
  if (isLikelyNetworkError(error)) {
    return kListingPublishOfflineMessage;
  }
  if (error is StorageException) {
    if (isStoragePayloadTooLarge(error) || isStorageMimeTypeRejected(error)) {
      return userFacingListingPublishError(error);
    }
    return kListingImageUploadFailedMessage;
  }
  return kListingImageUploadFailedMessage;
}
