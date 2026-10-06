import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/add_listing_controller.dart' show ListingFormat;
import '../../controllers/edit_listing_controller.dart';
import '../widgets/add_listing_form_sections.dart';
import '../widgets/listing_location_section.dart';
import '../widgets/listing_shipping_section.dart';

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Screen
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class EditListingScreen extends StatelessWidget {
  const EditListingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditListingController>();

    if (c.initialLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (c.loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Listing')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            child: Text(
              c.loadError!,
              style: AppTypography.body.copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

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
                title: const Text('Edit Listing'),
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
                      subtitle:
                          'Add up to 3 clear photos. The first is the cover.',
                      child: _PhotosSection(c: c),
                    ),
                    ListingFormSection(
                      title: 'Product information',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ThriftTextField(
                            label: 'Product name',
                            hint: 'What are you selling?',
                            controller: c.nameCtrl,
                            onChanged: c.onNameChanged,
                            error: c.fieldErrors['name'],
                          ),
                          const SizedBox(height: AppConstants.spacingMd),
                          _DescriptionField(c: c),
                          const SizedBox(height: AppConstants.spacingMd),
                          _CategoryField(c: c),
                          const SizedBox(height: AppConstants.spacingMd),
                          _ConditionField(c: c),
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
                              controller: c.brandCtrl,
                            ),
                            const SizedBox(height: AppConstants.spacingMd),
                            ThriftTextField(
                              label: 'Size',
                              controller: c.sizeCtrl,
                            ),
                            const SizedBox(height: AppConstants.spacingMd),
                            ThriftTextField(
                              label: 'Color',
                              controller: c.colorCtrl,
                            ),
                          ],
                        ),
                      ),
                    ),
                    ListingFormSection(
                      title: 'Listing type',
                      subtitle:
                          'Fixed price sells immediately. Auction accepts bids.',
                      child: ListingFormatTypeRow(
                        selectedFormat: c.selectedFormat,
                        onFormatSelected: c.selectFormat,
                      ),
                    ),
                    ListingFormSection(
                      title: c.selectedFormat == ListingFormat.auction
                          ? 'Auction pricing'
                          : 'Pricing',
                      child: _EditPricingSection(c: c),
                    ),
                    ListingFormSection(
                      title: 'Item location',
                      subtitle:
                          'Uses your shop barangay from Become a Seller. Buyers never see your street address.',
                      child: ListingLocationSection(
                        showItemLocation: c.showItemLocation,
                        sellerBarangay: c.sellerBarangay,
                        onToggle: c.setShowItemLocation,
                        showHeading: false,
                      ),
                    ),
                    ListingFormSection(
                      title: 'Shipping',
                      subtitle: 'Applied at checkout for this listing.',
                      child: ListingShippingSection(
                        listingFormat: c.selectedFormat,
                        shippingMode: c.shippingMode,
                        onModeChanged: c.setShippingMode,
                        shippingFeeController: c.shippingFeeCtrl,
                        qtyThresholdController: c.qtyThresholdCtrl,
                        bidThresholdController: c.bidThresholdCtrl,
                        startingBidText: c.startBidCtrl.text,
                        shippingFeeError: c.fieldErrors['shippingFee'],
                        qtyThresholdError: c.fieldErrors['qtyThreshold'],
                        bidThresholdError: c.fieldErrors['bidThreshold'],
                        readOnly: c.shippingConfigLocked,
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
                  label: 'Save changes',
                  isLoading: c.isSaving,
                  onPressed: c.isSaving ? null : () => c.saveChanges(context),
                ),
              ),
            ),
          ),
        ),

        // Progress overlay
        if (c.isSaving)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(
                    backgroundColor: AppColors.primaryLight,
                    color: AppColors.primary,
                  ),
                  if (c.saveStatusMessage.isNotEmpty)
                    Container(
                      width: double.infinity,
                      color: AppColors.textPrimary.withValues(alpha: 0.85),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingMd,
                        vertical: AppConstants.spacingSm,
                      ),
                      child: Text(
                        c.saveStatusMessage,
                        style: AppTypography.caption.copyWith(
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Photos strip
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({required this.c});
  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    final hasError = c.fieldErrors.containsKey('images');

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
              onReorder: (o, n) => c.reorderImages(o, n),
              itemBuilder: (context, index) {
                final isFilled = index < c.slots.length;
                return ReorderableDragStartListener(
                  key: ValueKey('edit_slot_$index'),
                  index: index,
                  child: GestureDetector(
                    onTap: () => isFilled
                        ? _showOptions(context, index)
                        : c.pickImage(index),
                    child: _SlotWidget(
                      index: index,
                      slot: isFilled ? c.slots[index] : null,
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
              c.fieldErrors['images']!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  void _showOptions(BuildContext context, int index) {
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
              c.replaceImage(index);
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
              c.removeImage(index);
            },
          ),
        ],
      ),
    );
  }
}

