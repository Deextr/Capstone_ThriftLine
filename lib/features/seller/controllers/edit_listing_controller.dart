import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/enums.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/thrift_widgets.dart';
import 'add_listing_controller.dart'
    show
        CategoryItem,
        ListingFormat,
        SelectedImage,
        conditionToDbString,
        formatToDbString,
        listingQuantityAvailable,
        listingStockIsValid;

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Existing image (already on Supabase Storage)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// An image that already exists in `product_images` (has a URL, not bytes).
class ExistingImage {
  const ExistingImage({
    required this.imageId,
    required this.imageUrl,
    required this.displayOrder,
  });

  final String imageId;
  final String imageUrl;
  final int displayOrder;
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// A slot in the image strip â€” either existing or newly picked
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

sealed class ImageSlot {}

class ExistingSlot extends ImageSlot {
  ExistingSlot(this.image);
  final ExistingImage image;
}

class NewSlot extends ImageSlot {
  NewSlot(this.image);
  final SelectedImage image;
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Controller
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class EditListingController extends ChangeNotifier {
  EditListingController({
    required this.productId,
    required SupabaseService supabase,
    required AuthProvider auth,
    ImagePicker? imagePicker,
  }) : _supabase = supabase,
       _auth = auth,
       _imagePicker = imagePicker ?? ImagePicker() {
    _init();
  }

  final String productId;
  final SupabaseService _supabase;
  final AuthProvider _auth;
  final ImagePicker _imagePicker;

  // â”€â”€ Loading state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool initialLoading = true;
  String? loadError;

  // â”€â”€ Image slots (max 3) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<ImageSlot> slots = [];

  // â”€â”€ Text controllers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController startBidCtrl = TextEditingController();
  final TextEditingController brandCtrl = TextEditingController();
  final TextEditingController sizeCtrl = TextEditingController();
  final TextEditingController colorCtrl = TextEditingController();
  final TextEditingController locationCtrl = TextEditingController();
  final TextEditingController stockCtrl = TextEditingController(text: '1');

  // â”€â”€ Selection state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  List<CategoryItem> categories = [];
  bool categoriesLoading = false;
  String? selectedCategoryId;
  String? selectedCategoryName;
  ProductCondition? selectedCondition;
  ListingFormat selectedFormat = ListingFormat.fixedPrice;
  int auctionDurationDays = 3;
  double bidIncrement = 10;

  // â”€â”€ Save state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool isSaving = false;
  String saveStatusMessage = '';
  Map<String, String> fieldErrors = {};

  // â”€â”€ IDs to delete from product_images on save â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  final List<String> _removedImageIds = [];

  // â”€â”€ Init â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> _init() async {
    await Future.wait([_loadProduct(), _loadCategories()]);
  }

