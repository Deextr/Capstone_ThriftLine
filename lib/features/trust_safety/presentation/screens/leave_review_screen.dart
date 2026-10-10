import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/leave_review_controller.dart';
import '../../data/review_rules.dart';
import '../widgets/review_photo_section.dart';
import '../widgets/star_rating_input.dart';

class LeaveReviewScreen extends StatefulWidget {
  const LeaveReviewScreen({super.key});

  @override
  State<LeaveReviewScreen> createState() => _LeaveReviewScreenState();
}

class _LeaveReviewScreenState extends State<LeaveReviewScreen> {
  late final TextEditingController _comment;

  @override
  void initState() {
    super.initState();
    _comment = TextEditingController();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LeaveReviewController>();
    if (controller.comment != _comment.text &&
        controller.existing != null &&
        _comment.text.isEmpty) {
      _comment.text = controller.comment;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(
            controller.isSellerReviewingBuyer ? 'Rate Buyer' : 'Leave a Review',
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: controller.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : controller.order == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingLg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          controller.errorMessage ?? 'Order not found.',
                          style: AppTypography.body,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ThriftButton(
                          label: 'Go Back',
                          variant: ThriftButtonVariant.outline,
                          onPressed: () => context.pop(),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        controller.existing == null
                            ? 'Rate your experience'
                            : 'Edit your review',
                        style: AppTypography.heading.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        reviewPrompt(
                          ratingBuyer: controller.isSellerReviewingBuyer,
                        ),
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _OrderContextCard(controller: controller),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusLg,
                          ),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            StarRatingInput(
                              value: controller.rating,
                              readOnly: controller.readOnly,
                              size: 42,
                              onChanged: controller.setRating,
                            ),
                            if (controller.readOnly) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceVariant,
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusSm,
                                  ),
                                ),
                                child: Text(
                                  'The 24-hour edit window has ended.',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Your review',
                                style: AppTypography.subheading,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(optional)',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${controller.comment.trim().length}/$kReviewCommentMaxLength',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _comment,
                            readOnly: controller.readOnly,
                            maxLines: 5,
                            maxLength: kReviewCommentMaxLength,
                            style: AppTypography.body,
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: controller.isSellerReviewingBuyer
                                  ? 'Share how smooth the transaction and communication was...'
                                  : 'Share details of the item condition, packaging, and communication...',
                              hintStyle: AppTypography.body.copyWith(
                                color: AppColors.textHint,
                              ),
                              filled: true,
                              fillColor: AppColors.surface,
                              contentPadding: const EdgeInsets.all(16),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMd,
                                ),
                                borderSide: BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMd,
                                ),
                                borderSide: BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  AppConstants.radiusMd,
                                ),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            onChanged: controller.setComment,
                          ),
                        ],
                      ),
                      if (!controller.isSellerReviewingBuyer) ...[
                        const SizedBox(height: 20),
                        ReviewPhotoSection(
                          existingPhotos: controller.existingPhotos,
                          newDrafts: controller.photoDrafts,
                          readOnly: controller.readOnly,
                          onAddGallery: () => context
                              .read<LeaveReviewController>()
                              .addPhotoFromGallery(),
                          onAddCamera: () => context
                              .read<LeaveReviewController>()
                              .addPhotoFromCamera(),
                          onRemoveExisting: (photo) => context
                              .read<LeaveReviewController>()
                              .markExistingPhotoRemoved(photo),
                          onRemoveDraft: (i) => context
                              .read<LeaveReviewController>()
                              .removePhotoDraft(i),
                        ),
                      ],
                      if (controller.errorMessage != null &&
                          controller.order != null &&
                          !controller.order!.isCompleted) ...[
                        const SizedBox(height: 16),
                        Text(
                          controller.errorMessage!,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (!controller.readOnly) ...[
                        ThriftButton(
                          label: controller.existing == null
                              ? 'Submit Review'
                              : 'Save Changes',
                          isLoading: controller.isSaving,
                          onPressed: controller.canSubmit
                              ? () async {
                                  final wasNew =
                                      context
                                          .read<LeaveReviewController>()
                                          .existing ==
                                      null;
                                  final error = await context
                                      .read<LeaveReviewController>()
                                      .submit();
                                  if (!context.mounted) return;
                                  if (error != null) {
                                    showThriftSnackBar(
                                      context,
                                      error,
                                      isError: true,
                                    );
                                    return;
                                  }
                                  showThriftSnackBar(
                                    context,
                                    wasNew
                                        ? 'Review submitted successfully!'
                                        : 'Review updated successfully!',
                                  );
                                  context.pop(true);
                                }
                              : null,
                        ),
                        if (controller.rating == 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Please select a star rating to submit your review',
                            textAlign: TextAlign.center,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _OrderContextCard extends StatelessWidget {
  const _OrderContextCard({required this.controller});

  final LeaveReviewController controller;

  @override
  Widget build(BuildContext context) {
    final order = controller.order!;
    final isSeller = controller.isSellerReviewingBuyer;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: order.productImage.isEmpty
                ? Container(
                    width: 64,
                    height: 64,
                    color: AppColors.surfaceVariant,
                    child: Icon(
                      Icons.checkroom_outlined,
                      color: AppColors.textHint,
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: order.productImage,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      width: 64,
                      height: 64,
                      color: AppColors.surfaceVariant,
                    ),
                    errorWidget: (_, _, _) => Container(
                      width: 64,
                      height: 64,
                      color: AppColors.surfaceVariant,
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  order.productTitle,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      isSeller
                          ? Icons.person_outline_rounded
                          : Icons.storefront_outlined,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        controller.counterpartName,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Order #${order.orderNumber}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textHint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
