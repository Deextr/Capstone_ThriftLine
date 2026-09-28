# Implementation Plan: Create Product Listing

## Overview

Replace the mock multi-step `PageView` form in `add_listing_screen.dart` with a real single-scroll listing form backed by a dedicated `AddListingController` (`ChangeNotifier`). The controller owns all state, validation, image-picker interactions, and Supabase I/O for publishing listings. The screen is pure UI that observes the controller via Provider. The controller is injected into the widget tree at the `addListing` route level inside `app_router.dart`.

## Tasks

- [x] 1. Create `AddListingController` skeleton and local models
  - [x] 1.1 Create `lib/features/seller/controllers/add_listing_controller.dart` with the `SelectedImage` model, `ListingFormat` enum, and the `AddListingController extends ChangeNotifier` class
    - Define `SelectedImage({ required File file, required String previewPath })`
    - Define `enum ListingFormat { fixedPrice, auction, liveSession }`
    - Declare all state fields: `images`, `nameCtrl`, `descCtrl`, `priceCtrl`, `startBidCtrl`, `brandCtrl`, `sizeCtrl`, `colorCtrl`, `locationCtrl`, `selectedCategory`, `selectedCondition`, `selectedFormat`, `auctionDurationDays`, `bidIncrement`, `isLoading`, `uploadStatusMessage`, `fieldErrors`
    - Constructor accepts `SupabaseService supabase` and `AuthProvider auth` as required parameters
    - Override `dispose()` to dispose all `TextEditingController` instances
    - _Requirements: 10.1, 10.5_

  - [x] 1.2 Implement private enum-mapping helpers `_conditionToDb` and `_formatToDb`
    - `_conditionToDb`: maps `newWithTags→'new'`, `likeNew→'like_new'`, `good→'good'`, `fair→'fair'`
    - `_formatToDb`: maps `fixedPrice→'fixed_price'`, `auction→'auction'`, `liveSession→'live_session'`
    - _Requirements: 5.2, 6.5_

  - [x] 1.3 Write property tests for enum mapping helpers (Properties 7 & 8)
    - **Property 7: Condition mapping is bijective and complete**
    - **Validates: Requirements 5.2**
    - **Property 8: Listing format mapping is bijective and complete**
    - **Validates: Requirements 6.5**
    - Create `test/features/seller/add_listing_controller_test.dart`; for each enum value assert the helper returns a non-null, non-empty, distinct DB string

- [ ] 2. Implement field change handlers and reactive error clearing
  - [x] 2.1 Add `onNameChanged`, `onDescChanged`, `onPriceChanged`, `onStartBidChanged`, `selectCategory`, `selectCondition`, `selectFormat`, `selectAuctionDuration`, `selectBidIncrement` methods
    - Each method removes its field key from `fieldErrors` before calling `notifyListeners()`
    - `onDescChanged` and `onNameChanged` also attach `addListener` callbacks on the relevant `TextEditingController` so the character counter rebuilds reactively
    - _Requirements: 3.3, 5.3, 6.1–6.4_

  - [x]* 2.2 Write property test for error clearing on correction (Property 5)
    - **Property 5: Correcting a field immediately clears its error**
    - **Validates: Requirements 3.3, 5.3**
    - Seed `fieldErrors` with all field keys; call each `onXxx`/`selectXxx` with a valid value; assert that field's key is gone and others remain

- [ ] 3. Implement image picker, reorder, and remove methods
  - [x] 3.1 Implement `pickImage(int slotIndex)` and `replaceImage(int slotIndex)`
    - Use `ImagePicker().pickImage(source: ImageSource.gallery)`
    - On success insert/replace a `SelectedImage` in `images` at `slotIndex`; call `notifyListeners()`
    - Accept `ImagePicker` as an optional constructor parameter (defaults to `ImagePicker()`) for testability
    - _Requirements: 2.2, 2.3_

  - [x] 3.2 Implement `removeImage(int slotIndex)` and `reorderImages(int oldIndex, int newIndex)`
    - `removeImage`: remove element at `slotIndex`; call `notifyListeners()`
    - `reorderImages`: apply standard `ReorderableListView` index fix (if `newIndex > oldIndex` decrement by 1), then `insert`/`removeAt`; call `notifyListeners()`
    - _Requirements: 2.3, 2.4_

  - [x]* 3.3 Write property test for image reorder cover invariant (Property 1)
    - **Property 1: Image reorder always places selected cover at index 0**
    - **Validates: Requirements 2.4**
    - Generate random lists of 1–8 `SelectedImage` stubs and valid (oldIndex, newIndex) pairs; assert `images[0]` is the item that was dragged to position 0

- [x] 4. Implement `_validateForPost`
  - [x] 4.1 Implement `_validateForPost()` — returns `bool`, populates `fieldErrors` for: empty images, blank/overlong name, blank/overlong description, missing category, missing condition, invalid price
    - Name: 1–100 chars; description: 1–500 chars; price: parseable double > 0
    - Clear `fieldErrors` before each full validation pass then re-populate only the failing fields
    - _Requirements: 3.1, 3.2, 3.4, 3.5, 3.6_

  - [x]* 4.2 Write property test for post validation completeness (Property 4)
    - **Property 4: Post-listing validation rejects exactly the invalid fields**
    - **Validates: Requirements 3.1, 3.2**
    - Generate random combinations of valid/invalid field values; call `_validateForPost()`; assert `fieldErrors.keys` equals the set of invalid field names

