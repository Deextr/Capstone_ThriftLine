import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/empty_state.dart';

class AdminWebTable extends StatelessWidget {
  const AdminWebTable({
    super.key,
    required this.columns,
    required this.rows,
    this.isLoading = false,
    this.emptyMessage = 'No records found.',
  });

  final List<String> columns;
  final List<List<Widget>> rows;
  final bool isLoading;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (isLoading && rows.isEmpty) {
      return Center(child: CircularProgressIndicator());
    }
    if (!isLoading && rows.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Nothing here',
        message: emptyMessage,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: MediaQuery.sizeOf(context).width - 48,
          ),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.background),
            columns: [
              for (final label in columns)
                DataColumn(
                  label: Text(
                    label,
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
            rows: [
              for (final cells in rows)
                DataRow(cells: [for (final cell in cells) DataCell(cell)]),
            ],
          ),
        ),
      ),
    );
  }
}
