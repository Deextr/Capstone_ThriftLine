import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../data/confirmed_violation_labels.dart';

class ConfirmedViolationsFilterSheet {
  static Future<void> show(
    BuildContext context, {
    required ConfirmedViolationCategoryFilter initialCategory,
    required ConfirmedViolationPenaltyFilter initialPenalty,
    required DateTime? initialDateFrom,
    required DateTime? initialDateTo,
    required void Function(
      ConfirmedViolationCategoryFilter category,
      ConfirmedViolationPenaltyFilter penalty,
      DateTime? dateFrom,
      DateTime? dateTo,
    ) onApply,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return _ConfirmedViolationsFilterSheetBody(
          initialCategory: initialCategory,
          initialPenalty: initialPenalty,
          initialDateFrom: initialDateFrom,
          initialDateTo: initialDateTo,
          onApply: onApply,
        );
      },
    );
  }
}

class _ConfirmedViolationsFilterSheetBody extends StatefulWidget {
  const _ConfirmedViolationsFilterSheetBody({
    required this.initialCategory,
    required this.initialPenalty,
    required this.initialDateFrom,
    required this.initialDateTo,
    required this.onApply,
  });

  final ConfirmedViolationCategoryFilter initialCategory;
  final ConfirmedViolationPenaltyFilter initialPenalty;
  final DateTime? initialDateFrom;
  final DateTime? initialDateTo;
  final void Function(
    ConfirmedViolationCategoryFilter category,
    ConfirmedViolationPenaltyFilter penalty,
    DateTime? dateFrom,
    DateTime? dateTo,
  ) onApply;

  @override
  State<_ConfirmedViolationsFilterSheetBody> createState() =>
      _ConfirmedViolationsFilterSheetBodyState();
}

class _ConfirmedViolationsFilterSheetBodyState
    extends State<_ConfirmedViolationsFilterSheetBody> {
  late ConfirmedViolationCategoryFilter _category;
  late ConfirmedViolationPenaltyFilter _penalty;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _penalty = widget.initialPenalty;
    _dateFrom = widget.initialDateFrom;
    _dateTo = widget.initialDateTo;
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = from ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Filter violations', style: AppTypography.heading),
          const SizedBox(height: 16),
          Text('Category', style: AppTypography.subheading),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ConfirmedViolationCategoryFilter.values.map((value) {
              return ChoiceChip(
                label: Text(confirmedViolationCategoryFilterLabel(value)),
                selected: _category == value,
                onSelected: (_) => setState(() => _category = value),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: AppTypography.caption,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text('Penalty status', style: AppTypography.subheading),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ConfirmedViolationPenaltyFilter.values.map((value) {
              return ChoiceChip(
                label: Text(confirmedViolationPenaltyFilterLabel(value)),
                selected: _penalty == value,
                onSelected: (_) => setState(() => _penalty = value),
                selectedColor: AppColors.primary.withValues(alpha: 0.15),
                labelStyle: AppTypography.caption,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text('Confirmed date', style: AppTypography.subheading),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(from: true),
                  child: Text(
                    _dateFrom == null
                        ? 'From'
                        : '${_dateFrom!.year}-${_dateFrom!.month.toString().padLeft(2, '0')}-${_dateFrom!.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickDate(from: false),
                  child: Text(
                    _dateTo == null
                        ? 'To'
                        : '${_dateTo!.year}-${_dateTo!.month.toString().padLeft(2, '0')}-${_dateTo!.day.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
            ],
          ),
          if (_dateFrom != null || _dateTo != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _dateFrom = null;
                  _dateTo = null;
                }),
                child: const Text('Clear dates'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              widget.onApply(_category, _penalty, _dateFrom, _dateTo);
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Apply filters'),
          ),
        ],
      ),
    );
  }
}
