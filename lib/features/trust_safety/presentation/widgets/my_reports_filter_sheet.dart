import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/buyer_report_filters.dart';

class MyReportsFilterSheet extends StatefulWidget {
  const MyReportsFilterSheet({
    super.key,
    required this.initialType,
    required this.initialStatus,
    required this.onApply,
  });

  final BuyerReportTypeFilter initialType;
  final BuyerReportStatusFilter initialStatus;
  final void Function(
    BuyerReportTypeFilter type,
    BuyerReportStatusFilter status,
  )
  onApply;

  static Future<void> show(
    BuildContext context, {
    required BuyerReportTypeFilter initialType,
    required BuyerReportStatusFilter initialStatus,
    required void Function(
      BuyerReportTypeFilter type,
      BuyerReportStatusFilter status,
    )
    onApply,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MyReportsFilterSheet(
        initialType: initialType,
        initialStatus: initialStatus,
        onApply: onApply,
      ),
    );
  }

  @override
  State<MyReportsFilterSheet> createState() => _MyReportsFilterSheetState();
}

class _MyReportsFilterSheetState extends State<MyReportsFilterSheet> {
  late BuyerReportTypeFilter _type;
  late BuyerReportStatusFilter _status;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _status = widget.initialStatus;
  }

  void _resetDraft() {
    setState(() {
      _type = BuyerReportTypeFilter.all;
      _status = BuyerReportStatusFilter.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  Text(
                    'Filter reports',
                    style: AppTypography.heading.copyWith(fontSize: 18),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _resetDraft,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(title: 'Report type'),
                    ...kBuyerReportTypeFilterOptions.map(
                      (filter) => _FilterOptionTile(
                        title: buyerReportTypeSheetLabel(filter),
                        selected: _type == filter,
                        onTap: () => setState(() => _type = filter),
                      ),
                    ),
                    SizedBox(height: 12),
                    _SectionHeader(title: 'Report status'),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Text(
                        'New reports appear as Under review. Closed includes '
                        'any finished decision.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                    ...kBuyerReportStatusFilterOptions.map(
                      (filter) => _FilterOptionTile(
                        title: buyerReportStatusSheetLabel(filter),
                        selected: _status == filter,
                        onTap: () => setState(() => _status = filter),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onApply(_type, _status);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Apply filters',
                      style: AppTypography.subheading.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: AppTypography.subheading.copyWith(fontSize: 14),
      ),
    );
  }
}

class _FilterOptionTile extends StatelessWidget {
  const _FilterOptionTile({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.body.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 22,
                  color: selected ? AppColors.primary : AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