  Future<void> _loadCategories() async {
    categoriesLoading = true;
    notifyListeners();
    try {
      final rows = await _supabase.client
          .from('categories')
          .select('category_id, category_name')
          .eq('is_active', true)
          .order('category_name');
      categories = (rows as List)
          .map(
            (r) => CategoryItem(
              id: r['category_id'] as String,
              name: r['category_name'] as String,
            ),
          )
          .toList();
    } catch (_) {
    } finally {
      categoriesLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProduct() async {
    try {
      final row = await _supabase.client
          .from('products')
          .select(
            'product_id, name, description, price, condition, listing_type, '
            'quantity_available, brand, size, color, location, category_id, '
            'categories(category_name), '
            'product_images(image_id, image_url, is_primary, display_order)',
          )
          .eq('product_id', productId)
          .single();

      // Text fields
      nameCtrl.text = row['name'] as String? ?? row['title'] as String? ?? '';
      descCtrl.text = row['description'] as String? ?? '';
      brandCtrl.text = row['brand'] as String? ?? '';
      sizeCtrl.text = row['size'] as String? ?? '';
      colorCtrl.text = row['color'] as String? ?? '';
      locationCtrl.text = row['location'] as String? ?? '';

      // Category
      selectedCategoryId = row['category_id'] as String?;
      final catRow = row['categories'];
      if (catRow != null) {
        selectedCategoryName = catRow['category_name'] as String?;
      }

      // Condition
      final condStr = row['condition'] as String? ?? '';
      selectedCondition = _conditionFromDb(condStr);

      // Format + price
      final fmtStr = row['listing_type'] as String? ?? 'fixed_price';
      selectedFormat = _formatFromDb(fmtStr);
      final price = (row['price'] as num?)?.toDouble() ?? 0;
      if (selectedFormat == ListingFormat.auction) {
        startBidCtrl.text = price.toString();
      } else {
        priceCtrl.text = price.toString();
      }

      final qty = (row['quantity_available'] as num?)?.toInt() ?? 1;
      stockCtrl.text = qty.toString();

      if (selectedFormat == ListingFormat.auction) {
        try {
          final auctionRow = await _supabase.client
              .from('auctions')
              .select('minimum_increment, duration_days, starts_at, ends_at')
              .eq('product_id', productId)
              .maybeSingle();
          if (auctionRow != null) {
            bidIncrement =
                (auctionRow['minimum_increment'] as num?)?.toDouble() ??
                bidIncrement;
            final storedDays = (auctionRow['duration_days'] as num?)?.toInt();
            if (storedDays != null && [1, 3, 5, 7].contains(storedDays)) {
              auctionDurationDays = storedDays;
            } else {
              final startsAt = DateTime.tryParse(
                auctionRow['starts_at'] as String? ?? '',
              );
              final endsAt = DateTime.tryParse(
                auctionRow['ends_at'] as String? ?? '',
              );
              if (startsAt != null && endsAt != null) {
                final days = endsAt.difference(startsAt).inDays;
                if ([1, 3, 5, 7].contains(days)) {
                  auctionDurationDays = days;
                }
              }
            }
          }
        } catch (_) {}
      }

      // Images â€” sort by display_order
      final imgRows = (row['product_images'] as List? ?? []);
      imgRows.sort(
        (a, b) =>
            (a['display_order'] as int).compareTo(b['display_order'] as int),
      );
      slots = imgRows
          .map(
            (i) =>
                ExistingSlot(
                      ExistingImage(
                        imageId: i['image_id'] as String,
                        imageUrl: i['image_url'] as String,
                        displayOrder: i['display_order'] as int,
                      ),
                    )
                    as ImageSlot,
          )
          .toList();

      initialLoading = false;
      notifyListeners();
    } catch (e) {
      loadError = 'Failed to load listing: $e';
      initialLoading = false;
      notifyListeners();
    }
  }

  // â”€â”€ Field change handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void onNameChanged(String _) {
    fieldErrors.remove('name');
    notifyListeners();
  }

  void onDescChanged(String _) {
    fieldErrors.remove('description');
    notifyListeners();
  }

  void onPriceChanged(String _) {
    fieldErrors.remove('price');
    notifyListeners();
  }

  void onStartBidChanged(String _) {
    fieldErrors.remove('price');
    notifyListeners();
  }

  void onStockChanged(String _) {
    fieldErrors.remove('stock');
    notifyListeners();
  }

  void selectCategory(String categoryId, String categoryName) {
    selectedCategoryId = categoryId;
    selectedCategoryName = categoryName;
    fieldErrors.remove('category');
    notifyListeners();
  }

  void selectCondition(ProductCondition condition) {
    selectedCondition = condition;
    fieldErrors.remove('condition');
    notifyListeners();
  }

  void selectFormat(ListingFormat format) {
    selectedFormat = format;
    fieldErrors.remove('price');
    fieldErrors.remove('stock');
    notifyListeners();
  }

  void selectAuctionDuration(int days) {
    auctionDurationDays = days;
    notifyListeners();
  }

  void selectBidIncrement(double increment) {
    bidIncrement = increment;
    notifyListeners();
  }

  // â”€â”€ Image management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> pickImage(int slotIndex) async {
    if (slots.length >= 3) return;
    final xfile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    final newSlot = NewSlot(SelectedImage(bytes: bytes, name: xfile.name));
    if (slotIndex >= slots.length) {
      slots = [...slots, newSlot];
    } else {
      slots = [...slots]..[slotIndex] = newSlot;
    }
    notifyListeners();
  }

  Future<void> replaceImage(int slotIndex) async {
    final xfile = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    final bytes = await xfile.readAsBytes();
    final newSlot = NewSlot(SelectedImage(bytes: bytes, name: xfile.name));
    final old = slotIndex < slots.length ? slots[slotIndex] : null;
    if (old is ExistingSlot) {
      _removedImageIds.add(old.image.imageId);
    }
    if (slotIndex < slots.length) {
      slots = [...slots]..[slotIndex] = newSlot;
    } else {
      slots = [...slots, newSlot];
    }
    notifyListeners();
  }

  void removeImage(int slotIndex) {
    if (slotIndex >= slots.length) return;
    final slot = slots[slotIndex];
    if (slot is ExistingSlot) {
      _removedImageIds.add(slot.image.imageId);
    }
    slots = [...slots]..removeAt(slotIndex);
    notifyListeners();
  }

  void reorderImages(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final updated = [...slots];
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    slots = updated;
    notifyListeners();
  }

  // â”€â”€ Validation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  bool _validate() {
    fieldErrors = {};

    if (slots.isEmpty) {
      fieldErrors['images'] = 'Please add at least one photo.';
    }

    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      fieldErrors['name'] = 'Product name is required.';
    } else if (name.length > 100) {
      fieldErrors['name'] = 'Name must be 100 characters or fewer.';
    }

    final desc = descCtrl.text.trim();
    if (desc.isEmpty) {
      fieldErrors['description'] = 'Description is required.';
    } else if (desc.length > 150) {
      fieldErrors['description'] =
          'Description must be 150 characters or fewer.';
    }

    if (selectedCategoryId == null) {
      fieldErrors['category'] = 'Please select a category.';
    }

    if (selectedCondition == null) {
      fieldErrors['condition'] = 'Please select a condition.';
    }

