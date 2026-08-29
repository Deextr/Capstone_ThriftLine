import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/add_listing_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Single-scroll listing creation screen.
///
/// Pure UI — all state and logic live in [AddListingController].
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
          body: CustomScrollView(
            slivers: [
              // ── App bar ──────────────────────────────────────────────────
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

              // ── Form sections ────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.spacingMd,
                  AppConstants.spacingMd,
                  AppConstants.spacingMd,
                  AppConstants.spacingXxl,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 1. Photos strip
                    _PhotosSection(controller: controller),
                    const SizedBox(height: AppConstants.spacingLg),

                    // 2. Product name
                    ThriftTextField(
                      label: 'Product Name',
                      controller: controller.nameCtrl,
                      onChanged: controller.onNameChanged,
                      error: controller.fieldErrors['name'],
                    ),
                    const SizedBox(height: AppConstants.spacingMd),

                    // 3. Description + counter
                    _DescriptionField(controller: controller),
                    const SizedBox(height: AppConstants.spacingMd),

                    // 4. Category
                    _CategoryField(controller: controller),
                    const SizedBox(height: AppConstants.spacingMd),

                    // 5. Condition
                    _ConditionField(controller: controller),
                    const SizedBox(height: AppConstants.spacingMd),

                    // 6. Brand (optional)
                    ThriftTextField(
                      label: 'Brand (optional)',
                      controller: controller.brandCtrl,
                    ),
                    const SizedBox(height: AppConstants.spacingMd),

                    // 7. Size (optional)
                    ThriftTextField(
                      label: 'Size (optional)',
                      controller: controller.sizeCtrl,
                    ),
                    const SizedBox(height: AppConstants.spacingMd),

                    // 8. Color (optional)
                    ThriftTextField(
                      label: 'Color (optional)',
                      controller: controller.colorCtrl,
                    ),
                    const SizedBox(height: AppConstants.spacingMd),

                    // 9. Selling format + pricing
                    _SellingFormatSection(controller: controller),
                    const SizedBox(height: AppConstants.spacingMd),

                    // 10. Location (optional)
                    ThriftTextField(
                      label: 'Item Location (optional)',
                      controller: controller.locationCtrl,
                    ),
                    const SizedBox(height: AppConstants.spacingMd),
                  ]),
                ),
              ),
            ],
          ),

          // ── Persistent bottom action bar ──────────────────────────────
          bottomNavigationBar: BottomAppBar(
            color: AppColors.surface,
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
                vertical: AppConstants.spacingSm,
              ),
              child: ThriftButton(
                label: 'Post Listing',
                onPressed: controller.isLoading
                    ? null
                    : () => controller.postListing(context),
              ),
            ),
          ),
        ),

        // ── Upload progress overlay (shown while isLoading) ───────────
        if (controller.isLoading)
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
                  if (controller.uploadStatusMessage.isNotEmpty)
                    Container(
                      width: double.infinity,
                      color: AppColors.textPrimary.withValues(alpha: 0.85),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingMd,
                        vertical: AppConstants.spacingSm,
                      ),
                      child: Text(
                        controller.uploadStatusMessage,
                        style: AppTypography.caption
                            .copyWith(color: Colors.white),
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

// ─────────────────────────────────────────────────────────────────────────────
// Description field with live character counter
// ─────────────────────────────────────────────────────────────────────────────

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
            '${controller.descCtrl.text.length} / 500',
            style: AppTypography.caption,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category field — tappable, opens bottom sheet populated from DB
// ─────────────────────────────────────────────────────────────────────────────

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
        Text('Category', style: AppTypography.label.copyWith(color: AppColors.textPrimary)),
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
                const Icon(Icons.category_outlined, color: AppColors.textHint, size: 20),
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
                const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
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

  void _showCategorySheet(BuildContext context, AddListingController controller) {
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
                  style: AppTypography.body.copyWith(color: AppColors.textSecondary),
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
                    color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                  title: Text(
                    cat.name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

// ─────────────────────────────────────────────────────────────────────────────
// Condition chip row (filled in task 8.4)
// ─────────────────────────────────────────────────────────────────────────────

class _ConditionField extends StatelessWidget {
  const _ConditionField({required this.controller});

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    final hasError = controller.fieldErrors.containsKey('condition');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Condition', style: AppTypography.label.copyWith(color: AppColors.textPrimary)),
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
                color: isSelected ? AppColors.primaryDark : AppColors.textSecondary,
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

// ─────────────────────────────────────────────────────────────────────────────
// Photos strip — placeholder, replaced in task 8.3
// ─────────────────────────────────────────────────────────────────────────────

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({required this.controller});

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    final hasError = controller.fieldErrors.containsKey('images');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photos',
          style: AppTypography.label.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppConstants.spacingXs),
        Text(
          'Add up to 3 photos. First photo is the cover.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: AppConstants.spacingSm),
        SizedBox(
          height: 90,
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
            title: const Text('Remove',
                style: TextStyle(color: AppColors.error)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Individual image slot widget
// ─────────────────────────────────────────────────────────────────────────────

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
        width: 80,
        height: 80,
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

// ─────────────────────────────────────────────────────────────────────────────
// Selling format cards + conditional price/auction fields (task 8.5)
// ─────────────────────────────────────────────────────────────────────────────

class _SellingFormatSection extends StatelessWidget {
  const _SellingFormatSection({required this.controller});

  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selling Format',
          style: AppTypography.label.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppConstants.spacingSm),

        // Format cards
        Row(
          children: [
            _FormatCard(
              label: 'Fixed Price',
              icon: Icons.tag,
              format: ListingFormat.fixedPrice,
              controller: controller,
            ),
            const SizedBox(width: 8),
            _FormatCard(
              label: 'Auction',
              icon: Icons.gavel,
              format: ListingFormat.auction,
              controller: controller,
            ),
            const SizedBox(width: 8),
            _FormatCard(
              label: 'Live Session',
              icon: Icons.live_tv_outlined,
              format: ListingFormat.liveSession,
              controller: controller,
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingMd),

        // Conditional price / auction fields
        if (controller.selectedFormat != ListingFormat.auction) ...[
          ThriftTextField(
            label: controller.selectedFormat == ListingFormat.liveSession
                ? 'Starting Price (₱)'
                : 'Price (₱)',
            controller: controller.priceCtrl,
            onChanged: controller.onPriceChanged,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            error: controller.fieldErrors['price'],
          ),
        ] else ...[
          ThriftTextField(
            label: 'Starting Bid (₱)',
            controller: controller.startBidCtrl,
            onChanged: controller.onStartBidChanged,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            error: controller.fieldErrors['price'],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _SelectorField(
            label: 'Auction Duration',
            value: '${controller.auctionDurationDays} days',
            icon: Icons.today_outlined,
            onTap: () => _showDurationPicker(context, controller),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _SelectorField(
            label: 'Minimum Bid Increment',
            value: '₱${controller.bidIncrement.toInt()}',
            icon: Icons.add_circle_outline,
            onTap: () => _showIncrementPicker(context, controller),
          ),
        ],
      ],
    );
  }

  void _showDurationPicker(
      BuildContext context, AddListingController controller) {
    ThriftBottomSheet.show(
      context,
      title: 'Auction Duration',
      child: Column(
        children: [1, 3, 5, 7].map((d) {
          final isSelected = controller.auctionDurationDays == d;
          return ListTile(
            leading: Icon(
              Icons.today,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            title: Text(
              '$d days',
              style: TextStyle(
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: isSelected
                ? const Icon(Icons.check, color: AppColors.primary)
                : null,
            onTap: () {
              controller.selectAuctionDuration(d);
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }

  void _showIncrementPicker(
      BuildContext context, AddListingController controller) {
    ThriftBottomSheet.show(
      context,
      title: 'Minimum Bid Increment',
      child: Column(
        children: [10.0, 20.0, 50.0, 100.0].map((v) {
          final isSelected = controller.bidIncrement == v;
          return ListTile(
            leading: Icon(
              Icons.add_circle_outline,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            title: Text(
              '₱${v.toInt()}',
              style: TextStyle(
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: isSelected
                ? const Icon(Icons.check, color: AppColors.primary)
                : null,
            onTap: () {
              controller.selectBidIncrement(v);
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Format card widget
// ─────────────────────────────────────────────────────────────────────────────

class _FormatCard extends StatelessWidget {
  const _FormatCard({
    required this.label,
    required this.icon,
    required this.format,
    required this.controller,
  });

  final String label;
  final IconData icon;
  final ListingFormat format;
  final AddListingController controller;

  @override
  Widget build(BuildContext context) {
    final isSelected = controller.selectedFormat == format;
    return Expanded(
      child: GestureDetector(
        onTap: () => controller.selectFormat(format),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryLight : AppColors.surface,
            borderRadius:
                BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: isSelected
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primaryDark
                      : AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable selector field (tap-to-open pattern)
// ─────────────────────────────────────────────────────────────────────────────

class _SelectorField extends StatelessWidget {
  const _SelectorField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.label
              .copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppConstants.spacingXs),
        InkWell(
          onTap: onTap,
          borderRadius:
              BorderRadius.circular(AppConstants.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.textHint, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    style: AppTypography.body.copyWith(
                        color: AppColors.textPrimary),
                  ),
                ),
                const Icon(Icons.arrow_drop_down,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
