import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../controllers/admin_marketplace_reports_controller.dart';
import '../../data/marketplace_report_export.dart';
import '../../data/marketplace_report_models.dart';
import '../../domain/marketplace_report_catalog.dart';
import '../../data/marketplace_report_export_progress.dart';
import '../widgets/admin_ui_components.dart';
import '../widgets/marketplace_report_export_progress_dialog.dart';
import '../widgets/marketplace_report_layout.dart';

class AdminWebMarketplaceReportsPage extends StatefulWidget {
  const AdminWebMarketplaceReportsPage({super.key});

  @override
  State<AdminWebMarketplaceReportsPage> createState() =>
      _AdminWebMarketplaceReportsPageState();
}

class _AdminWebMarketplaceReportsPageState
    extends State<AdminWebMarketplaceReportsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MarketplaceReportExporter.preloadPdfAssets();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminMarketplaceReportsController>();
    final payload = controller.payload;
    final padding = MediaQuery.sizeOf(context).width < 900 ? 16.0 : 24.0;

    return ColoredBox(
      color: AppColors.background,
      child: ListView(
        padding: EdgeInsets.all(padding),
        children: [
          AdminFilterBar(
            hasActiveFilters: controller.hasActiveFilters,
            onReset: controller.resetFilters,
            trailing: _ExportActions(
              isExporting: controller.isExporting,
              onPdf: () => _export(context, pdf: true),
              onExcel: () => _export(context, pdf: false),
            ),
            children: [
              AdminFilterDropdown<String>(
                label: 'Report type',
                value: controller.selection.queryValue,
                items: [
                  for (final type in adminReportTypesInOrder)
                    DropdownMenuItem(
                      value: adminReportTypeQueryValue(type),
                      child: Text(adminReportTypeLabel(type)),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  final selection = MarketplaceReportSelection.fromQuery(value);
                  controller.applyReportType(selection);
                  context.go(
                    '/admin/marketplace-reports?type=${selection.queryValue}',
                  );
                },
              ),
              _ReportDateRangeDropdown(
                window: controller.window,
                onPresetKey: (key) => _applyDateRangeKey(context, controller, key),
              ),
              ..._categoryFilters(controller),
            ],
          ),
          if (controller.errorMessage != null) ...[
            _ErrorBanner(
              message: controller.errorMessage!,
              onRetry: controller.load,
            ),
            const SizedBox(height: 12),
          ],
          if (controller.isLoading && payload == null)
            const AdminTableSkeleton(columns: ['Metric', 'Value'], rowCount: 8)
          else if (payload != null && payload.success) ...[
            if (controller.isLoading)
              const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
            if (controller.isAllReportTypes)
              _AllReportsDisplay(
                controller: controller,
                payload: payload,
              )
            else
              _SingleReportDisplay(
                controller: controller,
                payload: payload,
                payments: controller.paymentsPayload,
              ),
          ] else if (!controller.isLoading) ...[
            _EmptyReportState(
              title: 'Report unavailable',
              message: controller.errorMessage ??
                  'Unable to load data for this category.',
              onRetry: controller.load,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _export(
    BuildContext context, {
    required bool pdf,
  }) async {
    final controller = context.read<AdminMarketplaceReportsController>();
    await _exportWithProgress(
      context,
      dialogTitle: pdf ? 'Exporting PDF' : 'Exporting Excel',
      successMessage: pdf ? 'PDF downloaded.' : 'Excel downloaded.',
      exportFormat: pdf ? 'pdf' : 'xlsx',
      runExport: (payload, updateBuildProgress) async {
        if (pdf) {
          await MarketplaceReportExporter.exportPdf(
            payload: payload,
            category: controller.category,
            window: controller.window,
            filters: controller.filters,
            complete: controller.isAllReportTypes,
            title: controller.selection.label,
            onProgress: updateBuildProgress,
          );
        } else {
          await MarketplaceReportExporter.exportExcel(
            payload: payload,
            category: controller.category,
            window: controller.window,
            filters: controller.filters,
            complete: controller.isAllReportTypes,
            title: controller.selection.label,
            onProgress: updateBuildProgress,
          );
        }
      },
    );
  }

  Future<void> _exportWithProgress(
    BuildContext context, {
    required String dialogTitle,
    required String successMessage,
    required String exportFormat,
    required Future<void> Function(
      MarketplaceReportPayload payload,
      void Function(MarketplaceReportExportProgress progress) onBuildProgress,
    ) runExport,
  }) async {
    final controller = context.read<AdminMarketplaceReportsController>();
    final messenger = ScaffoldMessenger.of(context);
    final progressNotifier = ValueNotifier(
      const MarketplaceReportExportProgress(0, 'Preparing export…'),
    );

    controller.setExporting(true);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => ValueListenableBuilder(
          valueListenable: progressNotifier,
          builder: (_, progress, __) => MarketplaceReportExportProgressDialog(
            progress: progress,
            title: dialogTitle,
          ),
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;

    void updateProgress(double fraction, String message) {
      progressNotifier.value = MarketplaceReportExportProgress(
        fraction.clamp(0.0, 1.0),
        message,
      );
    }

    try {
      updateProgress(0.04, 'Fetching report data…');
      final payload = await controller.loadForExport(
        onProgress: (dataPhase) {
          updateProgress(
            0.04 + dataPhase * 0.28,
            'Fetching report data…',
          );
        },
      );
      if (payload == null || !payload.success) {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                payload?.error ??
                    'Export failed. Check your connection and try again.',
              ),
            ),
          );
        }
        return;
      }

      updateProgress(0.34, 'Building file…');
      await runExport(
        payload,
        (progress) {
          updateProgress(
            0.34 + progress.fraction * 0.64,
            progress.message,
          );
        },
      );

      await controller.recordExport(
        format: exportFormat,
        scope: controller.isAllReportTypes ? 'all' : 'category',
      );
      updateProgress(1.0, 'Download complete');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Export failed. Please try again.')),
        );
      }
    } finally {
      controller.setExporting(false);
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progressNotifier.dispose();
    }
  }

  Future<void> _applyDateRangeKey(
    BuildContext context,
    AdminMarketplaceReportsController controller,
    String key,
  ) async {
    if (key == 'custom') {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2024),
        lastDate: now,
      );
      if (picked != null) {
        controller.setWindow(
          MarketplaceReportDateWindow.custom(
            startManila: picked.start,
            endManila: picked.end,
          ),
        );
      }
      return;
    }
    final window = switch (key) {
      'today' => MarketplaceReportDateWindow.today(),
      'weekly' => MarketplaceReportDateWindow.last7Days(),
      'monthly' => MarketplaceReportDateWindow.thisMonth(),
      'yearly' => MarketplaceReportDateWindow.thisYear(),
      _ => MarketplaceReportDateWindow.thisMonth(),
    };
    controller.setWindow(window);
  }

  List<Widget> _categoryFilters(AdminMarketplaceReportsController controller) {
    if (controller.isAllReportTypes) return [];
    return switch (controller.selection.type) {
      AdminReportType.users => [
          AdminFilterDropdown<String?>(
            label: 'Account type',
            value: controller.filters['account_type'],
            items: const [
              DropdownMenuItem(value: null, child: Text('All records')),
              DropdownMenuItem(value: 'buyer_only', child: Text('Buyer only')),
              DropdownMenuItem(
                value: 'buyer_seller',
                child: Text('Buyer + Seller'),
              ),
            ],
            onChanged: (v) => controller.setFilter('account_type', v),
          ),
          AdminFilterDropdown<String?>(
            label: 'Account status',
            value: controller.filters['account_status'],
            items: const [
              DropdownMenuItem(value: null, child: Text('All statuses')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'suspended', child: Text('Disabled')),
              DropdownMenuItem(value: 'banned', child: Text('Banned')),
              DropdownMenuItem(value: 'deactivated', child: Text('Deactivated')),
            ],
            onChanged: (v) => controller.setFilter('account_status', v),
          ),
        ],
      AdminReportType.ordersTransactions => [
          AdminFilterDropdown<String?>(
            label: 'Order type',
            value: controller.filters['order_type'],
            items: const [
              DropdownMenuItem(value: null, child: Text('All types')),
              DropdownMenuItem(value: 'fixed_price', child: Text('Fixed price')),
              DropdownMenuItem(value: 'auction', child: Text('Auction')),
            ],
            onChanged: (v) => controller.setFilter('order_type', v),
          ),
          AdminFilterDropdown<String?>(
            label: 'Order status',
            value: controller.filters['order_status'],
            items: const [
              DropdownMenuItem(value: null, child: Text('All statuses')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'paid', child: Text('Paid')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              DropdownMenuItem(value: 'disputed', child: Text('Disputed')),
            ],
            onChanged: (v) => controller.setFilter('order_status', v),
          ),
          AdminFilterDropdown<String?>(
            label: 'Payment status',
            value: controller.filters['payment_status'],
            items: const [
              DropdownMenuItem(value: null, child: Text('All payments')),
              DropdownMenuItem(value: 'paid', child: Text('Paid')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'failed', child: Text('Failed')),
              DropdownMenuItem(value: 'refunded', child: Text('Refunded')),
            ],
            onChanged: (v) => controller.setFilter('payment_status', v),
          ),
        ],
      AdminReportType.bidding => [
          AdminFilterDropdown<String?>(
            label: 'Auction outcome',
            value: controller.filters['auction_outcome'],
            items: const [
              DropdownMenuItem(value: null, child: Text('All records')),
              DropdownMenuItem(value: 'with_winner', child: Text('With winner')),
              DropdownMenuItem(value: 'no_winner', child: Text('No winner')),
            ],
            onChanged: (v) => controller.setFilter('auction_outcome', v),
          ),
        ],
      AdminReportType.disputes => [
          AdminFilterDropdown<String?>(
            label: 'Dispute type',
            value: controller.filters['dispute_type'],
            items: const [
              DropdownMenuItem(value: null, child: Text('All types')),
              DropdownMenuItem(value: 'community', child: Text('Community')),
              DropdownMenuItem(value: 'order', child: Text('Order')),
              DropdownMenuItem(value: 'looking_for', child: Text('Looking For')),
            ],
            onChanged: (v) => controller.setFilter('dispute_type', v),
          ),
          AdminFilterDropdown<String?>(
            label: 'Dispute status',
            value: controller.filters['dispute_status'],
            items: const [
              DropdownMenuItem(value: null, child: Text('All statuses')),
              DropdownMenuItem(value: 'under_review', child: Text('Under review')),
              DropdownMenuItem(
                value: 'needs_more_evidence',
                child: Text('Needs evidence'),
              ),
              DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
              DropdownMenuItem(value: 'dismissed', child: Text('Dismissed')),
            ],
            onChanged: (v) => controller.setFilter('dispute_status', v),
          ),
        ],
      AdminReportType.verifications => [
          AdminFilterDropdown<String?>(
            label: 'Application outcome',
            value: controller.filters['verification_outcome'],
            items: const [
              DropdownMenuItem(value: null, child: Text('All records')),
              DropdownMenuItem(value: 'pending', child: Text('Pending')),
              DropdownMenuItem(value: 'approved', child: Text('Approved')),
              DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
            ],
            onChanged: (v) => controller.setFilter('verification_outcome', v),
          ),
        ],
      AdminReportType.security => [
          if (controller.isSuperAdmin)
            AdminFilterDropdown<String?>(
              label: 'Event category',
              value: controller.filters['event_category'],
              items: const [
                DropdownMenuItem(value: null, child: Text('All categories')),
                DropdownMenuItem(
                  value: 'authentication',
                  child: Text('Authentication'),
                ),
                DropdownMenuItem(
                  value: 'account_management',
                  child: Text('Account management'),
                ),
                DropdownMenuItem(
                  value: 'reports_disputes',
                  child: Text('Reports & disputes'),
                ),
                DropdownMenuItem(
                  value: 'payments_escrow',
                  child: Text('Payments & escrow'),
                ),
                DropdownMenuItem(
                  value: 'system_security',
                  child: Text('System security'),
                ),
              ],
              onChanged: (v) => controller.setFilter('event_category', v),
            ),
        ],
      AdminReportType.all => [],
    };
  }
}

