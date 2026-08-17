# Requirements Document

## Introduction

The **Create Product Listing** feature allows authenticated sellers on ThriftLine to create a new product listing from a single, vertically scrollable form. The seller fills in product details (name, description, category, condition, price, etc.), selects a selling format (fixed price, auction, or live session), uploads real device photos to Supabase Storage, and publishes the listing. On success the listing is saved to the `products` and `product_images` Supabase tables and the seller is returned to their dashboard.

This feature replaces the existing mock multi-step paged form (`add_listing_screen.dart`) with a properly implemented single-scroll screen backed by a dedicated MVC controller. All Supabase I/O lives in the controller; the screen is pure UI.

## Glossary

- **AddListingController**: The `ChangeNotifier` controller in `lib/features/seller/controllers/add_listing_controller.dart` that owns all state, validation, and Supabase I/O for the listing creation flow.
- **AddListingScreen**: The Flutter screen widget in `lib/features/seller/presentation/screens/add_listing_screen.dart` that presents the scrollable form and consumes `AddListingController`.
- **ProductImage**: A local representation of an image file selected from the device before upload (holds a `File` reference and an optional preview URL).
- **SupabaseService**: The existing service class at `lib/core/services/supabase_service.dart` that wraps the Supabase client.
- **product-images bucket**: The public Supabase Storage bucket named `product-images` where product photo files are uploaded.
- **products table**: The Supabase PostgreSQL table that stores product metadata (name, price, condition, category_id, seller_id, listing_type, status, etc.).
- **product_images table**: The Supabase PostgreSQL table that stores image URLs linked to a product (image_id, image_url, product_id, is_primary, display_order).
- **categories table**: The Supabase PostgreSQL table with `category_id` and `category_name` columns used to resolve a `ProductCategory` enum value to its UUID.
- **listing_type_enum**: DB enum with values `fixed_price`, `auction`, `live_session`.
- **product_condition_enum**: DB enum with values `new`, `like_new`, `good`, `fair`, `poor`.
- **product_status_enum**: DB enum with values `active`, `sold`, `removed`, `draft`.
- **Primary image**: The first image in the ordered list; stored with `is_primary = true` and `display_order = 0` in `product_images`.

---

## Requirements

### Requirement 1: Single-Scroll Listing Form

**User Story:** As a seller, I want to fill out all listing details in one continuous scrollable screen, so that I can create a listing without navigating through multiple wizard steps.

#### Acceptance Criteria

1. WHEN a seller navigates to `RouteNames.addListing`, THE AddListingScreen SHALL render all listing fields in a single `CustomScrollView` with no pagination or step-based navigation.
2. THE AddListingScreen SHALL present fields in this order: photos section, product name, description, category, condition, brand (optional), size (optional), color (optional), selling format, price / auction details, item location (optional).
3. WHEN the seller taps the back button or system back gesture, THE AddListingScreen SHALL pop back to the previous route without saving any data.
4. THE AddListingScreen SHALL display a persistent bottom action bar containing a "Post Listing" button.

---

### Requirement 2: Image Selection and Upload

**User Story:** As a seller, I want to upload real photos from my device, so that buyers can see accurate images of my item.

#### Acceptance Criteria

1. THE AddListingScreen SHALL display a horizontal photo strip that shows up to 8 image slots; the first slot is labelled "Cover" and the remaining seven are labelled sequentially.
2. WHEN a seller taps an empty image slot, THE AddListingController SHALL invoke the device image picker (`ImagePicker.pickImage`) with `ImageSource.gallery`.
3. WHEN a seller taps a filled image slot, THE AddListingScreen SHALL present an action sheet offering "Replace" (opens picker) and "Remove" options.
4. WHEN the seller reorders images via long-press drag, THE AddListingController SHALL update the internal image order so the item at index 0 remains the cover.
5. IF the seller attempts to post a listing with zero images selected, THEN THE AddListingController SHALL set a validation error message and THE AddListingScreen SHALL display it beneath the photos section.
6. WHEN the listing is submitted, THE AddListingController SHALL upload each selected image file to the `product-images` Supabase Storage bucket using the path `{seller_id}/{product_id}/{display_order}.jpg`.
7. WHEN all images are uploaded successfully, THE AddListingController SHALL insert one row per image into the `product_images` table with the public image URL, `is_primary` (true for index 0, false for others), and `display_order` matching its index.
8. IF any image upload fails, THEN THE AddListingController SHALL abort the listing creation, delete any already-uploaded files for that product from storage, and surface an error message to the seller.

---

### Requirement 3: Required Field Validation

**User Story:** As a seller, I want the form to tell me what I missed, so that my listing has all the information buyers need.

#### Acceptance Criteria

1. THE AddListingController SHALL treat the following fields as required: at least one image, product name (1–100 characters), description (1–500 characters), category, condition, and a valid price.
2. WHEN the seller taps "Post Listing" with one or more required fields empty or invalid, THE AddListingController SHALL populate a field-level error map and THE AddListingScreen SHALL display the error message directly beneath each invalid field.
3. WHEN a previously invalid field is corrected, THE AddListingController SHALL clear that field's error message immediately without waiting for resubmission.
4. IF the product name exceeds 100 characters, THEN THE AddListingController SHALL set an error message for the name field.
5. IF the description exceeds 500 characters, THEN THE AddListingController SHALL set an error message for the description field; THE AddListingScreen SHALL show a live character counter (e.g. "320 / 500").
6. IF the price field contains a non-numeric value or a value less than or equal to zero, THEN THE AddListingController SHALL set an error message for the price field.

