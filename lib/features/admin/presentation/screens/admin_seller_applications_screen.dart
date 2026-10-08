import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../controllers/admin_seller_applications_controller.dart';
import '../../data/admin_verification_service.dart';
import '../widgets/admin_ui_components.dart';

class AdminSellerApplicationsScreen extends StatefulWidget {
  const AdminSellerApplicationsScreen({
    super.key,
    this.embedded = false,
    this.webEmbedded = false,
  });

  final bool embedded;
  final bool webEmbedded;

  @override
  State<AdminSellerApplicationsScreen> createState() =>
      _AdminSellerApplicationsScreenState();
}

class _AdminSellerApplicationsScreenState
    extends State<AdminSellerApplicationsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    context.read<AdminSellerApplicationsController>().scheduleSearch(
      _searchController.text,
    );
  }

  void _openDetail(SellerApplication application) async {
    await context.push(RouteNames.adminReviewFor(application.id));
    if (mounted) {
      await context.read<AdminSellerApplicationsController>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminSellerApplicationsController>();
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= AppConstants.breakpointDesktop;

    final content = SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () =>
            context.read<AdminSellerApplicationsController>().load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            widget.embedded && !isDesktop ? 100 : 36,
          ),
          children: [
            if (!widget.webEmbedded)
              AdminPageHeader(
                title: 'Seller Verifications',
                actions: [
                  OutlinedButton.icon(
                    onPressed: controller.isLoading
                        ? null
                        : () => controller.load(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            AdminFilterBar(
              hasActiveFilters: controller.hasActiveFilters,
              onReset: () {
                _searchController.clear();
                controller.resetFilters();
              },
              trailing: widget.webEmbedded
                  ? OutlinedButton.icon(
                      onPressed: controller.isLoading
                          ? null
                          : () => controller.load(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    )
                  : null,
              children: [
                AdminSearchField(
                  controller: _searchController,
                  hintText: 'Search applicant, store, email…',
                  width: screenWidth < 600 ? double.infinity : 290,
                  onSubmitted: controller.setSearch,
                  onClear: () => controller.setSearch(''),
                ),
                AdminFilterDropdown<String>(
                  value: controller.status,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('Pending Review'),
                    ),
                    DropdownMenuItem(
                      value: 'approved',
                      child: Text('Approved'),
                    ),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) controller.setStatus(val);
                  },
                ),
                AdminDateFilter(
                  window: controller.window,
                  onChanged: controller.setWindow,
                ),
              ],
            ),
            if (controller.errorMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 20,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        controller.errorMessage!,
                        style: AppTypography.body.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => controller.load(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ],
            AdminDataTable(
              isLoading: controller.isLoading,
              minWidth: 720,
              columnFlex: const [3, 2, 2, 1, 1],
              emptyTitle: 'No seller applications found',
              emptyMessage: controller.hasActiveFilters
                  ? 'No applications match your active search or filters. Try adjusting them.'
                  : 'New seller verification requests will appear here.',
              onResetFilters: controller.hasActiveFilters
                  ? () {
                      _searchController.clear();
                      controller.resetFilters();
                    }
                  : null,
              onRowTap: [
                for (final app in controller.applications)
                  () => _openDetail(app),
              ],
              columns: const [
                'Applicant',
                'Store',
                'Submitted',
                'Status',
                'Action',
              ],
              rows: [
                for (final app in controller.applications)
                  [
                    AdminTableApplicantCell(
                      displayName:
                          (app.applicantName?.trim().isNotEmpty ?? false)
                          ? app.applicantName!.trim()
                          : 'Applicant',
                      secondaryLine:
                          app.applicantEmail?.trim().isNotEmpty == true
                          ? app.applicantEmail!.trim()
                          : (app.applicantUsername?.trim().isNotEmpty == true
                                ? '@${app.applicantUsername!.trim()}'
                                : null),
                      avatarName: app.applicantName ?? app.shopName,
                    ),
                    AdminTableCellText(primary: app.shopName),
                    AdminTableDateCell(dateTime: app.submittedAt),
                    AdminStatusBadge(status: app.status),
                    AdminTableLinkAction(
                      label: app.status == 'pending' ? 'Review' : 'View',
                      onPressed: () => _openDetail(app),
                    ),
                  ],
              ],
            ),
            const SizedBox(height: 16),
            AdminPagination(
              currentPage: controller.page,
              totalItems: controller.total,
              pageSize: controller.pageSize,
              pageSizeOptions: const [10, 25, 50],
              isLoading: controller.isLoading,
              onPageChanged: controller.setPage,
              onPageSizeChanged: controller.setPageSize,
            ),
          ],
        ),
      ),
    );

    if (widget.webEmbedded) {
      return ColoredBox(color: AppColors.background, child: content);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Seller Verifications'),
        leading: widget.embedded
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
      ),
      body: content,
    );
  }
}