class _ReportDateRangeDropdown extends StatelessWidget {
  const _ReportDateRangeDropdown({
    required this.window,
    required this.onPresetKey,
  });

  final MarketplaceReportDateWindow window;
  final void Function(String presetKey) onPresetKey;

  static const _options = [
    ('today', 'Today'),
    ('weekly', 'Weekly'),
    ('monthly', 'Monthly'),
    ('yearly', 'Yearly'),
    ('custom', 'Custom Range'),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedKey = window.reportDateRangeKey;
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedKey,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
          style: AppTypography.body.copyWith(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          selectedItemBuilder: (context) => [
            for (final _ in _options)
              Text(
                window.reportDateRangeButtonLabel,
                overflow: TextOverflow.ellipsis,
              ),
          ],
          items: [
            for (final (key, label) in _options)
              DropdownMenuItem(value: key, child: Text(label)),
          ],
          onChanged: (key) {
            if (key != null) onPresetKey(key);
          },
        ),
      ),
    );
  }
}

class _SingleReportDisplay extends StatelessWidget {
  const _SingleReportDisplay({
    required this.controller,
    required this.payload,
    this.payments,
  });

  final AdminMarketplaceReportsController controller;
  final MarketplaceReportPayload payload;
  final MarketplaceReportPayload? payments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportContextBar(
          title: controller.selection.label,
          periodLabel: controller.window.chipLabel,
        ),
        const SizedBox(height: 12),
        _buildReportSummarySection(
          reportType: controller.selection.type,
          metrics: payload.summary,
          breakdowns: payload.breakdowns,
          payments: payments,
        ),
        const SizedBox(height: 16),
        _DetailSection(controller: controller, payload: payload),
      ],
    );
  }
}

