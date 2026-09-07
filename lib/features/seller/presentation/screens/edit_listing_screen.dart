import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/add_listing_controller.dart' show ListingFormat;
import '../../controllers/edit_listing_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class EditListingScreen extends StatelessWidget {
  const EditListingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EditListingController>();

    if (c.initialLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
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
          body: CustomScrollView(
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
                    _PhotosSection(c: c),
                    const SizedBox(height: AppConstants.spacingLg),
                    ThriftTextField(
                      label: 'Product Name',
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
                    const SizedBox(height: AppConstants.spacingMd),
                    ThriftTextField(
                      label: 'Brand (optional)',
                      controller: c.brandCtrl,
                    ),
                    const SizedBox(height: AppConstants.spacingMd),
                    ThriftTextField(
                      label: 'Size (optional)',
                      controller: c.sizeCtrl,
                    ),
                    const SizedBox(height: AppConstants.spacingMd),
                    ThriftTextField(
                      label: 'Color (optional)',
                      controller: c.colorCtrl,
                    ),
                    const SizedBox(height: AppConstants.spacingMd),
                    _SellingFormatSection(c: c),
                    const SizedBox(height: AppConstants.spacingMd),
                    ThriftTextField(
                      label: 'Item Location (optional)',
                      controller: c.locationCtrl,
                    ),
                    const SizedBox(height: AppConstants.spacingMd),
                  ]),
                ),
              ),
            ],
          ),
          bottomNavigationBar: BottomAppBar(
            color: AppColors.surface,
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
                vertical: AppConstants.spacingSm,
              ),
              child: ThriftButton(
                label: 'Save Changes',
                onPressed:
                    c.isSaving ? null : () => c.saveChanges(context),
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
// Photos strip
// ─────────────────────────────────────────────────────────────────────────────

class _PhotosSection extends StatelessWidget {
  const _PhotosSection({required this.c});
  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    final hasError = c.fieldErrors.containsKey('images');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos',
            style: AppTypography.label.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppConstants.spacingXs),
        Text('Up to 3 photos. First is the cover.',
            style: AppTypography.caption),
        const SizedBox(height: AppConstants.spacingSm),
        SizedBox(
          height: 90,
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
            leading:
                const Icon(Icons.delete_outline, color: AppColors.error),
            title: const Text('Remove',
                style: TextStyle(color: AppColors.error)),
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
        width: 80,
        height: 80,
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
      img = Image.memory(
        (slot as NewSlot).image.bytes,
        fit: BoxFit.cover,
      );
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
          child:
              Icon(Icons.image_outlined, color: AppColors.textHint, size: 22),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Description + counter
// ─────────────────────────────────────────────────────────────────────────────

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
            '${c.descCtrl.text.length} / 500',
            style: AppTypography.caption,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryField extends StatelessWidget {
  const _CategoryField({required this.c});
  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    final hasError = c.fieldErrors.containsKey('category');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category',
            style:
                AppTypography.label.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppConstants.spacingXs),
        InkWell(
          onTap: () => _showSheet(context),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: hasError ? AppColors.error : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.category_outlined,
                    color: AppColors.textHint, size: 20),
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
                const Icon(Icons.arrow_drop_down,
                    color: AppColors.textSecondary),
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
                  style: AppTypography.body
                      .copyWith(color: AppColors.textSecondary),
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

// ─────────────────────────────────────────────────────────────────────────────
// Condition chips
// ─────────────────────────────────────────────────────────────────────────────

class _ConditionField extends StatelessWidget {
  const _ConditionField({required this.c});
  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    final hasError = c.fieldErrors.containsKey('condition');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Condition',
            style:
                AppTypography.label.copyWith(color: AppColors.textPrimary)),
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
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(AppConstants.radiusSm),
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

// ─────────────────────────────────────────────────────────────────────────────
// Selling format + conditional price / auction fields
// ─────────────────────────────────────────────────────────────────────────────

class _SellingFormatSection extends StatelessWidget {
  const _SellingFormatSection({required this.c});
  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Selling Format',
            style:
                AppTypography.label.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppConstants.spacingSm),
        Row(
          children: [
            _FmtCard(
                label: 'Fixed Price',
                icon: Icons.tag,
                format: ListingFormat.fixedPrice,
                c: c),
            const SizedBox(width: 8),
            _FmtCard(
                label: 'Auction',
                icon: Icons.gavel,
                format: ListingFormat.auction,
                c: c),
            const SizedBox(width: 8),
            _FmtCard(
                label: 'Live Session',
                icon: Icons.live_tv_outlined,
                format: ListingFormat.liveSession,
                c: c),
          ],
        ),
        const SizedBox(height: AppConstants.spacingMd),
        if (c.selectedFormat != ListingFormat.auction)
          ThriftTextField(
            label: c.selectedFormat == ListingFormat.liveSession
                ? 'Starting Price (₱)'
                : 'Price (₱)',
            controller: c.priceCtrl,
            onChanged: c.onPriceChanged,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            error: c.fieldErrors['price'],
          )
        else ...[
          ThriftTextField(
            label: 'Starting Bid (₱)',
            controller: c.startBidCtrl,
            onChanged: c.onStartBidChanged,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            error: c.fieldErrors['price'],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _SelectorField(
            label: 'Auction Duration',
            value: '${c.auctionDurationDays} days',
            icon: Icons.today_outlined,
            onTap: () => _showDurationPicker(context),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          _SelectorField(
            label: 'Minimum Bid Increment',
            value: '₱${c.bidIncrement.toInt()}',
            icon: Icons.add_circle_outline,
            onTap: () => _showIncrementPicker(context),
          ),
        ],
      ],
    );
  }

  void _showDurationPicker(BuildContext context) {
    ThriftBottomSheet.show(
      context,
      title: 'Auction Duration',
      child: Column(
        children: [1, 3, 5, 7].map((d) {
          final isSelected = c.auctionDurationDays == d;
          return ListTile(
            leading: Icon(Icons.today,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary),
            title: Text('$d days',
                style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal)),
            trailing: isSelected
                ? const Icon(Icons.check, color: AppColors.primary)
                : null,
            onTap: () {
              c.selectAuctionDuration(d);
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }

  void _showIncrementPicker(BuildContext context) {
    ThriftBottomSheet.show(
      context,
      title: 'Minimum Bid Increment',
      child: Column(
        children: [10.0, 20.0, 50.0, 100.0].map((v) {
          final isSelected = c.bidIncrement == v;
          return ListTile(
            leading: Icon(Icons.add_circle_outline,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textSecondary),
            title: Text('₱${v.toInt()}',
                style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal)),
            trailing: isSelected
                ? const Icon(Icons.check, color: AppColors.primary)
                : null,
            onTap: () {
              c.selectBidIncrement(v);
              Navigator.pop(context);
            },
          );
        }).toList(),
      ),
    );
  }
}

class _FmtCard extends StatelessWidget {
  const _FmtCard(
      {required this.label,
      required this.icon,
      required this.format,
      required this.c});

  final String label;
  final IconData icon;
  final ListingFormat format;
  final EditListingController c;

  @override
  Widget build(BuildContext context) {
    final isSelected = c.selectedFormat == format;
    return Expanded(
      child: GestureDetector(
        onTap: () => c.selectFormat(format),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 22),
              const SizedBox(height: 6),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
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
        Text(label,
            style:
                AppTypography.label.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppConstants.spacingXs),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.textHint, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(value,
                      style: AppTypography.body
                          .copyWith(color: AppColors.textPrimary)),
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