- [x] 5. Implement Supabase helpers: category resolution and image upload/cleanup
  - [x] 5.1 Implement `_resolveCategoryId(ProductCategory category)` — queries `categories` table where `category_name == category.label`; returns the UUID string; throws if no match; sets `fieldErrors['category']` on miss
    - _Requirements: 4.2, 4.3_

  - [x] 5.2 Implement `_uploadImages(String sellerId, String productId)` — uploads each `SelectedImage` file to path `{sellerId}/{productId}/{displayOrder}.jpg` in the `product-images` bucket; updates `uploadStatusMessage` as `"Uploading images… (N/${images.length})"` before each upload; returns list of public URLs
    - _Requirements: 2.6, 9.2, 9.3_

  - [x] 5.3 Implement `_cleanupImages(String sellerId, String productId, int uploadedCount)` — calls `storage.from('product-images').remove(paths)` for each successfully uploaded path index 0..uploadedCount-1
    - _Requirements: 2.8_

  - [x]* 5.4 Write property test for upload path pattern (Property 2)
    - **Property 2: Upload path conforms to expected pattern for all images**
    - **Validates: Requirements 2.6**
    - Generate random seller UUID, product UUID, and image count 1–8; assert each computed path matches `^[0-9a-f-]+/[0-9a-f-]+/[0-7]\.jpg$`

- [x] 6. Implement `postListing` public method
  - [x] 6.1 Implement `postListing(BuildContext context)`
    - Check `auth.user?.id`; return with error snackbar if null
    - Call `_validateForPost()`; return early if invalid
    - Set `isLoading = true`, `notifyListeners()`
    - Generate `productId = const Uuid().v4()`
    - Resolve category ID via `_resolveCategoryId`
    - Insert product row into `products` table with all mapped fields and `status = 'active'`
    - Call `_uploadImages`; on failure call `_cleanupImages` and surface error snackbar; set `isLoading = false`
    - Insert `product_images` rows (one per image: `is_primary = index == 0`, `display_order = index`)
    - Set `uploadStatusMessage = 'Saving listing…'`; call `notifyListeners()`
    - On full success: set `isLoading = false`; navigate to `RouteNames.sellerHome`; show "Listing published!" snackbar
    - On any Supabase exception: set `isLoading = false`; re-enable button; show error snackbar
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5, 7.6_

  - [x]* 6.2 Write property test for DB insert payload correctness (Property 9)
    - **Property 9: Post listing maps all form fields correctly into the DB insert**
    - **Validates: Requirements 7.2**
    - Mock Supabase to capture insert payload; generate random valid form inputs; assert `status`, `seller_id`, `name`, `condition`, `listing_type`, and `price` fields match expected mappings

  - [x]* 6.3 Write property test for Supabase failure resets loading state (Property 10)
    - **Property 10: Supabase failure resets loading state and re-enables button**
    - **Validates: Requirements 7.5**
    - Mock Supabase to throw for any valid form state; assert `isLoading == false` after call resolves

  - [x]* 6.4 Write property test for product_images row correctness (Property 3)
    - **Property 3: product_images rows are correct for any image list**
    - **Validates: Requirements 2.7**
    - Generate random lists of 1–8 images with mocked upload URLs; assert exactly one `is_primary=true` at index 0, `display_order` equals list index, no duplicates

  - [x]* 6.5 Write property test for upload status message progression (Property 11)
    - **Property 11: Upload status message updates for each image in the sequence**
    - **Validates: Requirements 8.3**
    - Generate N images (1–8); mock sequential uploads; collect all `uploadStatusMessage` values emitted; assert at least N distinct non-empty values before the final "Saving listing…"