class _AllReportsDisplay extends StatelessWidget {
  const _AllReportsDisplay({
    required this.controller,
    required this.payload,
  });

  final AdminMarketplaceReportsController controller;
  final MarketplaceReportPayload payload;

  @override
  Widget build(BuildContext context) {
    final bundle = payload.completeBundle ?? const {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportContextBar(
          title: 'All Reports',
          periodLabel: controller.window.chipLabel,
        ),
        const SizedBox(height: 12),
        MarketplaceReportOverviewGrid(metrics: payload.summary),
        for (final category in marketplaceReportAllSectionCategories) ...[
          if (category == MarketplaceReportCategory.payments) ...[],
          if (category != MarketplaceReportCategory.payments) ...[
            const SizedBox(height: 24),
            _TypedReportBlock(
              title: category == MarketplaceReportCategory.orders
                  ? adminReportTypeLabel(AdminReportType.ordersTransactions)
                  : _allSectionTitle(category),
              section: bundle[marketplaceReportCategoryRpcValue(category)],
              paymentsCompanion: category == MarketplaceReportCategory.orders
                  ? bundle['payments']
                  : null,
            ),
          ],
        ],
      ],
    );
  }
}

String _allSectionTitle(MarketplaceReportCategory category) => switch (category) {
      MarketplaceReportCategory.verifications => 'Seller Verification Reports',
      MarketplaceReportCategory.users => 'Users Reports',
      MarketplaceReportCategory.orders => 'Orders',
      MarketplaceReportCategory.payments => 'Transactions and payments',
      MarketplaceReportCategory.auctions => 'Bidding Reports',
      MarketplaceReportCategory.disputes => 'Disputes Reports',
      MarketplaceReportCategory.security => 'Security & Activity Reports',
      MarketplaceReportCategory.overview => 'Marketplace summary',
    };

