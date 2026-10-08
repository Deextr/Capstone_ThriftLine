import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/report_user_controller.dart';
import '../../data/report_reasons.dart';
import '../../../profile/data/followed_shop_item.dart';
import '../../data/report_seller_search.dart';
import '../widgets/report_evidence_section.dart';
import '../widgets/report_seller_selection_widgets.dart';

class ReportSellerScreen extends StatefulWidget {
  const ReportSellerScreen({super.key});

  @override
  State<ReportSellerScreen> createState() => _ReportSellerScreenState();
}

class _ReportSellerScreenState extends State<ReportSellerScreen> {
  late final TextEditingController _search;
  late final TextEditingController _details;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _details = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportUserController>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('Report a Seller'),
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
              : ListView(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomInset),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (controller.errorMessage != null &&
                        !controller.hasResolvedTarget) ...[
                      Text(
                        controller.errorMessage!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!controller.hasResolvedTarget) ...[
                      Text(
                        'Who are you reporting?',
                        style: AppTypography.subheading,
                      ),
                      const SizedBox(height: 12),
                      ThriftTextField(
                        hint: 'Search seller or shop…',
                        controller: _search,
                        icon: Icons.search,
                        onChanged: controller.setSearchQuery,
                      ),
                      const SizedBox(height: 16),
                      if (controller.isSearchActive)
                        _SearchResultsSection(controller: controller)
                      else
                        _FollowingShopsSection(controller: controller),
                      const SizedBox(height: 8),
                    ],
                    if (controller.hasResolvedTarget) ...[
                      if (controller.selectedSeller != null)
                        ReportSellerSelectedCard(
                          candidate: controller.selectedSeller!,
                          onChange: () {
                            _search.clear();
                            context.read<ReportUserController>()
                              ..clearSelectedSeller()
                              ..setSearchQuery('');
                          },
                        ),
                      const SizedBox(height: 24),
                      Text(
                        'Why are you reporting this seller?',
                        style: AppTypography.subheading,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select the reason that best describes the problem.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...kCommunityReportReasons.map(
                        (reason) => _ReasonOption(
                          reason: reason,
                          selected:
                              controller.selectedCategory == reason.slug,
                          onTap: () => context
                              .read<ReportUserController>()
                              .selectCategory(reason.slug),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ThriftTextField(
                        label: controller.detailsRequired
                            ? 'Please describe the issue'
                            : 'Additional Details (Optional)',
                        hint: controller.detailsRequired
                            ? 'Tell us what happened…'
                            : 'Tell us anything else that may help us review your report.',
                        controller: _details,
                        maxLines: 5,
                        maxLength: kReportDetailsMaxLength,
                        onChanged: controller.setDetails,
                        labelSuffix: controller.detailsRequired
                            ? null
                            : Text(
                                'Optional',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${controller.details.length}/$kReportDetailsMaxLength',
                          style: AppTypography.caption,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ReportEvidenceSection(
                        evidence: controller.evidence,
                        evidenceError: controller.evidenceError,
                        required: true,
                        onAddGallery: () => context
                            .read<ReportUserController>()
                            .addEvidenceFromGallery(),
                        onAddCamera: () => context
                            .read<ReportUserController>()
                            .addEvidenceFromCamera(),
                        onRemove: (i) => context
                            .read<ReportUserController>()
                            .removeEvidence(i),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your report stays private. The seller will not see who reported them. '
                        'Our team reviews community reports in Disputes.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ThriftButton(
                        label: 'Submit Report',
                        loadingLabel: 'Submitting…',
                        isLoading: controller.isSubmitting,
                        onPressed: controller.canSubmit
                            ? () => _submit(context)
                            : null,
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final reportController = context.read<ReportUserController>();
    if (reportController.isSubmitting) return;
    final error = await reportController.submit();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(
      context,
      'Report submitted. You can track it under My Reports.',
    );
    context.pushReplacement(RouteNames.myReports);
  }
}

class _SearchResultsSection extends StatelessWidget {
  const _SearchResultsSection({required this.controller});

  final ReportUserController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search Results',
          style: AppTypography.label.copyWith(color: AppColors.textSecondary),
        ),
        if (controller.isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
          )
        else if (controller.searchResults.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No sellers found.\nTry a different seller or shop name.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          )
        else
          Column(
            children: [
              for (final candidate in controller.searchResults)
                ReportSellerSuggestionTile(
                  candidate: candidate,
                  onTap: () => _select(context, candidate),
                ),
            ],
          ),
      ],
    );
  }

  void _select(BuildContext context, ReportSellerCandidate candidate) {
    FocusScope.of(context).unfocus();
    final error = context.read<ReportUserController>().selectSeller(candidate);
    if (error != null && context.mounted) {
      showThriftSnackBar(context, error, isError: true);
    }
  }
}

class _FollowingShopsSection extends StatelessWidget {
  const _FollowingShopsSection({required this.controller});

  final ReportUserController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoadingFollowedShops &&
        controller.followedShopPreview.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
        ),
      );
    }

    final shops = controller.followedShopPreview;
    if (shops.isEmpty) {
      return Text(
        'You aren\'t following any shops yet.',
        style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Following Shops',
              style: AppTypography.label.copyWith(color: AppColors.textSecondary),
            ),
            if (controller.hasMoreFollowedShops) ...[
              const Spacer(),
              TextButton(
                onPressed: () => _showAllFollowed(context),
                child: const Text('See all'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        for (final shop in shops)
          ReportSellerSuggestionTile(
            candidate: ReportSellerCandidate.fromFollowedShop(
              sellerId: shop.sellerId,
              username: shop.username,
              shopName: shop.shopName,
              ownerName: shop.ownerName,
              avatarUrl: shop.avatarUrl,
            ),
            onTap: () {
              FocusScope.of(context).unfocus();
              final error = context.read<ReportUserController>().selectSeller(
                ReportSellerCandidate.fromFollowedShop(
                  sellerId: shop.sellerId,
                  username: shop.username,
                  shopName: shop.shopName,
                  ownerName: shop.ownerName,
                  avatarUrl: shop.avatarUrl,
                ),
              );
              if (error != null && context.mounted) {
                showThriftSnackBar(context, error, isError: true);
              }
            },
          ),
      ],
    );
  }

  void _showAllFollowed(BuildContext context) {
    final all = controller.allFollowedShops;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollController) {
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text(
                    'Following Shops',
                    style: AppTypography.subheading,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: all.length,
                    itemBuilder: (context, index) {
                      final shop = all[index];
                      return ReportSellerSuggestionTile(
                        candidate: _candidateFromFollowed(shop),
                        onTap: () {
                          Navigator.pop(ctx);
                          FocusScope.of(context).unfocus();
                          final error = context
                              .read<ReportUserController>()
                              .selectSeller(_candidateFromFollowed(shop));
                          if (error != null && context.mounted) {
                            showThriftSnackBar(context, error, isError: true);
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  ReportSellerCandidate _candidateFromFollowed(FollowedShopItem shop) {
    return ReportSellerCandidate.fromFollowedShop(
      sellerId: shop.sellerId,
      username: shop.username,
      shopName: shop.shopName,
      ownerName: shop.ownerName,
      avatarUrl: shop.avatarUrl,
    );
  }
}

class _ReasonOption extends StatelessWidget {
  const _ReasonOption({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final ReportReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 22,
                color: selected ? AppColors.primary : AppColors.textHint,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  reason.label,
                  style: AppTypography.body.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
