import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/domain/product_image_storage.dart';

void main() {
  const sellerId = '11111111-1111-1111-1111-111111111111';
  const otherSeller = '22222222-2222-2222-2222-222222222222';

  group('productImageStoragePathFromPublicUrl', () {
    test('parses product-images public URLs for the owning seller', () {
      final url =
          'https://example.supabase.co/storage/v1/object/public/product-images/'
          '$sellerId/prod-1/0.jpg';
      expect(
        productImageStoragePathFromPublicUrl(url, sellerId: sellerId),
        '$sellerId/prod-1/0.jpg',
      );
    });

    test('rejects URLs outside the seller folder', () {
      final url =
          'https://example.supabase.co/storage/v1/object/public/product-images/'
          '$otherSeller/prod-1/0.jpg';
      expect(
        productImageStoragePathFromPublicUrl(url, sellerId: sellerId),
        isNull,
      );
    });

    test('rejects unrelated buckets', () {
      expect(
        productImageStoragePathFromPublicUrl(
          'https://example.supabase.co/storage/v1/object/public/avatars/x.jpg',
          sellerId: sellerId,
        ),
        isNull,
      );
    });
  });

  group('productImageStoragePathsForSeller', () {
    test('collects only trusted paths', () {
      final paths = productImageStoragePathsForSeller(
        sellerId: sellerId,
        imageUrls: [
          'https://x.co/storage/v1/object/public/product-images/$sellerId/p/a.jpg',
          'https://x.co/storage/v1/object/public/product-images/$otherSeller/p/b.jpg',
          null,
        ],
      );
      expect(paths, ['$sellerId/p/a.jpg']);
    });
  });
}
