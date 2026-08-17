# Design Document: Create Product Listing

## Overview

The Create Product Listing feature replaces the existing five-step `PageView` mock form in `add_listing_screen.dart` with a real, single-scroll form backed by a dedicated `AddListingController`. The controller owns all state, validation logic, image picker interactions, and Supabase I/O. The screen is pure UI that observes the controller via `Provider`.

On submission the controller:
1. Validates all required fields.
2. Inserts a row in the `products` table.
3. Uploads images to the `product-images` Storage bucket.
4. Inserts rows in the `product_images` table.
5. Navigates to `RouteNames.sellerHome` on success.

---

## Architecture

The feature follows the project's **feature/MVC** pattern using `ChangeNotifier` + Provider.

```
lib/features/seller/
├── controllers/
│   └── add_listing_controller.dart   ← NEW (ChangeNotifier, all logic)
└── presentation/
    └── screens/
        └── add_listing_screen.dart   ← REPLACE (pure UI, no Supabase)
```

### Data Flow

```
AddListingScreen (UI)
    │  context.watch<AddListingController>()
    ▼
AddListingController (ChangeNotifier)
    │  SupabaseService / Supabase.instance.client
    ▼
Supabase Backend
    ├── products table
    ├── product_images table
    └── product-images Storage bucket
```

The screen reads state from the controller and forwards user actions (field changes, button taps, image picks) to controller methods. The controller calls `notifyListeners()` after any state mutation so the screen rebuilds automatically.

---

## Components and Interfaces

### AddListingController

```dart
class AddListingController extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────
  List<SelectedImage> images;          // up to 8, index 0 = cover
  TextEditingController nameCtrl;
  TextEditingController descCtrl;
  TextEditingController priceCtrl;
  TextEditingController startBidCtrl;
  TextEditingController brandCtrl;
  TextEditingController sizeCtrl;
  TextEditingController colorCtrl;
  TextEditingController locationCtrl;

  ProductCategory? selectedCategory;
  ProductCondition? selectedCondition;
  ListingFormat selectedFormat;         // fixedPrice | auction | liveSession
  int auctionDurationDays;              // 1, 3, 5, 7
  double bidIncrement;                  // 10, 20, 50, 100

  bool isLoading;
  String uploadStatusMessage;
  Map<String, String> fieldErrors;      // key = field name, value = error text

  // ── Public methods ─────────────────────────────────────────────────────
  Future<void> pickImage(int slotIndex);
  Future<void> replaceImage(int slotIndex);
  void removeImage(int slotIndex);
  void reorderImages(int oldIndex, int newIndex);

  void onNameChanged(String value);
  void onDescChanged(String value);
  void onPriceChanged(String value);
  void onStartBidChanged(String value);
  void selectCategory(ProductCategory category);
  void selectCondition(ProductCondition condition);
  void selectFormat(ListingFormat format);
  void selectAuctionDuration(int days);
  void selectBidIncrement(double increment);

  Future<void> postListing(BuildContext context);

  // ── Private helpers ────────────────────────────────────────────────────
  bool _validateForPost();
  Future<String> _resolveCategoryId(ProductCategory category);
  Future<List<String>> _uploadImages(String sellerId, String productId);
  Future<void> _cleanupImages(String sellerId, String productId, int uploadedCount);
  String _conditionToDb(ProductCondition condition);
  String _formatToDb(ListingFormat format);
}
```

#### SelectedImage model (local, internal to controller file)

```dart
class SelectedImage {
  final File file;
  final String previewPath;   // local file path for Image.file()

  const SelectedImage({required this.file, required this.previewPath});
}
```

#### ListingFormat enum (local, not a DB enum — maps to listing_type_enum)

```dart
enum ListingFormat { fixedPrice, auction, liveSession }
```

### AddListingScreen

A `StatelessWidget` that uses `context.watch<AddListingController>()` for reactive rebuilds. It renders:

- `CustomScrollView` with a single `SliverList` containing all form sections
- A pinned `SliverAppBar` with the screen title and back button
- A persistent `BottomAppBar` holding a "Post Listing" (primary) button
- A `LinearProgressIndicator` + status text overlay while `isLoading == true`

The screen contains **no** `TextEditingController` declarations, **no** validation logic, and **no** Supabase imports.

