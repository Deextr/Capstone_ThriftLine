import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../domain/davao_barangay.dart';

/// Searchable Davao City barangay picker. Selection is limited to [barangays].
class DavaoBarangayField extends StatelessWidget {
  const DavaoBarangayField({
    super.key,
    required this.barangays,
    required this.selected,
    required this.loading,
    this.error,
    required this.onRetry,
    required this.onSelected,
  });

  final List<DavaoBarangay> barangays;
  final DavaoBarangay? selected;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<DavaoBarangay> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Barangay',
          style: AppTypography.label.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Davao City only',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppConstants.spacingXs),
        if (loading)
          Container(
            height: 52,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text('Loading Davao City barangays…', style: AppTypography.body),
              ],
            ),
          )
        else if (error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error!, style: AppTypography.body.copyWith(color: AppColors.error)),
                const SizedBox(height: 8),
                ThriftButton(
                  label: 'Retry',
                  variant: ThriftButtonVariant.outline,
                  expand: false,
                  onPressed: onRetry,
                ),
              ],
            ),
          )
        else if (barangays.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Davao City barangays were returned.',
                  style: AppTypography.body,
                ),
                const SizedBox(height: 8),
                ThriftButton(
                  label: 'Retry',
                  variant: ThriftButtonVariant.outline,
                  expand: false,
                  onPressed: onRetry,
                ),
              ],
            ),
          )
        else
          InkWell(
            onTap: () => _openPicker(context),
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.location_city_outlined,
                  color: AppColors.textHint,
                  size: 20,
                ),
                suffixIcon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
              child: Text(
                selected?.name ?? 'Select barangay',
                style: AppTypography.body.copyWith(
                  color: selected == null ? AppColors.textHint : AppColors.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<DavaoBarangay>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BarangaySheet(barangays: barangays),
    );
    if (result != null) onSelected(result);
  }
}

class _BarangaySheet extends StatefulWidget {
  const _BarangaySheet({required this.barangays});

  final List<DavaoBarangay> barangays;

  @override
  State<_BarangaySheet> createState() => _BarangaySheetState();
}

class _BarangaySheetState extends State<_BarangaySheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.barangays
        : widget.barangays
            .where((b) => b.name.toLowerCase().contains(q))
            .toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Davao City barangays', style: AppTypography.subheading),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search barangay',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matching Davao City barangay.',
                        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final barangay = filtered[index];
                        return ListTile(
                          title: Text(barangay.name),
                          subtitle: const Text(DavaoBarangay.cityName),
                          onTap: () => Navigator.of(context).pop(barangay),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