class _TypedReportBlock extends StatelessWidget {
  const _TypedReportBlock({
    required this.title,
    this.section,
    this.paymentsCompanion,
  });

  final String title;
  final MarketplaceReportPayload? section;
  final MarketplaceReportPayload? paymentsCompanion;

  @override
  Widget build(BuildContext context) {
    if (section == null || !section!.success) {
      return _EmptyReportState(
        title: title,
        message: 'This report section could not be loaded.',
      );
    }
    final data = section!;
    final sectionCategory = _sectionCategoryFromTitle(title);
    final hasSummary =
        data.summary.isNotEmpty || data.breakdowns.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReportSectionHeader(title: title),
        const SizedBox(height: 12),
        if (hasSummary)
          _buildReportSummarySection(
            sectionCategory: sectionCategory,
            metrics: data.summary,
            breakdowns: data.breakdowns,
            payments: paymentsCompanion,
          ),
        if (data.details.columns.isNotEmpty &&
            sectionCategory != MarketplaceReportCategory.payments) ...[
          const SizedBox(height: 16),
          _StaticDetailSection(payload: data),
        ],
      ],
    );
  }
}

Widget _buildReportSummarySection({
  AdminReportType? reportType,
  MarketplaceReportCategory? sectionCategory,
  required List<MarketplaceReportMetric> metrics,
  required List<MarketplaceReportBreakdown> breakdowns,
  MarketplaceReportPayload? payments,
}) {
  final useOrdersTransactionsGrid =
      reportType == AdminReportType.ordersTransactions ||
          sectionCategory == MarketplaceReportCategory.orders;
  if (useOrdersTransactionsGrid) {
    return MarketplaceReportOrdersTransactionsGrid(
      orderMetrics: metrics,
      orderBreakdowns: breakdowns,
      paymentMetrics: payments?.summary ?? const [],
      paymentBreakdowns: payments?.breakdowns ?? const [],
    );
  }

  return MarketplaceReportSummaryLayout(
    reportType: reportType,
    sectionCategory: sectionCategory,
    metrics: metrics,
    breakdowns: breakdowns,
  );
}