- [x] 7. Checkpoint — controller complete
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Register `AddListingController` in the Provider tree and replace the screen
  - [x] 8.1 Modify the `addListing` route in `lib/core/routes/app_router.dart` to wrap `AddListingScreen` with a `ChangeNotifierProvider<AddListingController>` at route level
    - Add import for `AddListingController`
    - Pass `SupabaseService` and `AuthProvider` from the outer scope into the controller constructor (they are already in the widget tree as `Provider.of`)
    - _Requirements: 10.1, 10.3_

  - [x] 8.2 Replace the full contents of `lib/features/seller/presentation/screens/add_listing_screen.dart` with a `StatelessWidget` that:
    - Uses `context.watch<AddListingController>()` for reactive rebuilds
    - Renders a `CustomScrollView` with a `SliverAppBar` (title "Add Listing", back button that calls `context.pop()`) and a single `SliverList` containing all form sections in spec order: photos strip, name, description, category, condition, brand, size, color, selling format, price/auction fields, location
    - Renders a persistent `BottomAppBar` with a "Post Listing" (primary) button; disabled (`onPressed: null`) when `controller.isLoading == true`
    - Shows a `LinearProgressIndicator` + `uploadStatusMessage` text overlay at the top of the screen while `isLoading == true`
    - Contains no `TextEditingController` declarations, no validation logic, and no Supabase imports
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 8.1, 8.2, 9.2, 9.3_

  - [x] 8.3 Implement the photos section widget inside `add_listing_screen.dart`
    - Horizontal strip of exactly 8 slots; slot 0 labelled "Cover", slots 1–7 labelled sequentially
    - Empty slot tap → `controller.pickImage(index)`
    - Filled slot tap → `showModalBottomSheet` with "Replace" (`controller.replaceImage(index)`) and "Remove" (`controller.removeImage(index)`) options
    - Slots are wrapped in a `ReorderableListView` (horizontal) so long-press drag calls `controller.reorderImages(oldIndex, newIndex)`
    - Display `controller.fieldErrors['images']` beneath the strip when present
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5_

  - [x] 8.4 Implement category bottom sheet and condition chip row in the screen
    - Category: tappable field opens a bottom sheet listing all `ProductCategory.values`; selection calls `controller.selectCategory(c)`; show `fieldErrors['category']` beneath the field
    - Condition: horizontal `Wrap` of `ChoiceChip` for all `ProductCondition.values`; tap calls `controller.selectCondition(c)`; show `fieldErrors['condition']` beneath
    - Description field shows a live character counter `"${controller.descCtrl.text.length} / 500"` below the text field
    - _Requirements: 4.1, 5.1, 3.5_

  - [x] 8.5 Implement selling format cards and conditional price/auction fields in the screen
    - Three format cards: Fixed Price, Auction, Live Session; tap calls `controller.selectFormat(f)`
    - Show price field only when `selectedFormat != auction`
    - Show starting bid + duration picker + bid increment fields only when `selectedFormat == auction`
    - Show `fieldErrors['price']` beneath the active price input
    - Duration picker: bottom sheet with options `[1, 3, 5, 7]` days → `controller.selectAuctionDuration(d)`
    - Bid increment picker: bottom sheet with options `[10, 20, 50, 100]` → `controller.selectBidIncrement(v)`
    - _Requirements: 6.1, 6.2, 6.3, 6.4_

- [x] 9. Write widget tests for `AddListingScreen`
  - [x]* 9.1 Write unit tests for screen structure and field display
    - Verify `CustomScrollView` is present (no `PageView`); action button visible; `LinearProgressIndicator` hidden when `isLoading == false`, visible when `true`; button disabled when `isLoading == true`
    - _Requirements: 1.1, 1.4, 8.1_

  - [x]* 9.2 Write unit tests for photos section behaviour
    - Exactly 8 slots rendered; empty slot tap triggers `pickImage`; filled slot shows action sheet with Replace/Remove; `fieldErrors['images']` message appears when set
    - _Requirements: 2.1, 2.2, 2.3, 2.5_

  - [x]* 9.3 Write unit tests for format-conditional field visibility
    - Fixed Price → price field visible, auction fields hidden; Auction → auction fields visible, price field hidden; Live Session → price field visible, auction fields hidden
    - _Requirements: 6.2, 6.3, 6.4_

  - [ ]* 9.4 Write property test for character counter accuracy (Property 6)
    - **Property 6: Character counter reflects actual description length**
    - **Validates: Requirements 3.5**
    - Generate random strings of length 0–600; set as `descCtrl.text`; assert rendered counter text equals `"${str.length} / 500"`

- [x] 10. Final checkpoint — Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- `package:fast_check` or `package:glados` should be added to `dev_dependencies` before running property tests; check with the user if neither is present
- Each controller test should mock `SupabaseService` and `AuthProvider` using `mockito` or `mocktail` (add to `dev_dependencies` as needed)
- Image picker must be injected as a constructor parameter on `AddListingController` for testability (see Task 3.1)
- `SellingType.both` (present in the old screen and `enums.dart`) is NOT used by the new controller; the new `ListingFormat` enum is internal to the controller file; the old `SellingType` enum is preserved for other parts of the app
- The existing `ThriftTextField`, `ThriftCard`, `ThriftButton`, `ThriftBottomSheet`, and `showThriftSnackBar` helpers from `lib/widgets/thrift_widgets.dart` should be reused in the new screen

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "3.1", "3.2"] },
    { "id": 2, "tasks": ["1.3", "2.2", "3.3", "4.1"] },
    { "id": 3, "tasks": ["4.2", "5.1", "5.2", "5.3"] },
    { "id": 4, "tasks": ["5.4", "6.1"] },
    { "id": 5, "tasks": ["6.2", "6.3", "6.4", "6.5", "8.1"] },
    { "id": 6, "tasks": ["8.2"] },
    { "id": 7, "tasks": ["8.3", "8.4", "8.5"] },
    { "id": 8, "tasks": ["9.1", "9.2", "9.3", "9.4"] }
  ]
}
```