---

## Data Models

### products table insert payload

| Column         | Source                                   | Type                   |
|----------------|------------------------------------------|------------------------|
| `product_id`   | `const Uuid().v4()`                      | uuid                   |
| `seller_id`    | `AuthProvider.user.id`                   | uuid                   |
| `name`         | `nameCtrl.text.trim()`                   | text                   |
| `description`  | `descCtrl.text.trim()`                   | text                   |
| `price`        | `double.parse(priceCtrl.text)`           | numeric                |
| `condition`    | `_conditionToDb(selectedCondition!)`     | product_condition_enum |
| `status`       | `'active'`                               | product_status_enum    |
| `listing_type` | `_formatToDb(selectedFormat)`            | listing_type_enum      |
| `category_id`  | resolved via `categories` table lookup   | uuid                   |
| `size`         | `sizeCtrl.text` (nullable)               | text                   |
| `brand`        | `brandCtrl.text` (nullable)              | text                   |
| `color`        | `colorCtrl.text` (nullable)              | text                   |
| `location`     | `locationCtrl.text` (nullable)           | text                   |
| `boosted`      | `false`                                  | boolean                |
| `created_at`   | server default (`now()`)                 | timestamptz            |

For auction listings, `price` stores the starting bid amount.

### product_images table insert payload (one row per image)

| Column          | Source                                                | Type    |
|-----------------|-------------------------------------------------------|---------|
| `product_id`    | product UUID from the insert above                    | uuid    |
| `image_url`     | public URL from Storage after upload                  | text    |
| `is_primary`    | `index == 0`                                          | boolean |
| `display_order` | list index (0-based)                                  | integer |

### Storage upload path

```
product-images/{seller_id}/{product_id}/{display_order}.jpg
```

Public URL retrieved via:
```dart
supabase.storage.from('product-images').getPublicUrl(path)
```

### Enum mappings

**ProductCondition → product_condition_enum**

| Dart enum value  | DB value   |
|------------------|------------|
| `newWithTags`    | `new`      |
| `likeNew`        | `like_new` |
| `good`           | `good`     |
| `fair`           | `fair`     |

`poor` is a valid DB enum value but is NOT exposed in the UI (per Requirement 5.2).

**ListingFormat → listing_type_enum**

| Dart enum value | DB value      |
|-----------------|---------------|
| `fixedPrice`    | `fixed_price` |
| `auction`       | `auction`     |
| `liveSession`   | `live_session`|

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Image reorder always places selected cover at index 0

*For any* ordered list of images and any valid drag reorder operation (old index → new index), after the reorder the image at index 0 in the resulting list is the item that occupied `newIndex == 0`'s slot — and specifically, `images[0]` is the one the user dragged to the front.

**Validates: Requirements 2.4**

---

### Property 2: Upload path conforms to expected pattern for all images

*For any* seller UUID, product UUID, and list of 1–8 `SelectedImage` values, the storage path passed to each upload call SHALL equal `"{seller_id}/{product_id}/{display_order}.jpg"` where `display_order` is the image's index in the list.

**Validates: Requirements 2.6**

---

### Property 3: product_images rows are correct for any image list

*For any* list of 1–8 uploaded images, the resulting `product_images` insert rows SHALL satisfy:
- Exactly one row has `is_primary = true`, and it corresponds to index 0.
- Every row's `display_order` matches its index in the list.
- No two rows share the same `display_order`.

**Validates: Requirements 2.7**

---

### Property 4: Post-listing validation rejects exactly the invalid fields

*For any* combination of form field values (name, description, category, condition, price, images), calling `postListing` with one or more required fields empty or invalid SHALL result in `fieldErrors` containing a non-empty error string for each invalid field and no error for fields that are valid.

**Validates: Requirements 3.1, 3.2**

---

### Property 5: Correcting a field immediately clears its error

*For any* field that currently has a non-null entry in `fieldErrors`, providing a valid value for that field via its corresponding `onXxxChanged` or `selectXxx` method SHALL remove that field's key from `fieldErrors` immediately (without resubmission).

**Validates: Requirements 3.3, 5.3**

---

### Property 6: Character counter reflects actual description length

*For any* string assigned to `descCtrl`, the character counter text rendered by the screen SHALL equal `"${text.length} / 500"`.

