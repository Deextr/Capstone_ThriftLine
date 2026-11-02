import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thriftline/core/utils/supabase_errors.dart';
import 'package:thriftline/features/seller/domain/product_image_storage.dart';

void main() {
  group('productListingImagePickError', () {
    test('rejects unsupported extensions with user-friendly message', () {
      final error = productListingImagePickError(
        fileName: 'photo.heic',
        byteLength: 100,
      );
      expect(error, kProductListingImageUnsupportedFormatMessage);
      expect(
        error,
        contains(
          'This image format isn\'t supported. Please select another image.',
        ),
      );
    });

    test('rejects files over the 5 MB bucket limit', () {
      final error = productListingImagePickError(
        fileName: 'photo.jpg',
        byteLength: kProductListingImageMaxBytes + 1,
      );
      expect(error, kProductListingImageTooLargeMessage);
      expect(
        error,
        contains(
          'One or more images are too large. Please choose smaller images.',
        ),
      );
    });

    test('rejects empty 0-byte files', () {
      expect(
        productListingImagePickError(fileName: 'photo.jpg', byteLength: 0),
        kProductListingImageUnsupportedFormatMessage,
      );
    });

    test('accepts supported sizes and formats (JPEG, PNG, WebP)', () {
      expect(
        productListingImagePickError(fileName: 'photo.jpg', byteLength: 1024),
        isNull,
      );
      expect(
        productListingImagePickError(fileName: 'photo.jpeg', byteLength: 1024),
        isNull,
      );
      expect(
        productListingImagePickError(fileName: 'photo.png', byteLength: 1024),
        isNull,
      );
      expect(
        productListingImagePickError(fileName: 'photo.webp', byteLength: 1024),
        isNull,
      );
    });

    test('accepts extensionless file when magic bytes match JPEG/PNG/WebP', () {
      final jpegHeader = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00]);
      expect(
        productListingImagePickError(
          fileName: 'image_picker_content_uri',
          byteLength: jpegHeader.length,
          bytes: jpegHeader,
        ),
        isNull,
      );
      expect(
        productListingImageContentType(
          'image_picker_content_uri',
          bytes: jpegHeader,
        ),
        'image/jpeg',
      );
      expect(
        productListingImageStorageExtension(
          'image_picker_content_uri',
          bytes: jpegHeader,
        ),
        '.jpg',
      );
    });
  });

  group('userFacingListingPublishError & userFacingListingImageUploadError', () {
    test('maps storage upload failure to user-friendly upload message', () {
      final message = userFacingListingImageUploadError(
        const StorageException('Bucket error', statusCode: '500'),
      );
      expect(
        message,
        'We couldn\'t upload your product images. Please check your internet connection and try again.',
      );
      expect(message, isNot(contains('500')));
      expect(message, isNot(contains('StorageException')));
    });

    test('maps storage payload errors without raw details', () {
      final message = userFacingListingPublishError(
        const StorageException('Payload too large', statusCode: '413'),
      );
      expect(
        message,
        contains(
          'One or more images are too large. Please choose smaller images.',
        ),
      );
      expect(message, isNot(contains('413')));
    });

    test('maps storage MIME errors without raw details', () {
      final message = userFacingListingPublishError(
        const StorageException('mime type not allowed', statusCode: '415'),
      );
      expect(
        message,
        contains(
          'This image format isn\'t supported. Please select another image.',
        ),
      );
      expect(message, isNot(contains('415')));
    });

    test('maps network failures to offline message', () {
      final message = userFacingListingPublishError(
        Exception('SocketException: failed host lookup'),
      );
      expect(
        message,
        'You\'re currently offline. Please reconnect to the internet and try again.',
      );
    });

    test('maps generic database failure to user-friendly publish message', () {
      final message = userFacingListingPublishError(
        const PostgrestException(
          message: 'insert or update on table "products" violates constraint',
          code: '23503',
        ),
      );
      expect(
        message,
        'We couldn\'t publish your listing right now. Please try again.',
      );
      expect(message, isNot(contains('23503')));
      expect(message, isNot(contains('PostgrestException')));
    });

    test('hides auction setup marker', () {
      final message = userFacingListingPublishError(
        Exception('auction_setup_failed'),
      );
      expect(message, contains('auction'));
      expect(message, isNot(contains('auction_setup_failed')));
    });
  });
}