MarketplaceReportCategory? _sectionCategoryFromTitle(String title) {
  if (title == adminReportTypeLabel(AdminReportType.ordersTransactions)) {
    return MarketplaceReportCategory.orders;
  }
  for (final category in marketplaceReportAllSectionCategories) {
    if (_allSectionTitle(category) == title) return category;
  }
  return null;
}

class _ReportContextBar extends StatelessWidget {
  const _ReportContextBar({
    required this.title,
    required this.periodLabel,
  });

  final String title;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTypography.sectionTitle.copyWith(fontSize: 16),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            periodLabel,
            style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ReportSectionHeader extends StatelessWidget {
  const _ReportSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.sectionTitle.copyWith(fontSize: 15),
    );
  }
}

class _StaticDetailSection extends StatelessWidget {
  const _StaticDetailSection({required this.payload});

  final MarketplaceReportPayload payload;

  @override
  Widget build(BuildContext context) {
    final details = payload.details;
    if (details.columns.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Detailed records',
              style: AppTypography.sectionTitle.copyWith(fontSize: 15),
            ),
            Spacer(),
            Text(
              '${payload.detailTotal} record${payload.detailTotal == 1 ? '' : 's'}',
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (details.rows.isEmpty)
          const _EmptyReportState(
            title: 'No records in period',
            message: 'Nothing was recorded for this report type in the selected date range.',
          )
        else ...[
          AdminDataTable(
            columns: details.columns,
            minWidth: _detailTableMinWidth(details.columns),
            columnFlex: _detailColumnFlex(details.columns),
            columnAlignments: _columnAlignmentsForHeaders(details.columns),
            columnSpacing: _uniformDetailColumnSpacing(details.columns),
            columnGapsAfter: _detailColumnGapsAfter(details.columns),
            rows: _detailTableRows(details.columns, details.rows),
            emptyTitle: 'No records',
            emptyMessage: 'No rows for this period.',
          ),
          if (payload.detailTotal > details.rows.length)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Showing ${details.rows.length} of ${payload.detailTotal}. '
                'Select this report type alone to browse pages, or export for the full dataset.',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
            ),
        ],
      ],
    );
  }
}

