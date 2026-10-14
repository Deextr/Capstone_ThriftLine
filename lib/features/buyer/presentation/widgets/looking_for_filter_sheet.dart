import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../domain/looking_for_feed_query.dart';

class LookingForFilterSheet extends StatefulWidget {
  const LookingForFilterSheet({
    super.key,
    required this.initial,
    required this.showInactiveStatus,
    required this.onApply,
  });

  final LookingForFeedFilters initial;
  final bool showInactiveStatus;
  final ValueChanged<LookingForFeedFilters> onApply;

  static Future<void> show(
    BuildContext context, {
    required LookingForFeedFilters initial,
    required bool showInactiveStatus,
    required ValueChanged<LookingForFeedFilters> onApply,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LookingForFilterSheet(
        initial: initial,
        showInactiveStatus: showInactiveStatus,
        onApply: onApply,
      ),
    );
  }

  @override
  State<LookingForFilterSheet> createState() => _LookingForFilterSheetState();
}

class _LookingForFilterSheetState extends State<LookingForFilterSheet> {
  late Set<ProductCategory> _categories;
  late bool _referenceImageOnly;
  late bool _withSizeOnly;
  late LookingForInactiveStatusFilter _inactiveStatus;
  String? _budgetPresetId;

  static List<({String id, String label, double? min, double? max})>
  get _budgetPresets => [
    (id: 'any', label: 'Any budget', min: null, max: null),
    (
      id: 'under500',
      label: 'Under ${formatCurrency(500)}',
      min: null,
      max: 500,
    ),
    (
      id: '500_1500',
      label: '${formatCurrency(500)} – ${formatCurrency(1500)}',
      min: 500,
      max: 1500,
    ),
    (
      id: '1500_5000',
      label: '${formatCurrency(1500)} – ${formatCurrency(5000)}',
      min: 1500,
      max: 5000,
    ),
    (
      id: '5000_plus',
      label: '${formatCurrency(5000)}+',
      min: 5000,
      max: null,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _categories = Set<ProductCategory>.from(widget.initial.categories);
    _referenceImageOnly = widget.initial.referenceImageOnly;
    _withSizeOnly = widget.initial.withSizeOnly;
    _inactiveStatus = widget.initial.inactiveStatus;
    _budgetPresetId = _presetIdFor(
      widget.initial.minBudget,
      widget.initial.maxBudget,
    );
  }

  String? _presetIdFor(double? min, double? max) {
    for (final p in _budgetPresets) {
      if (p.min == min && p.max == max) return p.id;
    }
    return min != null || max != null ? 'custom' : 'any';
  }

  LookingForFeedFilters _buildFilters() {
    final preset = _budgetPresets.firstWhere(
      (p) => p.id == _budgetPresetId,
      orElse: () => _budgetPresets.first,
    );
    return LookingForFeedFilters(
      categories: _categories,
      minBudget: preset.min,
      maxBudget: preset.max,
      referenceImageOnly: _referenceImageOnly,
      withSizeOnly: _withSizeOnly,
      inactiveStatus: _inactiveStatus,
    );
  }

  void _reset() {
    setState(() {
      _categories = {};
      _referenceImageOnly = false;
      _withSizeOnly = false;
      _inactiveStatus = LookingForInactiveStatusFilter.all;
      _budgetPresetId = 'any';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filters',
                      style: AppTypography.heading.copyWith(fontSize: 18),
                    ),
                  ),
                  TextButton(onPressed: _reset, child: const Text('Reset')),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Category'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ProductCategory.values.map((cat) {
                        final selected = _categories.contains(cat);
                        return FilterChip(
                          label: Text(cat.label),
                          selected: selected,
                          onSelected: (on) {
                            setState(() {
                              if (on) {
                                _categories.add(cat);
                              } else {
                                _categories.remove(cat);
                              }
                            });
                          },
                          selectedColor: AppColors.primaryLight,
                          checkmarkColor: AppColors.primaryDark,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    _sectionTitle('Budget range'),
                    const SizedBox(height: 8),
                    ..._budgetPresets.map((p) {
                      return RadioListTile<String>(
                        value: p.id,
                        groupValue: _budgetPresetId ?? 'any',
                        onChanged: (v) => setState(() => _budgetPresetId = v),
                        title: Text(
                          p.label,
                          style: AppTypography.body.copyWith(fontSize: 14),
                        ),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        activeColor: AppColors.primary,
                      );
                    }),
                    const SizedBox(height: 12),
                    _sectionTitle('More options'),
                    SwitchListTile(
                      value: _referenceImageOnly,
                      onChanged: (v) =>
                          setState(() => _referenceImageOnly = v),
                      title: const Text('Has reference photo'),
                      subtitle: const Text(
                        'Only requests that include an image',
                      ),
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.primary,
                    ),
                    SwitchListTile(
                      value: _withSizeOnly,
                      onChanged: (v) => setState(() => _withSizeOnly = v),
                      title: const Text('Size specified'),
                      subtitle: const Text(
                        'Helpful when matching inventory by size',
                      ),
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.primary,
                    ),
                    if (widget.showInactiveStatus) ...[
                      const SizedBox(height: 12),
                      _sectionTitle('Past request status'),
                      ...LookingForInactiveStatusFilter.values.map((status) {
                        return RadioListTile<LookingForInactiveStatusFilter>(
                          value: status,
                          groupValue: _inactiveStatus,
                          onChanged: (v) {
                            if (v != null) setState(() => _inactiveStatus = v);
                          },
                          title: Text(_inactiveLabel(status)),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: AppColors.primary,
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ThriftButton(
                  label: 'Apply filters',
                  onPressed: () {
                    widget.onApply(_buildFilters());
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: AppTypography.caption.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }

  String _inactiveLabel(LookingForInactiveStatusFilter status) =>
      switch (status) {
        LookingForInactiveStatusFilter.all => 'All past requests',
        LookingForInactiveStatusFilter.expired => 'Expired only',
        LookingForInactiveStatusFilter.fulfilled => 'Fulfilled / closed',
      };
}