**Validates: Requirements 3.5**

---

### Property 7: Condition mapping is bijective and complete

*For every* `ProductCondition` enum value, `_conditionToDb()` SHALL return a non-empty string that is a valid `product_condition_enum` DB value, and no two distinct enum values SHALL map to the same DB string.

**Validates: Requirements 5.2**

---

### Property 8: Listing format mapping is bijective and complete

*For every* `ListingFormat` enum value, `_formatToDb()` SHALL return a non-empty string that is a valid `listing_type_enum` DB value, and no two distinct enum values SHALL map to the same DB string.

**Validates: Requirements 6.5**

---

### Property 9: Post listing maps all form fields correctly into the DB insert

*For any* valid form state (all required fields filled), the `Map<String, dynamic>` passed to the `products` table insert SHALL contain:
- `status = 'active'`
- `seller_id` equal to the authenticated user's UUID
- `name` equal to `nameCtrl.text.trim()`
- `condition` equal to `_conditionToDb(selectedCondition!)`
- `listing_type` equal to `_formatToDb(selectedFormat)`
- `price` equal to the parsed numeric value of `priceCtrl.text`

**Validates: Requirements 7.2**

---

### Property 10: Supabase failure resets loading state and re-enables button

*For any* valid form state, if the Supabase insert or storage upload throws an exception, then after the exception is caught `isLoading` SHALL be `false` and the action button SHALL be enabled (its `onPressed` callback SHALL be non-null).

**Validates: Requirements 7.5**

---

### Property 11: Upload status message updates for each image in the sequence

*For any* list of N images (1 ≤ N ≤ 8), during the upload sequence, `uploadStatusMessage` SHALL transition through at least N distinct non-empty string values — one per image upload — before the final "Saving listing…" message.

**Validates: Requirements 8.3**

---

## Error Handling

### Validation errors

Field-level errors are stored in `Map<String, String> fieldErrors` with keys matching field names (e.g., `'name'`, `'description'`, `'price'`, `'images'`, `'category'`, `'condition'`). The screen reads `controller.fieldErrors['fieldName']` and passes it as the `error` parameter to `ThriftTextField` or renders it as a `Text(style: errorStyle)` below non-text fields.

Errors are cleared reactively: each `onXxxChanged` / `selectXxx` method removes its corresponding key from `fieldErrors` before calling `notifyListeners()`.

### Category resolution failure

If the `categories` table returns no row matching the selected `ProductCategory.label`, the controller sets `fieldErrors['category'] = 'Category unavailable. Please try again.'` and returns early without inserting anything.

### Image upload failure

If any `storage.from('product-images').upload(...)` call throws:
1. The upload loop aborts immediately.
2. `_cleanupImages(sellerId, productId, uploadedCount)` removes already-uploaded files from storage using a list-and-delete pattern.
3. `isLoading = false` and `notifyListeners()`.
4. `showThriftSnackBar(context, errorMessage, isError: true)` surfaces the failure.

No partial `product_images` rows are ever inserted because image inserts happen only after all uploads succeed.

### Supabase insert failure

If the `products` table insert throws, the controller catches the error, sets `isLoading = false`, re-enables buttons, and shows an error snackbar. No images are uploaded because the product UUID doesn't exist yet; the controller generates the UUID locally, inserts the product row first, then uploads.

### Unauthenticated state

`postListing` checks `AuthProvider.user?.id` at entry. If it is null, the controller shows an error snackbar and returns immediately without making any Supabase calls.

---

## Testing Strategy

### Unit Tests (example-based)

Focus on concrete, deterministic scenarios:

- **Screen structure**: Widget test verifying `CustomScrollView` present, no `PageView`, action button visible.
- **Field ordering**: Widget test confirming the rendered widget sequence matches the spec.
- **Photo strip**: Widget test asserting exactly 8 slots render.
- **Format card conditional fields**: Three widget tests (one per format) verifying correct field show/hide behavior.
- **Empty slot picker invocation**: Mock `ImagePicker`, tap empty slot, assert `pickImage` called with `ImageSource.gallery`.
- **Filled slot action sheet**: Tap filled slot, assert "Replace" and "Remove" options appear.
- **Category bottom sheet contents**: Open category picker, verify all `ProductCategory.values` listed.
- **Post listing success**: Mock Supabase insert succeeds → verify navigation to `sellerHome` and success snackbar.
- **Post listing failure**: Mock Supabase throws → verify error snackbar, no navigation.
- **Unauthenticated block**: Null `AuthProvider.user` → verify submission blocked with error.
- **Loading state**: `isLoading = true` → verify `LinearProgressIndicator` visible, button disabled.
- **Upload failure cleanup**: Mock upload fails at index N → verify `_cleanupImages` called for indices 0..N-1.
- **Category lookup miss**: Mock empty categories result → verify category error set, no insert.

