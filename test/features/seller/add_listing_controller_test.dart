// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, StorageException;
import 'package:thriftline/core/routes/route_names.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/features/auth/domain/auth_user.dart';
import 'package:thriftline/features/seller/controllers/add_listing_controller.dart';
import 'package:thriftline/features/seller/domain/product_image_storage.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/providers/auth_provider.dart';

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  _FakeAuthProvider(this._user);

  final AuthUser? _user;

  @override
  AuthUser? get user => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImagePicker extends ImagePicker {
  XFile? nextPickedFile;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    return nextPickedFile;
  }
}

class _FakeListingPublishGateway implements ListingPublishGateway {
  List<CategoryItem> categoriesToReturn = const [
    CategoryItem(id: 'cat-1', name: 'Tops'),
  ];
  String? barangayToReturn = 'Apopong';
  Map<String, dynamic> limitStatusToReturn = const {
    'ok': true,
    'can_publish': true,
    'active_count': 0,
    'limit': 15,
  };

  Object? uploadError;
  Object? insertProductError;
  Object? insertProductImagesError;
  Completer<void>? uploadBlocker;

  final List<String> uploadedPaths = [];
  final List<List<String>> removedPathBatches = [];
  final List<Map<String, dynamic>> insertedProducts = [];
  final List<List<Map<String, dynamic>>> insertedProductImageBatches = [];
  final List<String> deletedDraftProductIds = [];

  @override
  Future<List<CategoryItem>> fetchActiveCategories() async =>
      categoriesToReturn;

  @override
  Future<String?> fetchSellerBarangay(String sellerId) async =>
      barangayToReturn;

  @override
  Future<dynamic> fetchListingLimitStatus() async => limitStatusToReturn;

  @override
  Future<String> uploadProductImage({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (uploadBlocker != null) {
      await uploadBlocker!.future;
    }
    if (uploadError != null) {
      throw uploadError!;
    }
    uploadedPaths.add(path);
    return 'https://example.supabase.co/storage/v1/object/public/$productImagesBucket/$path';
  }

  @override
  Future<void> removeProductImages(List<String> paths) async {
    removedPathBatches.add(List<String>.from(paths));
  }

  @override
  Future<void> insertProduct(Map<String, dynamic> data) async {
    if (insertProductError != null) {
      throw insertProductError!;
    }
    insertedProducts.add(Map<String, dynamic>.from(data));
  }

  @override
  Future<dynamic> ensureProductAuction({
    required String productId,
    required double startingPrice,
    required double minimumIncrement,
    required int durationDays,
  }) async {
    return {'ok': true};
  }

  @override
  Future<void> insertProductImages(List<Map<String, dynamic>> rows) async {
    if (insertProductImagesError != null) {
      throw insertProductImagesError!;
    }
    insertedProductImageBatches.add(List<Map<String, dynamic>>.from(rows));
  }

  @override
  Future<void> deleteDraftProduct({
    required String productId,
    required String sellerId,
  }) async {
    deletedDraftProductIds.add(productId);
    insertedProducts.removeWhere((p) => p['product_id'] == productId);
  }
}

/// Valid 1x1 PNG bytes for widget tests.
final Uint8List _validPngBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82,
]);

void _fillValidForm(AddListingController controller) {
  controller.images = [SelectedImage(bytes: _validPngBytes, name: 'shirt.png')];
  controller.nameCtrl.text = 'Vintage Denim Jacket';
  controller.descCtrl.text =
      'Authentic vintage denim jacket in great condition with no stains.';
  controller.selectCategory('cat-1', 'Tops');
  controller.selectCondition(ProductCondition.good);
  controller.selectFormat(ListingFormat.fixedPrice);
  controller.priceCtrl.text = '450';
  controller.stockCtrl.text = '1';
  controller.shippingFeeCtrl.text = '80';
}