class _ExportActions extends StatelessWidget {
  const _ExportActions({
    required this.isExporting,
    required this.onPdf,
    required this.onExcel,
  });

  final bool isExporting;
  final VoidCallback onPdf;
  final VoidCallback onExcel;

  static const _pdfRed = Color(0xFFDC2626);
  static const _excelGreen = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (isExporting)
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        _ExportButton(
          label: 'Export PDF',
          icon: Icons.picture_as_pdf_outlined,
          background: _pdfRed,
          onPressed: isExporting ? null : onPdf,
        ),
        _ExportButton(
          label: 'Export Excel',
          icon: Icons.grid_on_outlined,
          background: _excelGreen,
          onPressed: isExporting ? null : onExcel,
        ),
      ],
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color background;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Material(
      color: enabled ? background : AppColors.border,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTypography.tableBodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<AlignmentGeometry> _columnAlignmentsForHeaders(List<String> columns) {
  if (_isBiddingDetailColumns(columns)) {
    return const [
      Alignment.centerLeft,
      Alignment.centerLeft,
      Alignment.centerLeft,
      Alignment.center,
      Alignment.center,
    ];
  }
  return [
    for (final column in columns)
      _isNumericReportColumn(column)
          ? Alignment.centerRight
          : Alignment.centerLeft,
  ];
}

bool _isReportDateTimeColumn(String header) {
  final h = header.trim().toLowerCase();
  return h.contains('date') ||
      h == 'created' ||
      h == 'updated' ||
      h == 'ends' ||
      h == 'submitted' ||
      h == 'reviewed' ||
      h == 'resolved';
}

const _disputeResolvedStatuses = {'resolved', 'dismissed'};

bool _isDisputesDetailColumns(List<String> columns) {
  if (columns.length != 5) return false;
  return columns[0].trim().toLowerCase() == 'type' &&
      columns[4].trim().toLowerCase() == 'resolved';
}

bool _isUnsetResolvedPlaceholder(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed == '—') return true;
  if (trimmed.toLowerCase() == 'not yet resolved') return true;
  if (trimmed.contains('â€') || trimmed == 'â€"') return true;
  return false;
}

String _formatDisputeResolvedCell(
  String raw,
  List<dynamic> row,
  List<String> columns,
) {
  final statusIdx =
      columns.indexWhere((c) => c.trim().toLowerCase() == 'status');
  final status = (statusIdx >= 0 ? row[statusIdx]?.toString() : null)
          ?.trim()
          .toLowerCase()
          .replaceAll(' ', '_') ??
      '';

  if (!_disputeResolvedStatuses.contains(status)) {
    return 'Not yet resolved';
  }
  if (_isUnsetResolvedPlaceholder(raw)) {
    return 'Not yet resolved';
  }
  return _formatMarketplaceReportDetailValue('Submitted', raw);
}

String _formatDetailCellValue(
  List<String> columns,
  List<dynamic> row,
  int columnIndex,
) {
  final header = columns[columnIndex];
  final raw = row[columnIndex]?.toString() ?? '';
  if (_isDisputesDetailColumns(columns) &&
      header.trim().toLowerCase() == 'resolved') {
    return _formatDisputeResolvedCell(raw, row, columns);
  }
  return _formatMarketplaceReportDetailValue(header, raw);
}

String _formatMarketplaceReportDetailValue(String columnHeader, String raw) {
  final header = columnHeader.trim().toLowerCase();
  if (header == 'total' || header == 'amount') {
    return formatAdminReportPesoAmount(raw);
  }
  if (!_isReportDateTimeColumn(columnHeader)) return raw;
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == '—') return raw;
  if (RegExp(r'^[A-Z]{3} \d{1,2}, \d{4} \d{1,2}:\d{2} [AP]M$').hasMatch(trimmed)) {
    return trimmed;
  }
  final legacy = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$').firstMatch(trimmed);
  if (legacy != null) {
    final manilaWall = DateTime.utc(
      int.parse(legacy.group(1)!),
      int.parse(legacy.group(2)!),
      int.parse(legacy.group(3)!),
      int.parse(legacy.group(4)!),
      int.parse(legacy.group(5)!),
    );
    final instant = manilaWall.subtract(const Duration(hours: 8));
    return formatAdminReportDateTime(instant);
  }
  return raw;
}

