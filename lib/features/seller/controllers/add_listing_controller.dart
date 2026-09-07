import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:uuid/uuid.dart';

import '../../../core/routes/route_names.dart';
import '../../../core/services/supabase_service.dart';
import '../../../models/enums.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/thrift_widgets.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Category model (fetched from DB)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// A category row fetched from the `categories` table.
class CategoryItem {
  const CategoryItem({required this.id, required this.name});

  final String id;
  final String name;
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Local models and enums
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// A device image that the seller has selected for this listing.
///
/// [bytes] holds the raw image data â€” works on both mobile and web.
/// [name] is the original filename, used to derive the MIME type.
class SelectedImage {
  const SelectedImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// The selling format the seller chooses for their listing.
///
/// Maps to the `listing_type_enum` DB values:
///   - [fixedPrice]  â†’ `'fixed_price'`
///   - [auction]     â†’ `'auction'`
enum ListingFormat { fixedPrice, auction }

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Enum mapping helpers (package-level for testability)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Controller
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
  })  : _supabase = supabase,
        _auth = auth,
        _imagePicker = imagePicker ?? ImagePicker() {
    loadCategories();
  }

  // â”€â”€ Dependencies â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final ImagePicker _imagePicker;

  // â”€â”€ Image state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Ordered list of images selected by the seller (max 8).
  /// Index 0 is always the cover image.
  List<SelectedImage> images = [];

  // â”€â”€ Text controllers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController startBidCtrl = TextEditingController();
  final TextEditingController brandCtrl = TextEditingController();
  final TextEditingController sizeCtrl = TextEditingController();
  final TextEditingController colorCtrl = TextEditingController();
  final TextEditingController locationCtrl = TextEditingController();

  // â”€â”€ Selection state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

  // â”€â”€ Auction-specific state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Duration of the auction in days. Options: 1, 3, 5, 7.
  int auctionDurationDays = 3;

  /// Minimum bid increment amount (e.g. 10, 20, 50, 100).
  double bidIncrement = 10;

  // â”€â”€ Async / progress state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Whether a post-listing operation is in progress.
  bool isLoading = false;

  /// Human-readable status shown while [isLoading] is true
  /// (e.g. `"Uploading imagesâ€¦ (2/5)"`, `"Saving listingâ€¦"`).
  String uploadStatusMessage = '';

  // â”€â”€ Validation state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Field-level validation errors keyed by field name.
  ///
  /// Keys used: `'images'`, `'name'`, `'description'`, `'category'`,
  /// `'condition'`, `'price'`.
  Map<String, String> fieldErrors = {};

  // â”€â”€ Field change handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Clears the `'name'` field error when the user edits the name field.
  void onNameChanged(String value) {
    fieldErrors.remove('name');
    notifyListeners();
  }

  /// Clears the `'description'` field error when the user edits the description field.
  void onDescChanged(String value) {
    fieldErrors.remove('description');
    notifyListeners();
  }

  /// Clears the `'price'` field error when the user edits the price field.
  void onPriceChanged(String value) {
    fieldErrors.remove('price');
    notifyListeners();
  }

  /// Clears the `'price'` field error when the user edits the starting bid field.
  void onStartBidChanged(String value) {
    fieldErrors.remove('price');
    notifyListeners();
  }

  /// Fetches the list of active categories from the `categories` table.
  ///
  /// Called automatically by the constructor. Sets [categoriesLoading] while
  /// in progress and notifies listeners on completion.
  Future<void> loadCategories() async {
    categoriesLoading = true;
    notifyListeners();
    try {
      final rows = await _supabase.client
          .from('categories')
          .select('category_id, category_name')
          .eq('is_active', true)
          .order('category_name');
      categories = (rows as List)
          .map((r) => CategoryItem(
                id: r['category_id'] as String,
                name: r['category_name'] as String,
              ))
          .toList();
    } catch (_) {
      // Non-fatal â€” the picker will just show an empty list
    } finally {
      categoriesLoading = false;
      notifyListeners();
    }
  }

  /// Stores the selected category and clears the `'category'` field error.
  void selectCategory(String categoryId, String categoryName) {
    selectedCategoryId = categoryId;
    selectedCategoryName = categoryName;
    fieldErrors.remove('category');
    notifyListeners();
  }

  /// Sets [selectedCondition] and clears the `'condition'` field error.
  void selectCondition(ProductCondition condition) {
    selectedCondition = condition;
    fieldErrors.remove('condition');
    notifyListeners();
  }

  /// Sets [selectedFormat] to the given [format].
  void selectFormat(ListingFormat format) {
    selectedFormat = format;
    fieldErrors.remove('price');
    notifyListeners();
  }

  /// Sets [auctionDurationDays] to the given [days].
  void selectAuctionDuration(int days) {
    auctionDurationDays = days;
    notifyListeners();
  }

  /// Sets [bidIncrement] to the given [increment].
  void selectBidIncrement(double increment) {
    bidIncrement = increment;
    notifyListeners();
  }

  // â”€â”€ Post listing â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Validates, uploads images, and inserts the listing into Supabase.
  ///
  /// Steps:
  /// 1. Guards against unauthenticated users.
  /// 2. Validates all required fields via [_validateForPost].
  /// 3. Sets loading state and generates a new product UUID.
  /// 4. Resolves the category ID from the `categories` table.
  /// 5. Inserts the product row into `products`.
  /// 6. Uploads images to Storage and inserts rows into `product_images`.
  /// 7. Navigates to [RouteNames.sellerHome] on success.
  ///
  /// Satisfies Requirements 4.1â€“4.4, 8.1â€“8.4.
  Future<void> postListing(BuildContext context) async {
    // 1. Auth guard
    if (_auth.user?.id == null) {
      showThriftSnackBar(
        context,
        'You must be logged in to post a listing.',
        isError: true,
      );
      return;
    }

    // 2. Validate
    if (!_validateForPost()) return;

    // 3. Set loading state
    isLoading = true;
    uploadStatusMessage = 'Preparingâ€¦';
    notifyListeners();

    // 4. Generate product ID
    final productId = const Uuid().v4();
    final sellerId = _auth.user!.id;

    try {
      // a. Use already-resolved category ID
      final categoryId = selectedCategoryId!;

      // b. Determine price value
      final priceValue = selectedFormat == ListingFormat.auction
          ? double.parse(startBidCtrl.text)
          : double.parse(priceCtrl.text);

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
        'category_id': categoryId,
        if (sizeCtrl.text.isNotEmpty) 'size': sizeCtrl.text,
        if (brandCtrl.text.isNotEmpty) 'brand': brandCtrl.text,
        if (colorCtrl.text.isNotEmpty) 'color': colorCtrl.text,
        if (locationCtrl.text.isNotEmpty) 'location': locationCtrl.text,
        'boosted': false,
      });

      // c2. If auction, also create the auctions row
      if (selectedFormat == ListingFormat.auction) {
        final now = DateTime.now().toUtc();
        final endsAt = now.add(Duration(days: auctionDurationDays));

        await _supabase.client.from('auctions').insert({
          'product_id': productId,
          'starting_price': priceValue,
          'minimum_increment': bidIncrement,
          'current_price': priceValue,
          'starts_at': now.toIso8601String(),
          'ends_at': endsAt.toIso8601String(),
          'status': 'active',
        });
      }

      // d. Upload images (with cleanup on failure)
      List<String> imageUrls;
      try {
        imageUrls = await _uploadImages(sellerId, productId);
      } catch (e) {
        await _cleanupImages(sellerId, productId, images.length);
        isLoading = false;
        notifyListeners();
        if (context.mounted) {
          showThriftSnackBar(context, 'Image upload failed: $e', isError: true);
        }
        return;
      }

      // e. Update status message
      uploadStatusMessage = 'Saving listingâ€¦';
      notifyListeners();

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

      // g. Clear loading state
      isLoading = false;
      notifyListeners();

      // h. Navigate to seller home
      if (context.mounted) context.go(RouteNames.sellerHome);

      // i. Show success snackbar
      if (context.mounted) showThriftSnackBar(context, 'Listing published!');
    } catch (e) {
      // j. Catch-all error handler
      isLoading = false;
      notifyListeners();
      if (context.mounted) {
        showThriftSnackBar(context, 'Failed to post listing: $e', isError: true);
      }
    }
  }

  // â”€â”€ Lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    priceCtrl.dispose();
    startBidCtrl.dispose();
    brandCtrl.dispose();
    sizeCtrl.dispose();
    colorCtrl.dispose();
    locationCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ Image management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Removes the image at [slotIndex] from [images].
  ///
  /// No-op if [slotIndex] is out of bounds. Notifies listeners on removal.
  /// Satisfies Requirement 2.3.
  void removeImage(int slotIndex) {
    if (slotIndex < images.length) {
      images = List<SelectedImage>.from(images)..removeAt(slotIndex);
      notifyListeners();
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
    notifyListeners();
  }

  // â”€â”€ Image picker actions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Opens the gallery and inserts a new image at [slotIndex].
  ///
  /// If [slotIndex] is beyond the current list length the image is appended.
  /// Satisfies Requirements 2.2, 2.3.
  Future<void> pickImage(int slotIndex) async {
    if (images.length >= 3) return; // max 3 photos
    final XFile? xfile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;

    final bytes = await xfile.readAsBytes();
    final selected = SelectedImage(bytes: bytes, name: xfile.name);

    if (slotIndex >= images.length) {
      images = List.of(images)..add(selected);
    } else {
      images = List.of(images)..insert(slotIndex, selected);
    }

    notifyListeners();
  }

  /// Opens the gallery and replaces the image at [slotIndex].
  ///
  /// If [slotIndex] is out of range, the image is appended instead.
  /// Satisfies Requirements 2.2, 2.3.
  Future<void> replaceImage(int slotIndex) async {
    final XFile? xfile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;

    final bytes = await xfile.readAsBytes();
    final selected = SelectedImage(bytes: bytes, name: xfile.name);

    if (slotIndex < images.length) {
      images = List.of(images)..[slotIndex] = selected;
    } else {
      images = List.of(images)..add(selected);
    }

    notifyListeners();
  }

  // â”€â”€ Validation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

    // Description
    final desc = descCtrl.text.trim();
    if (desc.isEmpty) {
      fieldErrors['description'] = 'Description is required.';
    } else if (desc.length > 150) {
      fieldErrors['description'] = 'Description must be 150 characters or fewer.';
    }

    // Category
    if (selectedCategoryId == null) {
      fieldErrors['category'] = 'Please select a category.';
    }

    // Condition
    if (selectedCondition == null) {
      fieldErrors['condition'] = 'Please select a condition.';
    }

    // Price
    if (selectedFormat == ListingFormat.fixedPrice) {
      final price = double.tryParse(priceCtrl.text);
      if (price == null || price <= 0) {
        fieldErrors['price'] = 'Please enter a valid price.';
      }
    } else if (selectedFormat == ListingFormat.auction) {
      final startBid = double.tryParse(startBidCtrl.text);
      if (startBid == null || startBid <= 0) {
        fieldErrors['price'] = 'Please enter a valid price.';
      }
    }

    notifyListeners();
    return fieldErrors.isEmpty;
  }

  // â”€â”€ DB mapping helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Maps a [ProductCondition] value to the corresponding DB string.
  String _conditionToDb(ProductCondition condition) =>
      conditionToDbString(condition);

  /// Maps a [ListingFormat] value to the corresponding DB string.
  String _formatToDb(ListingFormat format) => formatToDbString(format);

  // â”€â”€ Image upload â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Uploads each image in [images] to the `product-images` Storage bucket.
  ///
  /// Path pattern: `$sellerId/$productId/$index.jpg`
  /// Updates [uploadStatusMessage] before each upload and notifies listeners.
  /// Returns an ordered list of public URLs matching the image list.
  ///
  /// Satisfies Requirements 2.6, 8.3.
  Future<List<String>> _uploadImages(
    String sellerId,
    String productId,
  ) async {
    final urls = <String>[];

    for (var i = 0; i < images.length; i++) {
      uploadStatusMessage = 'Uploading imagesâ€¦ (${i + 1}/${images.length})';
      notifyListeners();

      final path = '$sellerId/$productId/$i.jpg';
      await _supabase.client.storage
          .from('product-images')
          .uploadBinary(
            path,
            images[i].bytes,
            fileOptions: FileOptions(contentType: 'image/jpeg'),
          );

      final url = _supabase.client.storage
          .from('product-images')
          .getPublicUrl(path);
      urls.add(url);
    }

    return urls;
  }

  // â”€â”€ Image cleanup â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  /// Removes already-uploaded images from Storage when an upload fails
  /// mid-way through the sequence.
  ///
  /// Builds the list of storage paths for indices `0` to `uploadedCount - 1`
  /// under `product-images/$sellerId/$productId/` and calls `remove` on the
  /// bucket. Any exception is swallowed â€” this is best-effort cleanup.
  ///
  /// Satisfies Requirement 2.8.
  Future<void> _cleanupImages(
    String sellerId,
    String productId,
    int uploadedCount,
  ) async {
    final paths = [
      for (var i = 0; i < uploadedCount; i++) '$sellerId/$productId/$i.jpg',
    ];
    try {
      await _supabase.client.storage.from('product-images').remove(paths);
    } catch (_) {
      // Best-effort â€” ignore any errors during cleanup.
    }
  }
}
