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
                    child: Text(
                      controller.errorMessage ?? 'Order not found.',
                      style: AppTypography.body,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: [
                          Text(
                            'Rate your experience',
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
                          _OrderContext(controller: controller),
                          const SizedBox(height: 28),
                          StarRatingInput(
                            value: controller.rating,
                            readOnly: controller.readOnly,
                            onChanged: controller.setRating,
                          ),
                          if (controller.rating > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${controller.rating} / 5',
                              textAlign: TextAlign.center,
                              style: AppTypography.caption.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (controller.readOnly) ...[
                            const SizedBox(height: 12),
                            Text(
                              'The 24-hour edit window has ended.',
                              textAlign: TextAlign.center,
                              style: AppTypography.caption,
                            ),
                          ],
                          const SizedBox(height: 28),
                          ThriftTextField(
                            label: 'Comment (optional)',
                            hint: 'Write your review...',
                            controller: _comment,
                            maxLines: 5,
                            readOnly: controller.readOnly,
                            onChanged: controller.setComment,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${controller.comment.trim().length}/$kReviewCommentMaxLength',
                              style: AppTypography.caption,
                            ),
                          ),
                          if (!controller.isSellerReviewingBuyer) ...[
                            const SizedBox(height: 24),
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
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!controller.readOnly)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          8,
                          20,
                          16 + MediaQuery.viewInsetsOf(context).bottom,
                        ),
                        child: ThriftButton(
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
                                        ? 'Review submitted'
                                        : 'Review updated',
                                  );
                                  context.pop();
                                }
                              : null,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _OrderContext extends StatelessWidget {
  const _OrderContext({required this.controller});

  final LeaveReviewController controller;

  @override
  Widget build(BuildContext context) {
    final order = controller.order!;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: order.productImage.isEmpty
              ? Container(
                  width: 64,
                  height: 64,
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.checkroom_outlined,
                    color: AppColors.textHint,
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: order.productImage,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order.productTitle,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '#${order.orderNumber} · ${controller.counterpartName}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