---

### Requirement 4: Category Resolution

**User Story:** As a seller, I want to select a category from the existing app categories, so that my listing is properly classified.

#### Acceptance Criteria

1. THE AddListingScreen SHALL display a tappable category field that opens a bottom sheet listing all values from the `ProductCategory` enum.
2. WHEN the seller selects a category, THE AddListingController SHALL store the selected `ProductCategory` value and resolve it to its `category_id` UUID by querying the `categories` table where `category_name` matches the enum's `label`.
3. IF the `categories` table lookup returns no match for a given `ProductCategory` label, THEN THE AddListingController SHALL set an error message indicating the category is unavailable and prevent submission.

---

### Requirement 5: Condition and Enum Mapping

**User Story:** As a seller, I want to select the condition of my item, so that buyers have accurate expectations.

#### Acceptance Criteria

1. THE AddListingScreen SHALL display condition options as a horizontal chip row using all values of the `ProductCondition` enum.
2. THE AddListingController SHALL map `ProductCondition` values to `product_condition_enum` DB values as follows: `newWithTags` → `new`, `likeNew` → `like_new`, `good` → `good`, `fair` → `fair`. The `poor` DB value is NOT used in the local enum and SHALL be excluded from the UI.
3. WHEN a condition chip is selected, THE AddListingController SHALL update the selected condition and clear any existing condition validation error.

---

### Requirement 6: Selling Format Selection

**User Story:** As a seller, I want to choose how my item is sold — fixed price, auction, or live session — so that I can reach buyers in the way that works best for me.

#### Acceptance Criteria

1. THE AddListingScreen SHALL display three format cards: "Fixed Price" (`listing_type_enum = fixed_price`), "Auction" (`listing_type_enum = auction`), and "Live Session" (`listing_type_enum = live_session`).
2. WHEN the seller selects "Fixed Price", THE AddListingScreen SHALL show a price input field and hide auction-specific fields.
3. WHEN the seller selects "Auction", THE AddListingScreen SHALL show starting bid, auction duration (days picker: 1, 3, 5, 7), and minimum bid increment fields; the fixed price field SHALL be hidden.
4. WHEN the seller selects "Live Session", THE AddListingScreen SHALL show only the price field (starting price for the session) and hide auction-specific fields.
5. THE AddListingController SHALL map local `SellingType` values to `listing_type_enum` as: `fixedPrice` → `fixed_price`, `auction` → `auction`; `live_session` has no local enum counterpart and is driven purely by the UI selection.

---

### Requirement 7: Post (Publish) Listing

**User Story:** As a seller, I want to publish my listing immediately, so that buyers can discover and purchase my item.

#### Acceptance Criteria

1. WHEN the seller taps "Post Listing" and all required fields are valid, THE AddListingController SHALL set `isLoading = true` and disable the action button to prevent double-submission.
2. THE AddListingController SHALL insert a row into the `products` table with `status = active`, `seller_id` from the authenticated user's UUID, `category_id` resolved from the `categories` table, and all other form fields mapped to their corresponding DB columns.
3. WHEN the product row is inserted, THE AddListingController SHALL upload images and insert rows into `product_images` as specified in Requirement 2.
4. WHEN the listing is published successfully, THE AddListingController SHALL navigate to `RouteNames.sellerHome` and display a "Listing published!" success snack bar.
5. IF the Supabase insert or upload operation fails, THEN THE AddListingController SHALL set `isLoading = false`, re-enable the button, and display an error snack bar with the failure reason.
6. THE AddListingController SHALL set `seller_id` from `AuthProvider.user.id` and SHALL NOT allow listing creation when the user is not authenticated.

---

### Requirement 8: Upload Progress Feedback

**User Story:** As a seller, I want to see upload progress while my listing is being submitted, so that I know the app is working and haven't lost connectivity.

#### Acceptance Criteria

1. WHILE `AddListingController.isLoading` is `true`, THE AddListingScreen SHALL display a linear progress indicator at the top of the screen.
2. WHILE `AddListingController.isLoading` is `true`, THE AddListingScreen SHALL display descriptive status text below the progress indicator (e.g., "Uploading images… (2/5)", "Saving listing…").
3. THE AddListingController SHALL expose an `uploadStatusMessage` string that updates as each image is uploaded and as the DB rows are inserted.

---

### Requirement 9: MVC Architecture Compliance

**User Story:** As a developer, I want the feature to follow the project's feature MVC pattern, so that the codebase stays consistent and maintainable.

#### Acceptance Criteria

1. THE AddListingController SHALL reside at `lib/features/seller/controllers/add_listing_controller.dart` and extend `ChangeNotifier`.
2. THE AddListingScreen SHALL reside at `lib/features/seller/presentation/screens/add_listing_screen.dart` and contain no direct Supabase calls.
3. THE AddListingScreen SHALL access `AddListingController` exclusively through `context.read<AddListingController>()` or `context.watch<AddListingController>()`.
4. All Supabase database queries, storage uploads, and enum mappings SHALL reside in `AddListingController` or in private helper methods called by it.
5. THE AddListingController SHALL use `SupabaseService` (injected or accessed via `Supabase.instance.client`) for all database and storage operations.
6. Global models (`ProductModel`, enums from `lib/models/enums.dart`) SHALL be reused as-is; the feature SHALL NOT define duplicate model classes.