bool _isBiddingDetailColumns(List<String> columns) {
  if (columns.length != 5) return false;
  bool eq(int i, String expected) =>
      columns[i].trim().toLowerCase() == expected.toLowerCase();
  return eq(0, 'Created') &&
      eq(3, 'Winner') &&
      columns[4].toLowerCase().contains('bid');
}

bool _isOrdersTransactionsDetailColumns(List<String> columns) {
  if (columns.length != 5) return false;
  bool eq(int i, String expected) =>
      columns[i].trim().toLowerCase() == expected.toLowerCase();
  return eq(0, 'Type') &&
      eq(2, 'Total') &&
      columns[3].toLowerCase().contains('date') &&
      eq(4, 'Status');
}

bool _isSecurityAuditDetailColumns(List<String> columns) {
  if (columns.length != 5) return false;
  bool eq(int i, String expected) =>
      columns[i].trim().toLowerCase() == expected.toLowerCase();
  return eq(0, 'Category') &&
      eq(1, 'Event') &&
      eq(2, 'When') &&
      eq(3, 'Status') &&
      eq(4, 'Summary');
}

bool _isSecurityAuditSummaryColumn(List<String> columns, int columnIndex) {
  return _isSecurityAuditDetailColumns(columns) &&
      columns[columnIndex].trim().toLowerCase() == 'summary';
}

/// Equal gutter between adjacent columns (half applied to each cell edge).
double _uniformDetailColumnSpacing(List<String> columns) {
  if (_isOrdersTransactionsDetailColumns(columns)) return 0;
  if (_isBiddingDetailColumns(columns)) return 0;
  if (_isPaymentsDetailColumns(columns)) return 16;
  return 0;
}

/// Per-column gaps; index [i] is space after column [i] (before column [i + 1]).
List<double>? _detailColumnGapsAfter(List<String> columns) {
  if (_isOrdersTransactionsDetailColumns(columns)) {
    return const [14, 14, 56, 14];
  }
  if (_isBiddingDetailColumns(columns)) {
    // Created | Status | Ends  |  Winner  |  Bid round
    return const [12, 12, 24, 24];
  }
  return null;
}

List<int>? _detailColumnFlex(List<String> columns) {
  if (_isBiddingDetailColumns(columns)) {
    return const [3, 2, 3, 2, 3];
  }
  if (_isSecurityAuditDetailColumns(columns)) {
    return const [2, 2, 3, 2, 5];
  }
  return null;
}

List<List<Widget>> _detailTableRows(
  List<String> columns,
  List<List<dynamic>> rows,
) {
  final alignments = _columnAlignmentsForHeaders(columns);
  final styled = _uniformDetailColumnSpacing(columns) > 0 ||
      _detailColumnGapsAfter(columns) != null ||
      _isBiddingDetailColumns(columns) ||
      _isSecurityAuditDetailColumns(columns);
  return rows
      .map(
        (row) => [
          for (var i = 0; i < row.length; i++)
            styled
                ? _reportDetailTableCell(
                    _formatDetailCellValue(columns, row, i),
                    i < alignments.length
                        ? alignments[i]
                        : Alignment.centerLeft,
                    columnIndex: i,
                    columns: columns,
                    maxLines: _isSecurityAuditSummaryColumn(columns, i)
                        ? null
                        : 2,
                  )
                : AdminTableCellText(
                    primary: _formatDetailCellValue(columns, row, i),
                  ),
        ],
      )
      .toList();
}