class _SlotWidget extends StatelessWidget {
  const _SlotWidget({required this.index, required this.slot});

  final int index;
  final ImageSlot? slot;

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
            color: slot != null ? AppColors.primary : AppColors.border,
            width: slot != null ? 2 : 1,
          ),
        ),
        child: slot != null ? _filled(isCover) : _empty(label),
      ),
    );
  }

  Widget _filled(bool isCover) {
    Widget img;
    if (slot is ExistingSlot) {
      img = Image.network(
        (slot as ExistingSlot).image.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    } else {
      img = Image.memory((slot as NewSlot).image.bytes, fit: BoxFit.cover);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        img,
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
    );
  }

  Widget _empty(String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          index == 0 ? Icons.add_a_photo_outlined : Icons.add,
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
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.primaryLight,
    child: const Center(
      child: Icon(Icons.image_outlined, color: AppColors.textHint, size: 22),
    ),
  );
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Description + counter
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _DescriptionField extends StatelessWidget {
  const _DescriptionField({required this.c});
  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThriftTextField(
          label: 'Description',
          controller: c.descCtrl,
          onChanged: c.onDescChanged,
          maxLines: 4,
          error: c.fieldErrors['description'],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${c.descCtrl.text.length} / 150',
            style: AppTypography.caption,
          ),
        ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Category
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _CategoryField extends StatelessWidget {
  const _CategoryField({required this.c});
  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    final hasError = c.fieldErrors.containsKey('category');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category',
          style: AppTypography.label.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppConstants.spacingXs),
        InkWell(
          onTap: () => _showSheet(context),
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
                  child: c.categoriesLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Text(
                          c.selectedCategoryName ?? 'Select a category',
                          style: AppTypography.body.copyWith(
                            color: c.selectedCategoryName != null
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
              c.fieldErrors['category']!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }

  void _showSheet(BuildContext context) {
    if (c.categoriesLoading) return;
    ThriftBottomSheet.show(
      context,
      title: 'Select Category',
      child: c.categories.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(AppConstants.spacingLg),
              child: Center(
                child: Text(
                  'No categories available.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          : Column(
              children: c.categories.map((cat) {
                final isSelected = c.selectedCategoryId == cat.id;
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
                    c.selectCategory(cat.id, cat.name);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Condition chips
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ConditionField extends StatelessWidget {
  const _ConditionField({required this.c});
  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    final hasError = c.fieldErrors.containsKey('condition');

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
          children: ProductCondition.values.map((cond) {
            final isSelected = c.selectedCondition == cond;
            return ChoiceChip(
              label: Text(cond.label),
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
              onSelected: (_) => c.selectCondition(cond),
            );
          }).toList(),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              c.fieldErrors['condition']!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _EditPricingSection extends StatelessWidget {
  const _EditPricingSection({required this.c});

  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    final isAuction = c.selectedFormat == ListingFormat.auction;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isAuction
            ? _EditAuctionPricingFields(
                key: const ValueKey('edit_auction_pricing'),
                c: c,
              )
            : _EditFixedPricePricingFields(
                key: const ValueKey('edit_fixed_pricing'),
                c: c,
              ),
      ),
    );
  }
}

class _EditFixedPricePricingFields extends StatelessWidget {
  const _EditFixedPricePricingFields({super.key, required this.c});

  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThriftTextField(
          label: 'Price',
          hint: 'Amount in pesos',
          controller: c.priceCtrl,
          onChanged: c.onPriceChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          error: c.fieldErrors['price'],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        ThriftTextField(
          label: 'Stock quantity',
          hint: 'How many units you have',
          controller: c.stockCtrl,
          onChanged: c.onStockChanged,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          error: c.fieldErrors['stock'],
        ),
      ],
    );
  }
}

class _EditAuctionPricingFields extends StatelessWidget {
  const _EditAuctionPricingFields({super.key, required this.c});

  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThriftTextField(
          label: 'Starting bid',
          hint: 'Minimum opening bid in pesos',
          controller: c.startBidCtrl,
          onChanged: c.onStartBidChanged,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          error: c.fieldErrors['price'],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        const ListingAuctionQuantityNote(),
        const SizedBox(height: AppConstants.spacingLg),
        Text('Auction duration', style: AppTypography.label),
        const SizedBox(height: 4),
        AuctionDurationSelector(
          selectedDays: c.auctionDurationDays,
          onDaysSelected: c.selectAuctionDuration,
          previewEndsAt: c.previewAuctionEndsAt,
          durationError: c.fieldErrors['duration'],
        ),
        const SizedBox(height: AppConstants.spacingLg),
        Text('Minimum bid increment', style: AppTypography.label),
        const SizedBox(height: 4),
        BidIncrementSelector(
          selectedIncrement: c.bidIncrement,
          onIncrementSelected: c.selectBidIncrement,
          incrementError: c.fieldErrors['increment'],
        ),
      ],
    );
  }
}