### Property-Based Tests (using `package:fast_check` or `package:glados`)

Each property test runs a minimum of **100 iterations** with randomly generated inputs. Each test is tagged with the corresponding property reference.

**Property 1 — Image reorder cover invariant**
Generate a list of 1–8 `SelectedImage` objects and a valid (oldIndex, newIndex) pair. Apply `reorderImages(oldIndex, newIndex)`. Assert `images[0]` is the item that was at `newIndex` after a conceptual `ReorderableListView` swap.
`// Feature: create-product-listing, Property 1: image reorder always places selected cover at index 0`

**Property 2 — Upload path pattern**
Generate random UUIDs for seller and product and a random image count 1–8. Verify each computed path string matches the regex `^[0-9a-f-]+/[0-9a-f-]+/[0-7]\.jpg$`.
`// Feature: create-product-listing, Property 2: upload path conforms to expected pattern`

**Property 3 — product_images row correctness**
Generate random lists of 1–8 images; mock successful uploads returning fake URLs. Verify resulting row list: one `is_primary=true` at index 0, all `display_order` values equal list indices, no duplicates.
`// Feature: create-product-listing, Property 3: product_images rows are correct for any image list`

**Property 4 — Post validation rejects exactly invalid fields**
Generate `FormState` with random combinations of empty/invalid fields. Call the validation method. Assert `fieldErrors.keys` == set of invalid field names.
`// Feature: create-product-listing, Property 4: post-listing validation rejects exactly the invalid fields`

**Property 5 — Error clearing on correction**
Start with a controller in an errored state (all fields invalid). For each field, provide a valid value. Assert that field's error is cleared; others remain until corrected.
`// Feature: create-product-listing, Property 5: correcting a field immediately clears its error`

**Property 6 — Character counter accuracy**
Generate random strings of length 0–600. Set as description. Assert rendered counter text == `"${str.length} / 500"`.
`// Feature: create-product-listing, Property 6: character counter reflects actual description length`

**Property 7 — Condition mapping completeness**
For each `ProductCondition` value (finite set), assert `_conditionToDb()` returns a non-null, non-empty string, all results are distinct.
`// Feature: create-product-listing, Property 7: condition mapping is bijective and complete`

**Property 8 — Format mapping completeness**
For each `ListingFormat` value, assert `_formatToDb()` returns a non-null, non-empty string, all results are distinct.
`// Feature: create-product-listing, Property 8: listing format mapping is bijective and complete`

**Property 9 — Post listing DB insert payload correctness**
Mock Supabase insert to capture payload; generate random valid form inputs; assert payload fields match expected mappings for all generated inputs.
`// Feature: create-product-listing, Property 9: post listing maps all form fields correctly into the DB insert`

**Property 10 — Supabase failure resets loading state**
Generate any valid form state. Mock Supabase to throw. Assert `isLoading == false` after the call resolves.
`// Feature: create-product-listing, Property 10: Supabase failure resets loading state and re-enables button`

**Property 11 — Upload status message progression**
Generate random lists of N images (1–8). Mock sequential uploads. Capture all `uploadStatusMessage` values emitted via `notifyListeners`. Assert at least N distinct non-empty values before the final message.
`// Feature: create-product-listing, Property 11: upload status message updates for each image in the sequence`

### Integration Notes

- Image picker interactions require a real or mocked `ImagePicker` instance injected into the controller (testability requires the picker to be a constructor parameter or a settable dependency).
- Supabase calls should be abstracted behind the controller's private helpers so tests can mock them with `mockito` or `mocktail`.
- All property tests should avoid real network calls; use mock implementations of `SupabaseService` and `StorageFileApi`.
