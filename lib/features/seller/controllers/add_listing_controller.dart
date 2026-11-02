import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, StorageException;
import 'package:uuid/uuid.dart';

import '../../../core/routes/route_names.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/connectivity_timing.dart';
import '../../../core/utils/listing_shipping.dart';
import '../../../core/utils/supabase_errors.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/enums.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/thrift_widgets.dart';
import '../data/listing_limit.dart';
import '../data/seller_listings_refresh.dart';
import '../domain/product_image_storage.dart';
import '../domain/product_listing_validation.dart';
import '../presentation/widgets/listing_publish_error_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Category model (fetched from DB)
// ─────────────────────────────────────────────────────────────────────────────

/// A category row fetched from the `categories` table.
class CategoryItem {
  const CategoryItem({required this.id, required this.name});

  final String id;
  final String name;
}

// ─────────────────────────────────────────────────────────────────────────────
// Local models and enums
// ─────────────────────────────────────────────────────────────────────────────

/// A device image that the seller has selected for this listing.
///
/// [bytes] holds the raw image data — works on both mobile and web.
/// [name] is the original filename, used to derive the MIME type.
class SelectedImage {
  const SelectedImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// The selling format the seller chooses for their listing.
///
/// Maps to the `listing_type_enum` DB values:
///   - [fixedPrice]  → `'fixed_price'`
///   - [auction]     → `'auction'`
enum ListingFormat { fixedPrice, auction }

// ─────────────────────────────────────────────────────────────────────────────
// Backend gateway (allows clean unit/widget testing without live Supabase)
// ─────────────────────────────────────────────────────────────────────────────

/// Abstracts Supabase storage and database operations for [AddListingController].
abstract class ListingPublishGateway {
  Future<List<CategoryItem>> fetchActiveCategories();
  Future<String?> fetchSellerBarangay(String sellerId);
  Future<dynamic> fetchListingLimitStatus();
  Future<String> uploadProductImage({
    required String path,
    required Uint8List bytes,
    required String contentType,
  });
  Future<void> removeProductImages(List<String> paths);
  Future<void> insertProduct(Map<String, dynamic> data);
  Future<dynamic> ensureProductAuction({
    required String productId,
    required double startingPrice,
    required double minimumIncrement,
    required int durationDays,
  });
  Future<void> insertProductImages(List<Map<String, dynamic>> rows);
  Future<void> deleteDraftProduct({
    required String productId,
    required String sellerId,
  });
}

class _SupabaseListingPublishGateway implements ListingPublishGateway {
  const _SupabaseListingPublishGateway(this._supabase);

  final SupabaseService _supabase;

  @override
  Future<List<CategoryItem>> fetchActiveCategories() async {
    final rows = await _supabase.client
        .from('categories')
        .select('category_id, category_name')
        .eq('is_active', true)
        .order('category_name');
    return (rows as List)
        .map(
          (r) => CategoryItem(
            id: r['category_id'] as String,
            name: r['category_name'] as String,
          ),
        )
        .toList();
  }

  @override
  Future<String?> fetchSellerBarangay(String sellerId) async {
    final row = await _supabase.client
        .from('seller_profiles')
        .select('barangay')
        .eq('seller_id', sellerId)
        .maybeSingle();
    return (row?['barangay'] as String?)?.trim();
  }

  @override
  Future<dynamic> fetchListingLimitStatus() {
    return _supabase.client.rpc('seller_listing_limit_status');
  }