Widget _reportDetailTableCell(
  String text,
  AlignmentGeometry alignment, {
  int? columnIndex,
  List<String>? columns,
  int? maxLines = 2,
}) {
  final textAlign = switch (alignment) {
    Alignment.centerRight => TextAlign.right,
    Alignment.center => TextAlign.center,
    _ => TextAlign.left,
  };
  EdgeInsets padding = EdgeInsets.zero;
  if (columnIndex != null &&
      columns != null &&
      _isOrdersTransactionsDetailColumns(columns)) {
    if (columnIndex == 2) {
      padding = const EdgeInsets.only(right: 8);
    } else if (columnIndex == 3) {
      padding = const EdgeInsets.only(left: 8);
    }
  }
  return Padding(
    padding: padding,
    child: SizedBox(
      width: double.infinity,
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: AppTypography.tableBodyMedium.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

double _detailTableMinWidth(List<String> columns) {
  if (_isOrdersTransactionsDetailColumns(columns)) return 1040;
  if (_isBiddingDetailColumns(columns)) return 980;
  if (_isSecurityAuditDetailColumns(columns)) return 1100;
  if (_isPaymentsDetailColumns(columns)) return 720;
  return 720;
}

bool _isPaymentsDetailColumns(List<String> columns) {
  if (columns.length != 4) return false;
  return columns[0].trim().toLowerCase() == 'updated' &&
      columns[2].trim().toLowerCase() == 'amount';
}

bool _isNumericReportColumn(String column) {
  final lower = column.toLowerCase();
  return lower == 'value' ||
      lower == 'count' ||
      lower.contains('amount') ||
      lower == 'total' ||
      lower.contains('#') ||
      lower.contains('round') ||
      lower.contains('rate');
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.controller,
    required this.payload,
  });

  final AdminMarketplaceReportsController controller;
  final MarketplaceReportPayload payload;

  @override
  Widget build(BuildContext context) {
    if (payload.details.columns.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasRows = payload.details.rows.isNotEmpty;
    final filteredEmpty =
        controller.hasActiveFilters && !hasRows && controller.detailTotal == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Detailed records',
              style: AppTypography.sectionTitle.copyWith(fontSize: 15),
            ),
            Spacer(),
            Text(
              '${controller.detailTotal} record${controller.detailTotal == 1 ? '' : 's'}',
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!hasRows)
          _EmptyReportState(
            title: filteredEmpty ? 'No matching records' : 'No records in period',
            message: filteredEmpty
                ? 'Try adjusting or resetting your filters.'
                : 'Nothing was recorded for this category in the selected date range.',
            onRetry: filteredEmpty ? controller.resetFilters : null,
            retryLabel: filteredEmpty ? 'Reset filters' : null,
          )
        else ...[
          AdminDataTable(
            columns: payload.details.columns,
            minWidth: _detailTableMinWidth(payload.details.columns),
            columnFlex: _detailColumnFlex(payload.details.columns),
            columnAlignments: _columnAlignmentsForHeaders(payload.details.columns),
            columnSpacing: _uniformDetailColumnSpacing(payload.details.columns),
            columnGapsAfter: _detailColumnGapsAfter(payload.details.columns),
            rows: _detailTableRows(payload.details.columns, payload.details.rows),
            isLoading: controller.isLoading,
            emptyTitle: 'No records',
            emptyMessage: 'No rows match the selected filters.',
            onResetFilters: controller.resetFilters,
          ),
          if (controller.detailTotal > controller.pageSize) ...[
            const SizedBox(height: 12),
            AdminPagination(
              currentPage: controller.page,
              totalItems: controller.detailTotal,
              pageSize: controller.pageSize,
              onPageChanged: controller.setPage,
              isLoading: controller.isLoading,
            ),
          ],
          if (payload.details.truncated)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Export includes up to ${marketplaceReportExportDetailCap} rows.',
                style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
              ),
            ),
        ],
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(child: Text(message, style: AppTypography.tableBodyMedium)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _EmptyReportState extends StatelessWidget {
  const _EmptyReportState({
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.tableBodyMedium.copyWith(fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            message,
            style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: Text(retryLabel ?? 'Retry'),
            ),
          ],
        ],
      ),
    );
  }
}