    final priceText = selectedFormat == ListingFormat.auction
        ? startBidCtrl.text
        : priceCtrl.text;
    final price = double.tryParse(priceText);
    if (price == null || price <= 0) {
      fieldErrors['price'] = selectedFormat == ListingFormat.auction
          ? 'Please enter a valid starting price.'
          : 'Please enter a valid price.';
    }
    if (!listingStockIsValid(selectedFormat, stockCtrl.text, min: 0)) {
      fieldErrors['stock'] = 'Enter how many units you have (0 or more).';
    }
    if (selectedFormat == ListingFormat.auction) {
      if (bidIncrement <= 0) {
        fieldErrors['increment'] = 'Please choose a valid bid increment.';
      }
      if (![1, 3, 5, 7].contains(auctionDurationDays)) {
        fieldErrors['duration'] =
            'Auction duration must be 1, 3, 5, or 7 days.';
      }
    }

    notifyListeners();
    return fieldErrors.isEmpty;
  }

  // â”€â”€ Save â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<void> saveChanges(BuildContext context) async {
    if (!_validate()) return;

    final sellerId = _auth.user?.id;
    if (sellerId == null) {
      showThriftSnackBar(context, 'Not authenticated.', isError: true);
      return;
    }

    isSaving = true;
    saveStatusMessage = 'Savingâ€¦';
    notifyListeners();

    try {
      // 1. Update products row
      final priceValue = selectedFormat == ListingFormat.auction
          ? double.parse(startBidCtrl.text)
          : double.parse(priceCtrl.text);

      await _supabase.client
          .from('products')
          .update({
            'name': nameCtrl.text.trim(),
            'description': descCtrl.text.trim(),
            'price': priceValue,
            'condition': conditionToDbString(selectedCondition!),
            'listing_type': formatToDbString(selectedFormat),
            'quantity_available': listingQuantityAvailable(
              selectedFormat,
              stockCtrl.text,
            ),
            'category_id': selectedCategoryId,
            if (sizeCtrl.text.isNotEmpty)
              'size': sizeCtrl.text
            else
              'size': null,
            if (brandCtrl.text.isNotEmpty)
              'brand': brandCtrl.text
            else
              'brand': null,
            if (colorCtrl.text.isNotEmpty)
              'color': colorCtrl.text
            else
              'color': null,
            if (locationCtrl.text.isNotEmpty)
              'location': locationCtrl.text
            else
              'location': null,
          })
          .eq('product_id', productId);

      // 1b. Auction params go through ensure_product_auction (no client writes).
      if (selectedFormat == ListingFormat.auction) {
        final rpcRes = await _supabase.client.rpc(
          'ensure_product_auction',
          params: {
            'p_product_id': productId,
            'p_starting_price': priceValue,
            'p_minimum_increment': bidIncrement,
            'p_duration_days': auctionDurationDays,
          },
        );
        if (!supabaseRpcSuccess(rpcRes)) {
          throw Exception(
            supabaseRpcError(
              rpcRes,
              fallback: 'Failed to save the auction record.',
            ),
          );
        }
      }

      // 2. Delete removed images from product_images table
      if (_removedImageIds.isNotEmpty) {
        await _supabase.client
            .from('product_images')
            .delete()
            .inFilter('image_id', _removedImageIds);
        _removedImageIds.clear();
      }

      // 3. Upload new images and insert rows
      final newSlots = slots
          .asMap()
          .entries
          .where((e) => e.value is NewSlot)
          .toList();

      for (final entry in newSlots) {
        final idx = entry.key;
        final slot = entry.value as NewSlot;
        saveStatusMessage =
            'Uploading image ${newSlots.indexOf(entry) + 1}/${newSlots.length}â€¦';
        notifyListeners();

        final path = '$sellerId/$productId/edit_$idx.jpg';
        await _supabase.client.storage
            .from('product-images')
            .uploadBinary(
              path,
              slot.image.bytes,
              fileOptions: FileOptions(contentType: 'image/jpeg'),
            );
        final url = _supabase.client.storage
            .from('product-images')
            .getPublicUrl(path);

        await _supabase.client.from('product_images').insert({
          'product_id': productId,
          'image_url': url,
          'is_primary': idx == 0,
          'display_order': idx,
        });
      }

      // 4. Re-index display_order for all existing images
      saveStatusMessage = 'Finishing upâ€¦';
      notifyListeners();
      for (int i = 0; i < slots.length; i++) {
        final slot = slots[i];
        if (slot is ExistingSlot) {
          await _supabase.client
              .from('product_images')
              .update({'display_order': i, 'is_primary': i == 0})
              .eq('image_id', slot.image.imageId);
        }
      }

      isSaving = false;
      notifyListeners();

      if (context.mounted) {
        showThriftSnackBar(context, 'Listing updated!');
        context.pop();
      }
    } catch (e) {
      isSaving = false;
      notifyListeners();
      if (context.mounted) {
        showThriftSnackBar(context, 'Failed to save: $e', isError: true);
      }
    }
  }

  // â”€â”€ Lifecycle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
    stockCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ DB helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  ProductCondition _conditionFromDb(String s) =>
      ProductCondition.fromDbString(s);

  ListingFormat _formatFromDb(String s) {
    if (s == 'auction') return ListingFormat.auction;
    return ListingFormat.fixedPrice;
  }
}
