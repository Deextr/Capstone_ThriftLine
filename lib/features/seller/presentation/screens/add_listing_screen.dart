import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/add_listing_controller.dart';
import '../widgets/add_listing_form_sections.dart';
import '../widgets/listing_location_section.dart';
import '../widgets/listing_shipping_section.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Screen
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// Single-scroll listing creation screen.
///
/// Pure UI â€” all state and logic live in [AddListingController].
/// Observes the controller via [context.watch] and delegates every action to it.
///
/// Requirements: 1.1, 1.2, 1.3, 1.4, 8.1, 8.2, 9.2, 9.3
class AddListingScreen extends StatelessWidget {
  const AddListingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AddListingController>();

    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          resizeToAvoidBottomInset: true,
          body: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverAppBar(
                pinned: true,
                title: const Text('Add Listing'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.textPrimary,
                elevation: 1,
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingMd,
                  AppConstants.spacingMd,
                  AppConstants.spacingMd,
                  AppConstants.spacingXxl,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    ListingFormSection(
                      title: 'Product photos',
                      subtitle: 'Add up to 3 clear photos. The first is the cover.',
                      child: _PhotosSection(controller: controller),
                    ),
                    ListingFormSection(
                      title: 'Product information',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ThriftTextField(
                            label: 'Product name',
                            hint: 'What are you selling?',
                            controller: controller.nameCtrl,
                            onChanged: controller.onNameChanged,
                            error: controller.fieldErrors['name'],
                          ),
                          const SizedBox(height: AppConstants.spacingMd),
                          _DescriptionField(controller: controller),
                          const SizedBox(height: AppConstants.spacingMd),
                          _CategoryField(controller: controller),
                          const SizedBox(height: AppConstants.spacingMd),
                          _ConditionField(controller: controller),
                        ],
                      ),
                    ),
                    ListingFormSection(
                      title: 'Item details',
                      subtitle: 'Optional — helps buyers find your listing',
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMd),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            ThriftTextField(
                              label: 'Brand',
                              hint: 'Leave blank if unknown',
                              controller: controller.brandCtrl,
                            ),
                            const SizedBox(height: AppConstants.spacingMd),
                            ThriftTextField(
                              label: 'Size',
                              controller: controller.sizeCtrl,
                            ),
                            const SizedBox(height: AppConstants.spacingMd),
                            ThriftTextField(
                              label: 'Color',
                              controller: controller.colorCtrl,
                            ),
                          ],
                        ),
                      ),
                    ),
                    ListingFormSection(
                      title: 'Listing type',
                      subtitle: 'Fixed price sells immediately. Auction accepts bids.',
                      child: _ListingTypeSection(controller: controller),
                    ),
                    ListingFormSection(
                      title: controller.selectedFormat == ListingFormat.auction
                          ? 'Auction pricing'
                          : 'Pricing',
                      child: _PricingSection(controller: controller),
                    ),
                    ListingFormSection(
                      title: 'Item location',
                      subtitle:
                          'Uses your shop barangay from Become a Seller. Buyers never see your street address.',
                      child: ListingLocationSection(
                        showItemLocation: controller.showItemLocation,
                        sellerBarangay: controller.sellerBarangay,
                        onToggle: controller.setShowItemLocation,
                        showHeading: false,
                      ),
                    ),
                    ListingFormSection(
                      title: 'Shipping',
                      subtitle: 'Applied at checkout for this listing.',
                      child: ListingShippingSection(
                        listingFormat: controller.selectedFormat,
                        shippingMode: controller.shippingMode,
                        onModeChanged: controller.setShippingMode,
                        shippingFeeController: controller.shippingFeeCtrl,
                        qtyThresholdController: controller.qtyThresholdCtrl,
                        bidThresholdController: controller.bidThresholdCtrl,
                        startingBidText: controller.startBidCtrl.text,
                        shippingFeeError: controller.fieldErrors['shippingFee'],
                        qtyThresholdError:
                            controller.fieldErrors['qtyThreshold'],
                        bidThresholdError:
                            controller.fieldErrors['bidThreshold'],
                        showHeading: false,
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomAppBar(
            color: AppColors.surface,
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingMd,
                  vertical: AppConstants.spacingSm,
                ),
                child: ThriftButton(
                  label: 'Publish listing',
                  isLoading: controller.isLoading,
                  onPressed: controller.isLoading
                      ? null
                      : () => controller.postListing(context),
                ),
              ),
            ),
          ),
        ),

        if (controller.isLoading)
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Material(
                    color: AppColors.surface,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            controller.uploadStatusMessage.isEmpty
                                ? 'Publishing listing…'
                                : controller.uploadStatusMessage,
                            textAlign: TextAlign.center,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Description field with live character counter
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.controller});

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThriftTextField(
          label: 'Description',
          controller: controller.descCtrl,
          onChanged: controller.onDescChanged,
          maxLines: 4,
          error: controller.fieldErrors['description'],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${controller.descCtrl.text.length} / 150',
            style: AppTypography.caption,
          ),
        ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Category field â€” tappable, opens bottom sheet populated from DB
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CategoryField extends StatelessWidget {
  const _CategoryField({required this.controller});

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    final selectedName = controller.selectedCategoryName;
    final hasError = controller.fieldErrors.containsKey('category');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category',
          style: AppTypography.label.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppConstants.spacingXs),
        InkWell(
          onTap: () => _showCategorySheet(context, controller),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: hasError ? AppColors.error : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.category_outlined,
                  color: AppColors.textHint,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: controller.categoriesLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Text(
                          selectedName ?? 'Select a category',
                          style: AppTypography.body.copyWith(
                            color: selectedName != null
                                ? AppColors.textPrimary
                                : AppColors.textHint,
                          ),
                        ),
                ),
                const Icon(
                  Icons.arrow_drop_down,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              controller.fieldErrors['category']!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  void _showCategorySheet(
    BuildContext context,
    AddListingController controller,
  ) {
    if (controller.categoriesLoading) return;

    ThriftBottomSheet.show(
      context,
      title: 'Select Category',
      child: controller.categories.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(AppConstants.spacingLg),
              child: Center(
                child: Text(
                  'No categories available. Pull down to retry.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: controller.categories.map((cat) {
                final isSelected = controller.selectedCategoryId == cat.id;
                return ListTile(
                  leading: Icon(
                    Icons.sell_outlined,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  title: Text(
                    cat.name,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    controller.selectCategory(cat.id, cat.name);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Condition chip row (filled in task 8.4)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ConditionField extends StatelessWidget {
  const _ConditionField({required this.controller});

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    final hasError = controller.fieldErrors.containsKey('condition');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Condition',
          style: AppTypography.label.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ProductCondition.values.map((c) {
            final isSelected = controller.selectedCondition == c;
            return ChoiceChip(
              label: Text(c.label),
              selected: isSelected,
              selectedColor: AppColors.primaryLight,
              labelStyle: TextStyle(
                color: isSelected
                    ? AppColors.primaryDark
                    : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ),
              onSelected: (_) => controller.selectCondition(c),
            );
          }).toList(),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              controller.fieldErrors['condition']!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Photos strip â€” placeholder, replaced in task 8.3
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({required this.controller});

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    final hasError = controller.fieldErrors.containsKey('images');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: Material(
            color: Colors.transparent,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 3,
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) =>
                  controller.reorderImages(oldIndex, newIndex),
              itemBuilder: (context, index) {
              final isFilled = index < controller.images.length;
              return ReorderableDragStartListener(
                key: ValueKey('slot_$index'),
                index: index,
                child: GestureDetector(
                  onTap: () => isFilled
                      ? _showSlotOptions(context, index)
                      : controller.pickImage(index),
                  child: _ImageSlot(
                    index: index,
                    image: isFilled ? controller.images[index] : null,
                  ),
                ),
              );
              },
            ),
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              controller.fieldErrors['images']!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  void _showSlotOptions(BuildContext context, int index) {
    ThriftBottomSheet.show(
      context,
      title: index == 0 ? 'Cover Photo' : 'Photo ${index + 1}',
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.swap_horiz, color: AppColors.primary),
            title: const Text('Replace'),
            onTap: () {
              Navigator.pop(context);
              controller.replaceImage(index);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.error),
            title: const Text(
              'Remove',
              style: TextStyle(color: AppColors.error),
            ),
            onTap: () {
              Navigator.pop(context);
              controller.removeImage(index);
            },
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Individual image slot widget
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ImageSlot extends StatelessWidget {
  const _ImageSlot({required this.index, required this.image});

  final int index;
  final SelectedImage? image;

  @override
  Widget build(BuildContext context) {
    final isCover = index == 0;
    final label = isCover ? 'Cover' : 'Photo ${index + 1}';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        width: 88,
        height: 88,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          border: Border.all(
            color: image != null ? AppColors.primary : AppColors.border,
            width: image != null ? 2 : 1,
          ),
        ),
        child: image != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(image!.bytes, fit: BoxFit.cover),
                  if (isCover)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: const Text(
                          'Cover',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isCover ? Icons.add_a_photo_outlined : Icons.add,
                    color: AppColors.textHint,
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: AppTypography.caption.copyWith(fontSize: 9),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Selling format cards + conditional price/auction fields (task 8.5)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ListingTypeSection extends StatelessWidget {
  const _ListingTypeSection({required this.controller});

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    return ListingFormatTypeRow(
      selectedFormat: controller.selectedFormat,
      onFormatSelected: controller.selectFormat,
    );
  }
}

class _PricingSection extends StatelessWidget {
  const _PricingSection({required this.controller});

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    final isAuction = controller.selectedFormat == ListingFormat.auction;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isAuction
            ? _AuctionPricingFields(
                key: const ValueKey('auction_pricing'),
                controller: controller,
              )
            : _FixedPricePricingFields(
                key: const ValueKey('fixed_pricing'),
                controller: controller,
              ),
      ),
    );
  }
}

class _FixedPricePricingFields extends StatelessWidget {
  const _FixedPricePricingFields({
    super.key,
    required this.controller,
  });

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThriftTextField(
          label: 'Price',
          hint: 'Amount in pesos',
          controller: controller.priceCtrl,
          onChanged: controller.onPriceChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          error: controller.fieldErrors['price'],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        ThriftTextField(
          label: 'Stock quantity',
          hint: 'How many units you have',
          controller: controller.stockCtrl,
          onChanged: controller.onStockChanged,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          error: controller.fieldErrors['stock'],
        ),
      ],
    );
  }
}

class _AuctionPricingFields extends StatelessWidget {
  const _AuctionPricingFields({
    super.key,
    required this.controller,
  });

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThriftTextField(
          label: 'Starting bid',
          hint: 'Minimum opening bid in pesos',
          controller: controller.startBidCtrl,
          onChanged: controller.onStartBidChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          error: controller.fieldErrors['price'],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        const ListingAuctionQuantityNote(),
        const SizedBox(height: AppConstants.spacingLg),
        Text('Auction duration', style: AppTypography.label),
        const SizedBox(height: 4),
        AuctionDurationSelector(
          selectedDays: controller.auctionDurationDays,
          onDaysSelected: controller.selectAuctionDuration,
          previewEndsAt: controller.previewAuctionEndsAt,
          durationError: controller.fieldErrors['duration'],
        ),
        const SizedBox(height: AppConstants.spacingLg),
        Text('Minimum bid increment', style: AppTypography.label),
        const SizedBox(height: 4),
        BidIncrementSelector(
          selectedIncrement: controller.bidIncrement,
          onIncrementSelected: controller.selectBidIncrement,
          incrementError: controller.fieldErrors['increment'],
        ),
      ],
    );
  }
}