Widget _buildTestHarness({
  required AddListingController controller,
  List<String>? navigatedRoutes,
}) {
  final router = GoRouter(
    initialLocation: '/add',
    routes: [
      GoRoute(
        path: '/add',
        builder: (context, state) => ChangeNotifierProvider.value(
          value: controller,
          child: Scaffold(
            body: Builder(
              builder: (ctx) {
                final c = ctx.watch<AddListingController>();
                return Column(
                  children: [
                    Text('Loading:${c.isLoading}'),
                    Text('Status:${c.uploadStatusMessage}'),
                    ElevatedButton(
                      onPressed: () => c.postListing(ctx),
                      child: const Text('Publish listing'),
                    ),
                    ElevatedButton(
                      onPressed: () => c.pickImage(0, ctx),
                      child: const Text('Pick image'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
      GoRoute(
        path: RouteNames.sellerHome,
        builder: (context, state) {
          navigatedRoutes?.add(state.uri.toString());
          return const Scaffold(body: Text('Seller Listings Destination'));
        },
      ),
    ],
  );

  return MaterialApp.router(routerConfig: router);
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Property 7 — Condition mapping is bijective and complete
  // ─────────────────────────────────────────────────────────────────────────
  group('Property 7: conditionToDbString — bijective and complete', () {
    test('returns a non-empty string for every ProductCondition value', () {
      for (final condition in ProductCondition.values) {
        final result = conditionToDbString(condition);
        expect(
          result,
          isNotEmpty,
          reason: '$condition mapped to an empty string',
        );
      }
    });

    test(
      'all results are distinct (no two enum values map to the same string)',
      () {
        final results = ProductCondition.values
            .map(conditionToDbString)
            .toList();
        final uniqueResults = results.toSet();
        expect(uniqueResults.length, equals(results.length));
      },
    );

    test('maps to the exact expected DB values', () {
      expect(conditionToDbString(ProductCondition.newWithTags), equals('new'));
      expect(conditionToDbString(ProductCondition.likeNew), equals('like_new'));
      expect(conditionToDbString(ProductCondition.good), equals('good'));
      expect(conditionToDbString(ProductCondition.fair), equals('fair'));
      expect(conditionToDbString(ProductCondition.poor), equals('poor'));
    });

    test('covers all five ProductCondition cases', () {
      expect(ProductCondition.values, hasLength(5));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Property 8 — Listing format mapping is bijective and complete
  // ─────────────────────────────────────────────────────────────────────────
  group('Property 8: formatToDbString — bijective and complete', () {
    test('returns a non-empty string for every ListingFormat value', () {
      for (final format in ListingFormat.values) {
        final result = formatToDbString(format);
        expect(result, isNotEmpty);
      }
    });

    test(
      'all results are distinct (no two enum values map to the same string)',
      () {
        final results = ListingFormat.values.map(formatToDbString).toList();
        final uniqueResults = results.toSet();
        expect(uniqueResults.length, equals(results.length));
      },
    );

    test('maps to the exact expected DB values', () {
      expect(formatToDbString(ListingFormat.fixedPrice), equals('fixed_price'));
      expect(formatToDbString(ListingFormat.auction), equals('auction'));
    });

    test('covers all two ListingFormat cases', () {
      expect(ListingFormat.values, hasLength(2));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Seller Listing Publishing Scenarios (1–10)
  // ─────────────────────────────────────────────────────────────────────────
  group('Seller Listing Publishing Error Handling & Data Integrity', () {
    late _FakeAuthProvider auth;
    late _FakeImagePicker imagePicker;
    late _FakeListingPublishGateway gateway;
    late AddListingController controller;

    setUp(() {
      auth = _FakeAuthProvider(
        const AuthUser(
          id: 'seller-123',
          email: 'seller@thriftline.test',
          name: 'Seller One',
          username: 'seller123',
          role: UserRole.seller,
          avatarUrl: '',
          location: 'General Santos City',
          isVerified: true,
        ),
      );
      imagePicker = _FakeImagePicker();
      gateway = _FakeListingPublishGateway();
      controller = AddListingController(
        supabase: SupabaseService(),
        auth: auth,
        imagePicker: imagePicker,
        gateway: gateway,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    testWidgets(
      'Scenario 1: Seller successfully publishes a listing with valid images',
      (tester) async {
        final navigatedRoutes = <String>[];
        _fillValidForm(controller);

        await tester.pumpWidget(
          _buildTestHarness(
            controller: controller,
            navigatedRoutes: navigatedRoutes,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Publish listing'));
        await tester.pumpAndSettle();

        expect(gateway.uploadedPaths, hasLength(1));
        expect(gateway.insertedProducts, hasLength(1));
        expect(gateway.insertedProducts.single['name'], 'Vintage Denim Jacket');
        expect(gateway.insertedProductImageBatches, hasLength(1));
        expect(
          find.text('Your listing has been published successfully!'),
          findsOneWidget,
        );
        expect(find.text('Seller Listings Destination'), findsOneWidget);
        expect(navigatedRoutes, isNotEmpty);
      },
    );

    testWidgets(
      'Scenario 2: Seller attempts to publish without completing required fields',
      (tester) async {
        await tester.pumpWidget(_buildTestHarness(controller: controller));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Publish listing'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Please complete all required product details before publishing.',
          ),
          findsOneWidget,
        );
        expect(controller.fieldErrors['images'], isNotNull);
        expect(controller.fieldErrors['name'], isNotNull);
        expect(controller.fieldErrors['description'], isNotNull);
        expect(controller.fieldErrors['category'], isNotNull);
        expect(controller.fieldErrors['condition'], isNotNull);
        expect(controller.fieldErrors['price'], isNotNull);
        expect(gateway.uploadedPaths, isEmpty);
        expect(gateway.insertedProducts, isEmpty);
        // Should not open an unnecessary modal dialog for inline validation errors
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'Scenario 3: Image upload fails — shows friendly dialog, does not insert product, preserves form',
      (tester) async {
        _fillValidForm(controller);
        gateway.uploadError = const StorageException(
          'Internal Server Error',
          statusCode: '500',
        );

        await tester.pumpWidget(_buildTestHarness(controller: controller));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Publish listing'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Couldn\'t upload photos'), findsOneWidget);
        expect(
          find.text(
            'We couldn\'t upload your product images. Please check your internet connection and try again.',
          ),
          findsOneWidget,
        );
        expect(find.text('Try Again'), findsOneWidget);
        expect(find.text('Go Back'), findsOneWidget);

        // No product inserted and form data preserved
        expect(gateway.insertedProducts, isEmpty);
        expect(controller.nameCtrl.text, 'Vintage Denim Jacket');
        expect(controller.images, hasLength(1));

        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      },
    );

    testWidgets(
      'Scenario 4: Seller loses internet connectivity during publication',
      (tester) async {
        _fillValidForm(controller);
        gateway.insertProductError = Exception(
          'SocketException: Failed host lookup: supabase.co',
        );

        await tester.pumpWidget(_buildTestHarness(controller: controller));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Publish listing'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('No internet connection'), findsOneWidget);
        expect(
          find.text(
            'You\'re currently offline. Please reconnect to the internet and try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('SocketException'), findsNothing);
        // Uploaded image was cleaned up when DB insert failed due to network loss
        expect(gateway.removedPathBatches, hasLength(1));
        // Seller's entered product information is preserved
        expect(controller.nameCtrl.text, 'Vintage Denim Jacket');
        expect(controller.priceCtrl.text, '450');

        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('Scenario 5: Seller selects an unsupported image format', (
      tester,
    ) async {
      imagePicker.nextPickedFile = XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4]),
        name: 'unsupported_photo.heic',
      );

      await tester.pumpWidget(_buildTestHarness(controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pick image'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Unsupported image format'), findsOneWidget);
      expect(
        find.textContaining(
          'This image format isn\'t supported. Please select another image.',
        ),
        findsOneWidget,
      );
      expect(find.text('Okay'), findsOneWidget);
      expect(controller.images, isEmpty);

      await tester.tap(find.text('Okay'));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'Scenario 6: Seller selects images that exceed the allowed size',
      (tester) async {
        final oversizedBytes = Uint8List(kProductListingImageMaxBytes + 100);
        imagePicker.nextPickedFile = XFile.fromData(
          oversizedBytes,
          path: 'huge_photo.jpg',
          name: 'huge_photo.jpg',
        );

        await tester.pumpWidget(_buildTestHarness(controller: controller));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Pick image'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Image too large'), findsOneWidget);
        expect(
          find.textContaining(
            'One or more images are too large. Please choose smaller images.',
          ),
          findsOneWidget,
        );
        expect(find.text('Okay'), findsOneWidget);
        expect(controller.images, isEmpty);

        await tester.tap(find.text('Okay'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Scenario 7: Database insertion or listing publication fails — rolls back draft and shows friendly dialog',
      (tester) async {
        _fillValidForm(controller);
        gateway.insertProductImagesError = const PostgrestException(
          message: 'insert on table "product_images" failed',
          code: '500',
        );

        await tester.pumpWidget(_buildTestHarness(controller: controller));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Publish listing'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Couldn\'t publish listing'), findsOneWidget);
        expect(
          find.text(
            'We couldn\'t publish your listing right now. Please try again.',
          ),
          findsOneWidget,
        );
        // No raw DB or Postgrest message shown
        expect(find.textContaining('product_images'), findsNothing);
        expect(find.textContaining('PostgrestException'), findsNothing);

        // Draft product row and uploaded storage objects were rolled back
        expect(gateway.deletedDraftProductIds, hasLength(1));
        expect(gateway.insertedProducts, isEmpty);
        expect(gateway.removedPathBatches, hasLength(1));

        // Seller's form data is intact
        expect(controller.nameCtrl.text, 'Vintage Denim Jacket');

        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Scenario 8: Seller taps the Publish button multiple times — prevents duplicate submissions',
      (tester) async {
        _fillValidForm(controller);
        gateway.uploadBlocker = Completer<void>();

        await tester.pumpWidget(_buildTestHarness(controller: controller));
        await tester.pumpAndSettle();

        // Tap Publish multiple times while upload is in-flight
        await tester.tap(find.text('Publish listing'));
        await tester.pump();
        expect(controller.isLoading, isTrue);

        await tester.tap(find.text('Publish listing'));
        await tester.tap(find.text('Publish listing'));
        await tester.pump();

        // Unblock the upload and complete
        gateway.uploadBlocker!.complete();
        await tester.pumpAndSettle();

        expect(gateway.uploadedPaths, hasLength(1));
        expect(gateway.insertedProducts, hasLength(1));
      },
    );

    testWidgets(
      'Scenario 9: Seller retries after an unsuccessful publication via Try Again button',
      (tester) async {
        _fillValidForm(controller);
        gateway.uploadError = const StorageException(
          'Temporary storage glitch',
          statusCode: '503',
        );

        await tester.pumpWidget(_buildTestHarness(controller: controller));
        await tester.pumpAndSettle();

        // First attempt fails
        await tester.tap(find.text('Publish listing'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'We couldn\'t upload your product images. Please check your internet connection and try again.',
          ),
          findsOneWidget,
        );

        // Upload issue resolves; seller taps Try Again directly in the dialog
        gateway.uploadError = null;
        await tester.tap(find.text('Try Again'));
        await tester.pumpAndSettle();

        expect(gateway.uploadedPaths, hasLength(1));
        expect(gateway.insertedProducts, hasLength(1));
        expect(
          find.text('Your listing has been published successfully!'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Scenario 10: Seller successfully publishes after correcting a validation or image issue',
      (tester) async {
        // Start with an invalid image format in the controller and missing price
        controller.images = [
          SelectedImage(
            bytes: Uint8List.fromList([1, 2, 3]),
            name: 'bad_format.bmp',
          ),
        ];
        controller.nameCtrl.text = 'Corduroy Tote Bag';
        controller.descCtrl.text =
            'Handmade corduroy tote bag with inner zipper pocket.';
        controller.selectCategory('cat-1', 'Tops');
        controller.selectCondition(ProductCondition.likeNew);
        controller.priceCtrl.text = '';

        await tester.pumpWidget(_buildTestHarness(controller: controller));
        await tester.pumpAndSettle();

        // 1st attempt: blocked by unsupported image format
        await tester.tap(find.text('Publish listing'));
        await tester.pumpAndSettle();
        expect(find.text('Unsupported image format'), findsOneWidget);
        await tester.tap(find.text('Okay'));
        await tester.pumpAndSettle();

        // Seller replaces image with a valid PNG, but price is still missing
        controller.images = [
          SelectedImage(bytes: _validPngBytes, name: 'tote.png'),
        ];
        await tester.tap(find.text('Publish listing'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Please complete all required product details before publishing.',
          ),
          findsOneWidget,
        );
        expect(controller.fieldErrors['price'], isNotNull);

        // Seller enters valid price and publishes
        controller.priceCtrl.text = '320';
        await tester.tap(find.text('Publish listing'));
        await tester.pumpAndSettle();

        expect(gateway.insertedProducts, hasLength(1));
        expect(gateway.insertedProducts.single['name'], 'Corduroy Tote Bag');
        expect(
          find.text('Your listing has been published successfully!'),
          findsOneWidget,
        );
      },
    );
  });
}