  @override
  Future<String> uploadProductImage({
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    await _supabase.client.storage
        .from(productImagesBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return _supabase.client.storage
        .from(productImagesBucket)
        .getPublicUrl(path);
  }

  @override
  Future<void> removeProductImages(List<String> paths) async {
    if (paths.isEmpty) return;
    await _supabase.client.storage.from(productImagesBucket).remove(paths);
  }

  @override
  Future<void> insertProduct(Map<String, dynamic> data) async {
    await _supabase.client.from('products').insert(data);
  }

  @override
  Future<dynamic> ensureProductAuction({
    required String productId,
    required double startingPrice,
    required double minimumIncrement,
    required int durationDays,
  }) {
    return _supabase.client.rpc(
      'ensure_product_auction',
      params: {
        'p_product_id': productId,
        'p_starting_price': startingPrice,
        'p_minimum_increment': minimumIncrement,
        'p_duration_days': durationDays,
      },
    );
  }

  @override
  Future<void> insertProductImages(List<Map<String, dynamic>> rows) async {
    await _supabase.client.from('product_images').insert(rows);
  }

  @override
  Future<void> deleteDraftProduct({
    required String productId,
    required String sellerId,
  }) async {
    try {
      await _supabase.client
          .from('products')
          .delete()
          .eq('product_id', productId)
          .eq('seller_id', sellerId);
    } catch (_) {
      // Fallback: mark as removed so an incomplete product never stays active.
      await _supabase.client
          .from('products')
          .update({'status': 'removed'})
          .eq('product_id', productId)
          .eq('seller_id', sellerId);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Enum mapping helpers (package-level for testability)
// ─────────────────────────────────────────────────────────────────────────────

/// Maps a [ProductCondition] to its corresponding DB string.
String conditionToDbString(ProductCondition condition) => switch (condition) {
  ProductCondition.newWithTags => 'new',
  ProductCondition.likeNew => 'like_new',
  ProductCondition.good => 'good',
  ProductCondition.fair => 'fair',
  ProductCondition.poor => 'poor',
};

/// Maps a [ListingFormat] to its corresponding DB string.
String formatToDbString(ListingFormat format) => switch (format) {
  ListingFormat.fixedPrice => 'fixed_price',
  ListingFormat.auction => 'auction',
};

/// Auction listings are always 1 unit. Fixed-price uses the seller's stock.
int listingQuantityAvailable(ListingFormat format, String stockText) {
  if (format == ListingFormat.auction) return 1;
  return int.tryParse(stockText.trim()) ?? 0;
}

/// Auctions skip the stock field. Fixed-price requires an integer in range.
bool listingStockIsValid(
  ListingFormat format,
  String stockText, {
  int min = 1,
}) {
  if (format == ListingFormat.auction) return true;
  final n = int.tryParse(stockText.trim());
  return n != null && n >= min && n <= 9999;
}

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

/// Owns all state, validation, image-picker interactions, and Supabase I/O for
/// the "Add Listing" flow.
///
/// The matching screen ([AddListingScreen]) is pure UI; it reads state through
/// `context.watch<AddListingController>()` and delegates every action here.
///
/// Inject this controller at the route level via a [ChangeNotifierProvider].
class AddListingController extends ChangeNotifier {
  AddListingController({
    required SupabaseService supabase,
    required AuthProvider auth,
    ImagePicker? imagePicker,
    ListingPublishGateway? gateway,
  }) : _auth = auth,
       _imagePicker = imagePicker ?? ImagePicker(),
       _gateway = gateway ?? _SupabaseListingPublishGateway(supabase) {
    loadCategories();
    loadSellerShopLocation();
  }

  // ── Dependencies ──────────────────────────────────────────────────────────

  final AuthProvider _auth;
  final ImagePicker _imagePicker;
  final ListingPublishGateway _gateway;

  // ── Image state ───────────────────────────────────────────────────────────

  /// Ordered list of images selected by the seller (max 3).
  /// Index 0 is always the cover image.
  List<SelectedImage> images = [];

  // ── Text controllers ──────────────────────────────────────────────────────

  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController startBidCtrl = TextEditingController();
  final TextEditingController brandCtrl = TextEditingController();
  final TextEditingController sizeCtrl = TextEditingController();
  final TextEditingController colorCtrl = TextEditingController();
  final TextEditingController stockCtrl = TextEditingController(text: '1');
  final TextEditingController shippingFeeCtrl = TextEditingController(
    text: '80',
  );
  final TextEditingController qtyThresholdCtrl = TextEditingController(
    text: '3',
  );
  final TextEditingController bidThresholdCtrl = TextEditingController(
    text: '500',
  );

  bool showItemLocation = false;
  ListingShippingMode shippingMode = ListingShippingMode.fixedFee;
  String? sellerBarangay;

  // ── Selection state ───────────────────────────────────────────────────────

  /// Categories fetched from the `categories` table.
  List<CategoryItem> categories = [];

  /// Whether categories are currently being loaded.
  bool categoriesLoading = false;

  /// The selected category's UUID (null until the seller picks one).
  String? selectedCategoryId;

  /// The selected category's display name.
  String? selectedCategoryName;

  /// Currently selected product condition (nullable until the seller picks one).
  ProductCondition? selectedCondition;

  /// Currently selected listing format; defaults to [ListingFormat.fixedPrice].
  ListingFormat selectedFormat = ListingFormat.fixedPrice;

  // ── Auction-specific state ────────────────────────────────────────────────

  /// Duration of the auction in days. Options: 1, 3, 5, 7.
  int auctionDurationDays = 3;

  /// Minimum bid increment amount (e.g. 10, 20, 50, 100).
  double bidIncrement = 10;

  // ── Async / progress state ────────────────────────────────────────────────

  /// Whether a post-listing operation is in progress.
  bool isLoading = false;

  /// Human-readable status shown on the posting overlay while [isLoading]
  /// is true (e.g. `"Uploading images (2/3)"`, `"Saving listing…"`).
  String uploadStatusMessage = '';

  bool _disposed = false;

  // ── Validation state ──────────────────────────────────────────────────────

  /// Field-level validation errors keyed by field name.
  ///
  /// Keys used: `'images'`, `'name'`, `'description'`, `'category'`,
  /// `'condition'`, `'price'`, `'stock'`.
  Map<String, String> fieldErrors = {};

  // ── Field change handlers ─────────────────────────────────────────────────

  /// Clears the `'name'` field error when the user edits the name field.
  void onNameChanged(String value) {
    fieldErrors.remove('name');
    _safeNotify();
  }

  /// Clears the `'description'` field error when the user edits the description field.
  void onDescChanged(String value) {
    fieldErrors.remove('description');
    _safeNotify();
  }

  /// Clears the `'price'` field error when the user edits the price field.
  void onPriceChanged(String value) {
    fieldErrors.remove('price');
    _safeNotify();
  }

  /// Clears the `'price'` field error when the user edits the starting bid field.
  void onStartBidChanged(String value) {
    fieldErrors.remove('price');
    _safeNotify();
  }

  /// Clears the `'stock'` field error when the user edits available quantity.
  void onStockChanged(String value) {
    fieldErrors.remove('stock');
    _safeNotify();
  }

  /// Fetches the list of active categories from the `categories` table.
  ///
  /// Called automatically by the constructor. Sets [categoriesLoading] while
  /// in progress and notifies listeners on completion.
  Future<void> loadCategories() async {
    categoriesLoading = true;
    _safeNotify();
    try {
      categories = await _gateway.fetchActiveCategories();
    } catch (_) {
      // Non-fatal — the picker will just show an empty list
    } finally {
      categoriesLoading = false;
      _safeNotify();
    }
  }

  /// Stores the selected category and clears the `'category'` field error.
  void selectCategory(String categoryId, String categoryName) {
    selectedCategoryId = categoryId;
    selectedCategoryName = categoryName;
    fieldErrors.remove('category');
    _safeNotify();
  }

  /// Sets [selectedCondition] and clears the `'condition'` field error.
  void selectCondition(ProductCondition condition) {
    selectedCondition = condition;
    fieldErrors.remove('condition');
    _safeNotify();
  }

  /// Sets [selectedFormat] to the given [format].
  void selectFormat(ListingFormat format) {
    selectedFormat = format;
    fieldErrors.remove('price');
    fieldErrors.remove('stock');
    if (format == ListingFormat.auction &&
        shippingMode == ListingShippingMode.quantityThreshold) {
      shippingMode = ListingShippingMode.fixedFee;
    }
    if (format == ListingFormat.fixedPrice &&
        shippingMode == ListingShippingMode.bidThreshold) {
      shippingMode = ListingShippingMode.fixedFee;
    }
    _safeNotify();
  }

  Future<void> loadSellerShopLocation() async {
    final sellerId = _auth.user?.id;
    if (sellerId == null) return;
    try {
      sellerBarangay = await _gateway.fetchSellerBarangay(sellerId);
      _safeNotify();
    } catch (_) {
      // Non-fatal — toggle stays disabled until shop address exists.
    }
  }

  void setShowItemLocation(bool value) {
    showItemLocation = value;
    _safeNotify();
  }

  void setShippingMode(ListingShippingMode mode) {
    shippingMode = mode;
    fieldErrors.remove('shippingFee');
    fieldErrors.remove('qtyThreshold');
    fieldErrors.remove('bidThreshold');
    _safeNotify();
  }

  /// Preview when listing is published (`now()` + duration days on server).
  DateTime get previewAuctionEndsAt =>
      DateTime.now().add(Duration(days: auctionDurationDays));

  /// Sets [auctionDurationDays] to the given [days].
  void selectAuctionDuration(int days) {
    auctionDurationDays = days;
    fieldErrors.remove('duration');
    _safeNotify();
  }

  /// Sets [bidIncrement] to the given [increment].
  void selectBidIncrement(double increment) {
    bidIncrement = increment;
    fieldErrors.remove('increment');
    _safeNotify();
  }

  // ── Post listing ──────────────────────────────────────────────────────────

  /// Validates, uploads images, and inserts the listing into Supabase.
  ///
  /// Steps:
  /// 1. Guards against concurrent submissions and unauthenticated users.
  /// 2. Validates selected images (format & size) and all required fields.
  /// 3. Synchronously sets [isLoading] before any async work to prevent double taps.
  /// 4. Checks active listing limit via RPC.
  /// 5. Uploads images to Storage (before any DB row is created).
  /// 6. Inserts the product row, auction RPC when needed, then `product_images`.
  /// 7. Rolls back storage and draft product rows if any step fails.
  /// 8. Navigates to seller listings on confirmed database success.
  Future<void> postListing(BuildContext context) async {
    if (isLoading) return;

    // 1. Auth guard
    if (_auth.user?.id == null) {
      if (context.mounted) {
        showThriftSnackBar(
          context,
          'You must be logged in to post a listing.',
          isError: true,
        );
      }
      return;
    }

    // 2. Check selected images for unsupported format or excessive size first
    if (images.isNotEmpty) {
      for (final img in images) {
        final pickError = productListingImagePickError(
          fileName: img.name,
          byteLength: img.bytes.length,
          bytes: img.bytes,
        );
        if (pickError != null) {
          fieldErrors['images'] = pickError;
          _safeNotify();
          if (context.mounted) {
            await _showImageValidationErrorDialog(context, pickError);
          }
          return;
        }
      }
    }

    // 3. Validate required fields (handled via inline validation + snackbar)
    if (!_validateForPost()) {
      if (context.mounted) {
        showThriftSnackBar(
          context,
          kListingMissingDetailsMessage,
          isError: true,
        );
      }
      return;
    }

    // 4. Lock submission synchronously BEFORE any await to prevent double taps
    isLoading = true;
    uploadStatusMessage = 'Preparing listing…';
    _safeNotify();

    // 5. Check active listing limit
    final limitBlocked = await _ensureCanPublishActiveListing();
    if (limitBlocked) {
      isLoading = false;
      uploadStatusMessage = '';
      _safeNotify();
      if (context.mounted) {
        await _showListingLimitDialog(context, kListingLimitReachedMessage);
      }
      return;
    }

    // 6. Generate product ID
    final productId = const Uuid().v4();
    final sellerId = _auth.user!.id;

    List<String>? uploadedImageUrls;
    var productInserted = false;
    var imagesUploaded = false;

    try {
      final categoryId = selectedCategoryId!;
      final priceValue = selectedFormat == ListingFormat.auction
          ? double.parse(startBidCtrl.text.trim())
          : double.parse(priceCtrl.text.trim());

      // c. Insert into products table
      await _supabase.client.from('products').insert({
        'product_id': productId,
        'seller_id': sellerId,
        'name': nameCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'price': priceValue,
        'condition': _conditionToDb(selectedCondition!),
        'status': 'active',
        'listing_type': _formatToDb(selectedFormat),
        'quantity_available': listingQuantityAvailable(
          selectedFormat,
          stockCtrl.text,
        ),
        'category_id': categoryId,
        if (sizeCtrl.text.isNotEmpty) 'size': sizeCtrl.text,
        if (brandCtrl.text.isNotEmpty) 'brand': brandCtrl.text,
        if (colorCtrl.text.isNotEmpty) 'color': colorCtrl.text,
        'show_item_location': showItemLocation,
        'shipping_mode': _resolvedShippingMode().dbValue,
        'shipping_fee': _resolvedShippingFee(),
        if (_resolvedQtyThreshold() != null)
          'free_shipping_qty_threshold': _resolvedQtyThreshold(),
        if (_resolvedBidThreshold() != null)
          'free_shipping_bid_threshold': _resolvedBidThreshold(),
        'boosted': false,
      });

      // c. Auction row must be created in the same listing flow.
      if (selectedFormat == ListingFormat.auction) {
        final rpcRes = await _gateway.ensureProductAuction(
          productId: productId,
          startingPrice: priceValue,
          minimumIncrement: bidIncrement,
          durationDays: auctionDurationDays,
        );
        if (!supabaseRpcSuccess(rpcRes)) {
          throw Exception(
            supabaseRpcError(rpcRes, fallback: 'auction_setup_failed'),
          );
        }
      }

      // d. Upload images (with cleanup on failure)
      List<String> imageUrls;
      try {
        imageUrls = await _uploadImages(sellerId, productId);
      } catch (e) {
        await _cleanupImages(sellerId, productId, images.length);
        if (context.mounted) {
          showThriftSnackBar(
            context,
            'Image upload failed. Please try again.',
            isError: true,
          );
        }
        return;
      }

      // e. Update status message
      uploadStatusMessage = 'Saving listing…';
      _safeNotify();

      // f. Insert product_images rows
      await _supabase.client.from('product_images').insert([
        for (var i = 0; i < imageUrls.length; i++)
          {
            'product_id': productId,
            'image_url': imageUrls[i],
            'is_primary': i == 0,
            'display_order': i,
          },
      ]);

      isLoading = false;
      uploadStatusMessage = '';
      _safeNotify();

      SellerListingsRefresh.notify(sellerId);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
        final router = GoRouter.maybeOf(context);
        if (router != null) {
          router.go(RouteNames.sellerHomeWithTab('listings'));
        }
        showThriftSnackBar(context, kListingPublishedSuccessMessage);
      }
    } catch (e) {
      debugPrint('AddListingController.postListing error: $e');
      if (productInserted) {
        await _deleteDraftProduct(productId, sellerId);
      }
      if (uploadedImageUrls != null && uploadedImageUrls.isNotEmpty) {
        await _cleanupImages(sellerId, productId, uploadedImageUrls.length);
      }

      // Clear loading overlay before presenting the error dialog.
      isLoading = false;
      uploadStatusMessage = '';
      _safeNotify();

      if (context.mounted) {
        final shouldRetry = await _presentPublishErrorDialog(
          context,
          error: e,
          imagesUploaded: imagesUploaded,
        );
        if (shouldRetry && context.mounted) {
          await postListing(context);
        }
      }
    } finally {
      if (isLoading) {
        isLoading = false;
        uploadStatusMessage = '';
        _safeNotify();
      }
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<bool> _ensureCanPublishActiveListing() async {
    try {
      final rpcRes = await _gateway.fetchListingLimitStatus();
      if (!supabaseRpcSuccess(rpcRes)) return false;
      final map = supabaseRpcMap(rpcRes);
      final canPublish = map?['can_publish'] == true;
      return !canPublish;
    } catch (e) {
      debugPrint('AddListingController listing limit check error: $e');
      return false;
    }
  }

  Future<void> _showListingLimitDialog(
    BuildContext context,
    String message,
  ) async {
    await showListingPublishErrorDialog(
      context,
      title: kListingLimitReachedTitle,
      message: message,
      icon: Icons.info_outline_rounded,
      canRetry: false,
      primaryLabel: 'Okay',
    );
  }

  Future<void> _showImageValidationErrorDialog(
    BuildContext context,
    String pickError,
  ) async {
    final isTooLarge = pickError == kProductListingImageTooLargeMessage;
    await showListingPublishErrorDialog(
      context,
      title: isTooLarge ? 'Image too large' : 'Unsupported image format',
      message: pickError,
      icon: isTooLarge
          ? Icons.photo_size_select_large_outlined
          : Icons.broken_image_outlined,
      canRetry: false,
      primaryLabel: 'Okay',
    );
  }

  Future<bool> _presentPublishErrorDialog(
    BuildContext context, {
    required Object error,
    required bool imagesUploaded,
  }) async {
    final limitMessage = listingLimitMessageFromError(error);
    if (limitMessage != null) {
      await _showListingLimitDialog(context, limitMessage);
      return false;
    }

    if (error is StorageException) {
      if (isStoragePayloadTooLarge(error)) {
        await _showImageValidationErrorDialog(
          context,
          kProductListingImageTooLargeMessage,
        );
        return false;
      }
      if (isStorageMimeTypeRejected(error)) {
        await _showImageValidationErrorDialog(
          context,
          kProductListingImageUnsupportedFormatMessage,
        );
        return false;
      }
    }

    if (isLikelyNetworkError(error)) {
      return showListingPublishErrorDialog(
        context,
        title: 'No internet connection',
        message: kListingPublishOfflineMessage,
        icon: Icons.wifi_off_rounded,
        canRetry: true,
      );
    }

    if (!imagesUploaded) {
      return showListingPublishErrorDialog(
        context,
        title: 'Couldn\'t upload photos',
        message: userFacingListingImageUploadError(error),
        icon: Icons.cloud_off_outlined,
        canRetry: true,
      );
    }

    return showListingPublishErrorDialog(
      context,
      title: 'Couldn\'t publish listing',
      message: userFacingListingPublishError(error),
      icon: Icons.error_outline_rounded,
      canRetry: true,
    );
  }

  Future<void> _deleteDraftProduct(String productId, String sellerId) async {
    try {
      await _gateway.deleteDraftProduct(
        productId: productId,
        sellerId: sellerId,
      );
    } catch (e) {
      debugPrint('AddListingController._deleteDraftProduct error: $e');
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    nameCtrl.dispose();
    descCtrl.dispose();
    priceCtrl.dispose();
    startBidCtrl.dispose();
    brandCtrl.dispose();
    sizeCtrl.dispose();
    colorCtrl.dispose();
    shippingFeeCtrl.dispose();
    qtyThresholdCtrl.dispose();
    bidThresholdCtrl.dispose();
    stockCtrl.dispose();
    super.dispose();
  }

  // ── Image management ──────────────────────────────────────────────────────

  /// Removes the image at [slotIndex] from [images].
  ///
  /// No-op if [slotIndex] is out of bounds. Notifies listeners on removal.
  /// Satisfies Requirement 2.3.
  void removeImage(int slotIndex) {
    if (slotIndex < images.length) {
      images = List<SelectedImage>.from(images)..removeAt(slotIndex);
      fieldErrors.remove('images');
      _safeNotify();
    }
  }

  /// Moves the image at [oldIndex] to [newIndex], applying the standard
  /// [ReorderableListView] index correction.
  ///
  /// Satisfies Requirement 2.4.
  void reorderImages(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = List<SelectedImage>.from(images);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    images = updated;
    _safeNotify();
  }

  // ── Image picker actions ──────────────────────────────────────────────────

  /// Opens the gallery and inserts a new image at [slotIndex].
  ///
  /// If [slotIndex] is beyond the current list length the image is appended.
  /// Satisfies Requirements 2.2, 2.3.
  Future<void> pickImage(int slotIndex, BuildContext context) async {
    if (images.length >= 3) return; // max 3 photos
    final XFile? xfile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (xfile == null) return;

    final bytes = await xfile.readAsBytes();
    final pickError = productListingImagePickError(
      fileName: xfile.name,
      byteLength: bytes.length,
      bytes: bytes,
    );
    if (pickError != null) {
      if (images.isEmpty) {
        fieldErrors['images'] = pickError;
        _safeNotify();
      }
      if (context.mounted) {
        await _showImageValidationErrorDialog(context, pickError);
      }
      return;
    }

    final selected = SelectedImage(bytes: bytes, name: xfile.name);

    if (slotIndex >= images.length) {
      images = List.of(images)..add(selected);
    } else {
      images = List.of(images)..insert(slotIndex, selected);
    }

    fieldErrors.remove('images');
    _safeNotify();
  }

  /// Opens the gallery and replaces the image at [slotIndex].
  ///
  /// If [slotIndex] is out of range, the image is appended instead.
  /// Satisfies Requirements 2.2, 2.3.
  Future<void> replaceImage(int slotIndex, BuildContext context) async {
    final XFile? xfile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (xfile == null) return;

    final bytes = await xfile.readAsBytes();
    final pickError = productListingImagePickError(
      fileName: xfile.name,
      byteLength: bytes.length,
      bytes: bytes,
    );
    if (pickError != null) {
      if (context.mounted) {
        await _showImageValidationErrorDialog(context, pickError);
      }
      return;
    }

    final selected = SelectedImage(bytes: bytes, name: xfile.name);

    if (slotIndex < images.length) {
      images = List.of(images)..[slotIndex] = selected;
    } else {
      images = List.of(images)..add(selected);
    }

    fieldErrors.remove('images');
    _safeNotify();
  }

  // ── Validation ────────────────────────────────────────────────────────────

  /// Validates all required fields before posting a listing.
  ///
  /// Clears [fieldErrors] completely, then checks each field in order.
  /// Returns `true` if there are no errors, `false` otherwise.
  /// Calls [notifyListeners] so the UI rebuilds with any error messages shown.
  bool _validateForPost() {
    fieldErrors = {};

    // Images
    if (images.isEmpty) {
      fieldErrors['images'] = 'Please add at least one photo.';
    }

    // Name
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      fieldErrors['name'] = 'Product name is required.';
    } else if (name.length > 100) {
      fieldErrors['name'] = 'Name must be 100 characters or fewer.';
    }

    final descriptionError = productDescriptionError(descCtrl.text);
    if (descriptionError != null) {
      fieldErrors['description'] = descriptionError;
    }

    // Category
    if (selectedCategoryId == null) {
      fieldErrors['category'] = 'Please select a category.';
    }

    // Condition
    if (selectedCondition == null) {
      fieldErrors['condition'] = 'Please select a condition.';
    }

    // Price + stock
    if (selectedFormat == ListingFormat.fixedPrice) {
      final price = double.tryParse(priceCtrl.text.trim());
      if (price == null || price <= 0) {
        fieldErrors['price'] = 'Please enter a valid price.';
      }
      if (!listingStockIsValid(selectedFormat, stockCtrl.text)) {
        fieldErrors['stock'] = 'Enter how many units you have (1 or more).';
      }
    } else if (selectedFormat == ListingFormat.auction) {
      final startBid = double.tryParse(startBidCtrl.text.trim());
      if (startBid == null || startBid <= 0) {
        fieldErrors['price'] = 'Please enter a valid starting price.';
      }
      if (bidIncrement <= 0) {
        fieldErrors['increment'] = 'Please choose a valid bid increment.';
      }
      if (![1, 3, 5, 7].contains(auctionDurationDays)) {
        fieldErrors['duration'] =
            'Auction duration must be 1, 3, 5, or 7 days.';
      }
    }

    _validateShippingFields();

    _safeNotify();
    return fieldErrors.isEmpty;
  }

  void _validateShippingFields() {
    if (shippingMode == ListingShippingMode.free) return;

    final fee = double.tryParse(shippingFeeCtrl.text.trim());
    if (fee == null || fee <= 0) {
      fieldErrors['shippingFee'] = 'Enter a shipping fee greater than zero.';
    }

    if (selectedFormat == ListingFormat.fixedPrice &&
        shippingMode == ListingShippingMode.quantityThreshold) {
      final qty = int.tryParse(qtyThresholdCtrl.text.trim());
      if (qty == null || qty < 2) {
        fieldErrors['qtyThreshold'] =
            'Quantity must be at least 2 for this option.';
      }
    }

    if (selectedFormat == ListingFormat.auction &&
        shippingMode == ListingShippingMode.bidThreshold) {
      final threshold = double.tryParse(bidThresholdCtrl.text.trim());
      final startBid = double.tryParse(startBidCtrl.text.trim());
      if (threshold == null || threshold <= 0) {
        fieldErrors['bidThreshold'] = 'Enter a valid bid amount.';
      } else if (startBid != null && threshold <= startBid) {
        fieldErrors['bidThreshold'] =
            'Free-shipping bid must be higher than the starting bid.';
      }
    }
  }

  ListingShippingMode _resolvedShippingMode() {
    if (selectedFormat == ListingFormat.auction &&
        shippingMode == ListingShippingMode.quantityThreshold) {
      return ListingShippingMode.fixedFee;
    }
    if (selectedFormat == ListingFormat.fixedPrice &&
        shippingMode == ListingShippingMode.bidThreshold) {
      return ListingShippingMode.fixedFee;
    }
    return shippingMode;
  }

  double _resolvedShippingFee() {
    if (shippingMode == ListingShippingMode.free) return 0;
    return double.tryParse(shippingFeeCtrl.text.trim()) ?? 0;
  }

  int? _resolvedQtyThreshold() {
    if (selectedFormat != ListingFormat.fixedPrice ||
        shippingMode != ListingShippingMode.quantityThreshold) {
      return null;
    }
    return int.tryParse(qtyThresholdCtrl.text.trim());
  }

  double? _resolvedBidThreshold() {
    if (selectedFormat != ListingFormat.auction ||
        shippingMode != ListingShippingMode.bidThreshold) {
      return null;
    }
    return double.tryParse(bidThresholdCtrl.text.trim());
  }

  // ── DB mapping helpers ────────────────────────────────────────────────────

  /// Maps a [ProductCondition] value to the corresponding DB string.
  String _conditionToDb(ProductCondition condition) =>
      conditionToDbString(condition);

  /// Maps a [ListingFormat] value to the corresponding DB string.
  String _formatToDb(ListingFormat format) => formatToDbString(format);

  // ── Image upload ──────────────────────────────────────────────────────────

  /// Uploads each image in [images] to the `product-images` Storage bucket.
  ///
  /// Path pattern: `$sellerId/$productId/$index$ext`
  /// Updates [uploadStatusMessage] before each upload and notifies listeners.
  /// Returns an ordered list of public URLs matching the image list.
  ///
  /// Satisfies Requirements 2.6, 8.3.
  Future<List<String>> _uploadImages(String sellerId, String productId) async {
    final urls = <String>[];

    try {
      for (var i = 0; i < images.length; i++) {
        uploadStatusMessage = 'Uploading images (${i + 1}/${images.length})';
        _safeNotify();

        final ext = productListingImageStorageExtension(
          images[i].name,
          bytes: images[i].bytes,
        );
        final path = '$sellerId/$productId/$i$ext';
        final url = await _gateway.uploadProductImage(
          path: path,
          bytes: images[i].bytes,
          contentType: productListingImageContentType(
            images[i].name,
            bytes: images[i].bytes,
          ),
        );
        urls.add(url);
      }
    } catch (e) {
      if (urls.isNotEmpty) {
        await _cleanupImages(sellerId, productId, urls.length);
      }
      rethrow;
    }

    return urls;
  }

  // ── Image cleanup ─────────────────────────────────────────────────────────

  /// Removes already-uploaded images from Storage when an upload or subsequent
  /// database write fails.
  ///
  /// Builds the list of storage paths for indices `0` to `uploadedCount - 1`
  /// under `product-images/$sellerId/$productId/` and calls `remove` on the
  /// bucket. Any exception is swallowed — this is best-effort cleanup.
  ///
  /// Satisfies Requirement 2.8.
  Future<void> _cleanupImages(
    String sellerId,
    String productId,
    int uploadedCount,
  ) async {
    final paths = [
      for (var i = 0; i < uploadedCount; i++)
        '$sellerId/$productId/$i${productListingImageStorageExtension(images[i].name, bytes: images[i].bytes)}',
    ];
    try {
      await _gateway.removeProductImages(paths);
    } catch (_) {
      // Best-effort — ignore any errors during cleanup.
    }
  }
}
