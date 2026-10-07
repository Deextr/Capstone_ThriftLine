import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/skeleton_widgets.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/admin_dashboard_models.dart';
import 'admin_dashboard_widgets.dart';

final _kNumberFormat = NumberFormat.decimalPattern();

// ============================================================================
// 1. ADMIN PAGE HEADER
// ============================================================================

class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
    this.breadcrumbs,
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final Widget? breadcrumbs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (breadcrumbs != null) ...[breadcrumbs!, const SizedBox(height: 8)],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.pageTitle),
                    if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: AppTypography.body.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(width: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions!,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 2. ADMIN STAT / KPI CARD
// ============================================================================

class AdminStatCard extends StatefulWidget {
  const AdminStatCard({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    this.accentColor = AppColors.primary,
    this.isSelected = false,
    this.onTap,
    this.subtitle,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  State<AdminStatCard> createState() => _AdminStatCardState();
}

class _AdminStatCardState extends State<AdminStatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isClickable = widget.onTap != null;
    final color = widget.accentColor;

    return Semantics(
      button: isClickable,
      selected: widget.isSelected,
      label: '${widget.label}: ${widget.count}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: isClickable ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? color.withValues(alpha: 0.06)
                  : _isHovered && isClickable
                  ? AppColors.surfaceVariant.withValues(alpha: 0.5)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: widget.isSelected
                    ? color.withValues(alpha: 0.8)
                    : _isHovered && isClickable
                    ? color.withValues(alpha: 0.4)
                    : AppColors.border,
                width: widget.isSelected ? 1.5 : 1.0,
              ),
              boxShadow: [
                if (widget.isSelected || (_isHovered && isClickable))
                  BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, size: 20, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _kNumberFormat.format(widget.count),
                        style: AppTypography.heading.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.label,
                        style: AppTypography.label.copyWith(
                          color: widget.isSelected
                              ? color
                              : AppColors.textSecondary,
                          fontWeight: widget.isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: AppTypography.caption.copyWith(
                            fontSize: 11,
                            color: AppColors.textHint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.isSelected)
                  Icon(Icons.check_circle_rounded, size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 3. ADMIN PAGINATION COMPONENT
// ============================================================================

class AdminPagination extends StatelessWidget {
  const AdminPagination({
    super.key,
    required this.currentPage,
    required this.totalItems,
    required this.pageSize,
    required this.onPageChanged,
    this.pageSizeOptions = const [10, 25, 50],
    this.onPageSizeChanged,
    this.isLoading = false,
  });

  /// 0-indexed current page.
  final int currentPage;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final List<int> pageSizeOptions;
  final ValueChanged<int>? onPageSizeChanged;
  final bool isLoading;

  int get totalPages =>
      totalItems <= 0 ? 1 : ((totalItems + pageSize - 1) ~/ pageSize);

  @override
  Widget build(BuildContext context) {
    final startItem = totalItems == 0 ? 0 : (currentPage * pageSize) + 1;
    final endItem = (currentPage * pageSize + pageSize).clamp(0, totalItems);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 840;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: isCompact
              ? _buildCompact(context, startItem, endItem)
              : _buildDesktop(context, startItem, endItem),
        );
      },
    );
  }

  Widget _buildDesktop(BuildContext context, int startItem, int endItem) {
    return Row(
      children: [
        // Range text: Showing 1–10 of 126 results
        Text(
          totalItems == 0
              ? 'Showing 0 results'
              : 'Showing ${_kNumberFormat.format(startItem)}–${_kNumberFormat.format(endItem)} of ${_kNumberFormat.format(totalItems)} results',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        // Rows per page dropdown
        if (onPageSizeChanged != null && pageSizeOptions.isNotEmpty) ...[
          Text(
            'Rows per page:',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
              color: AppColors.surface,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: pageSizeOptions.contains(pageSize)
                    ? pageSize
                    : pageSizeOptions.first,
                isDense: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                style: AppTypography.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                items: [
                  for (final opt in pageSizeOptions)
                    DropdownMenuItem(value: opt, child: Text('$opt')),
                ],
                onChanged: isLoading
                    ? null
                    : (v) => v != null ? onPageSizeChanged!(v) : null,
              ),
            ),
          ),
          const SizedBox(width: 20),
        ],
        // Page buttons
        _buildPageButtons(),
      ],
    );
  }

  Widget _buildCompact(BuildContext context, int startItem, int endItem) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              totalItems == 0
                  ? 'Showing 0 results'
                  : 'Showing ${_kNumberFormat.format(startItem)}–${_kNumberFormat.format(endItem)} of ${_kNumberFormat.format(totalItems)} results',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (onPageSizeChanged != null && pageSizeOptions.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Rows per page:',
                    style: AppTypography.caption.copyWith(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(4),
                      color: AppColors.surface,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: pageSizeOptions.contains(pageSize)
                            ? pageSize
                            : pageSizeOptions.first,
                        isDense: true,
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        items: [
                          for (final opt in pageSizeOptions)
                            DropdownMenuItem(value: opt, child: Text('$opt')),
                        ],
                        onChanged: isLoading
                            ? null
                            : (v) => v != null ? onPageSizeChanged!(v) : null,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PaginationNavButton(
              icon: Icons.chevron_left,
              tooltip: 'Previous page',
              isEnabled: currentPage > 0 && !isLoading,
              onTap: () => onPageChanged(currentPage - 1),
            ),
            const SizedBox(width: 12),
            Text(
              'Page ${currentPage + 1} of $totalPages',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            _PaginationNavButton(
              icon: Icons.chevron_right,
              tooltip: 'Next page',
              isEnabled: currentPage + 1 < totalPages && !isLoading,
              onTap: () => onPageChanged(currentPage + 1),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPageButtons() {
    final pages = _calculatePageSequence(currentPage + 1, totalPages);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Prev button
        _PaginationNavButton(
          icon: Icons.chevron_left,
          tooltip: 'Previous page',
          isEnabled: currentPage > 0 && !isLoading,
          onTap: () => onPageChanged(currentPage - 1),
        ),
        const SizedBox(width: 4),
        for (final item in pages) ...[
          if (item == -1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '…',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textHint,
                ),
              ),
            )
          else
            _PageNumberButton(
              pageNumber: item,
              isSelected: item == currentPage + 1,
              isLoading: isLoading,
              onTap: () => onPageChanged(item - 1),
            ),
          const SizedBox(width: 4),
        ],
        // Next button
        _PaginationNavButton(
          icon: Icons.chevron_right,
          tooltip: 'Next page',
          isEnabled: currentPage + 1 < totalPages && !isLoading,
          onTap: () => onPageChanged(currentPage + 1),
        ),
      ],
    );
  }

  static List<int> _calculatePageSequence(int current, int total) {
    if (total <= 7) {
      return List.generate(total, (i) => i + 1);
    }
    if (current <= 4) {
      return [1, 2, 3, 4, 5, -1, total];
    }
    if (current >= total - 3) {
      return [1, -1, total - 4, total - 3, total - 2, total - 1, total];
    }
    return [1, -1, current - 1, current, current + 1, -1, total];
  }
}

class _PaginationNavButton extends StatelessWidget {
  const _PaginationNavButton({
    required this.icon,
    required this.tooltip,
    required this.isEnabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
              color: isEnabled
                  ? AppColors.surface
                  : AppColors.surfaceVariant.withValues(alpha: 0.5),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isEnabled ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageNumberButton extends StatefulWidget {
  const _PageNumberButton({
    required this.pageNumber,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  final int pageNumber;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  State<_PageNumberButton> createState() => _PageNumberButtonState();
}

class _PageNumberButtonState extends State<_PageNumberButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.isSelected;
    final bg = selected
        ? AppColors.primary
        : _hovered
        ? AppColors.surfaceVariant
        : AppColors.surface;
    final fg = selected
        ? Colors.white
        : _hovered
        ? AppColors.primary
        : AppColors.textPrimary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.isLoading || selected ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            '${widget.pageNumber}',
            style: AppTypography.caption.copyWith(
              color: fg,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 4. ADMIN SEARCH FIELD
// ============================================================================

class AdminSearchField extends StatefulWidget {
  const AdminSearchField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.hintText = 'Search...',
    this.width = 280,
    this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final String hintText;
  final double width;
  final VoidCallback? onClear;

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;

    return SizedBox(
      width: widget.width,
      height: 38,
      child: TextField(
        controller: widget.controller,
        style: AppTypography.body.copyWith(fontSize: 13),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: AppTypography.body.copyWith(
            color: AppColors.textHint,
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 18,
            color: AppColors.textSecondary,
          ),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: 'Clear search',
                  onPressed: () {
                    widget.controller.clear();
                    widget.onSubmitted('');
                    widget.onClear?.call();
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
        ),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

// ============================================================================
// 5. ADMIN FILTER DROPDOWN
// ============================================================================

class AdminFilterDropdown<T> extends StatelessWidget {
  const AdminFilterDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.prefixIcon,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? label;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            size: 18,
            color: AppColors.textSecondary,
          ),
          style: AppTypography.body.copyWith(
            fontSize: 13,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ============================================================================
// 6. ADMIN DATE FILTER
// ============================================================================

class AdminDateFilter extends StatelessWidget {
  const AdminDateFilter({
    super.key,
    required this.window,
    required this.onChanged,
  });

  final AdminDateWindow? window;
  final ValueChanged<AdminDateWindow?> onChanged;

  String _label() {
    if (window == null) return 'All Time';
    return switch (window!.preset) {
      AdminDatePreset.today => 'Today',
      AdminDatePreset.last7Days => 'Last 7 Days',
      AdminDatePreset.last30Days => 'Last 30 Days',
      AdminDatePreset.thisMonth => 'This Month',
      AdminDatePreset.lastYear => 'Last Year',
      AdminDatePreset.custom => window!.chipLabel,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isActive = window != null;

    return PopupMenuButton<AdminDatePreset?>(
      tooltip: 'Filter by date',
      offset: const Offset(0, 42),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: const BorderSide(color: AppColors.border),
      ),
      onSelected: (preset) async {
        if (preset == null) {
          onChanged(null);
          return;
        }
        if (preset == AdminDatePreset.custom) {
          final picked = await showAdminCustomRangePicker(
            context,
            initial: window,
          );
          if (picked != null) onChanged(picked);
          return;
        }
        final newWindow = switch (preset) {
          AdminDatePreset.today => AdminDateWindow.today(),
          AdminDatePreset.last7Days => AdminDateWindow.last7Days(),
          AdminDatePreset.last30Days => AdminDateWindow.last30Days(),
          AdminDatePreset.thisMonth => AdminDateWindow.thisMonth(),
          AdminDatePreset.lastYear => AdminDateWindow.lastYear(),
          AdminDatePreset.custom => AdminDateWindow.last7Days(),
        };
        onChanged(newWindow);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: null, child: Text('All Time')),
        PopupMenuItem(value: AdminDatePreset.today, child: Text('Today')),
        PopupMenuItem(
          value: AdminDatePreset.last7Days,
          child: Text('Last 7 Days'),
        ),
        PopupMenuItem(
          value: AdminDatePreset.last30Days,
          child: Text('Last 30 Days'),
        ),
        PopupMenuItem(
          value: AdminDatePreset.thisMonth,
          child: Text('This Month'),
        ),
        PopupMenuItem(
          value: AdminDatePreset.lastYear,
          child: Text('Last Year'),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: AdminDatePreset.custom,
          child: Text('Custom Range...'),
        ),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.06)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.6)
                : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 15,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              _label(),
              style: AppTypography.body.copyWith(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: isActive ? AppColors.primary : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 7. ADMIN FILTER BAR
// ============================================================================

class AdminFilterBar extends StatelessWidget {
  const AdminFilterBar({
    super.key,
    required this.children,
    this.hasActiveFilters = false,
    this.onReset,
    this.trailing,
  });

  final List<Widget> children;
  final bool hasActiveFilters;
  final VoidCallback? onReset;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...children,
                if (hasActiveFilters && onReset != null)
                  TextButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Clear filters'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      textStyle: AppTypography.label.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
  }
}

// ============================================================================
// 8. ADMIN STATUS BADGE
// ============================================================================

class AdminStatusBadge extends StatelessWidget {
  const AdminStatusBadge({super.key, required this.status, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final s = status.trim().toLowerCase();
    final display = label ?? _defaultLabel(s);

    final (Color fg, Color bg) = switch (s) {
      'pending' ||
      'awaiting_review' ||
      'under_review' ||
      'open' ||
      'payment_pending' => (const Color(0xFF92400E), const Color(0xFFFFFBEB)),
      'approved' ||
      'active' ||
      'success' ||
      'completed' ||
      'paid' ||
      'resolved' ||
      'shipped' => (
        AppColors.primary,
        AppColors.primary.withValues(alpha: 0.08),
      ),
      'rejected' ||
      'failed' ||
      'banned' ||
      'cancelled' ||
      'dismissed' ||
      'closed' ||
      'suspended' ||
      'blocked' => (const Color(0xFF9F1239), const Color(0xFFFFF1F2)),
      'action_taken' ||
      'processing' => (const Color(0xFF475569), const Color(0xFFF1F5F9)),
      _ => (AppColors.textSecondary, AppColors.surfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Text(
        display,
        style: AppTypography.badge.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }

  static String _defaultLabel(String s) => switch (s) {
    'under_review' => 'Under review',
    'payment_pending' => 'Payment pending',
    'action_taken' => 'Action taken',
    _ =>
      s.isEmpty
          ? 'Unknown'
          : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' '),
  };
}

// ============================================================================
// 9. ADMIN DATA TABLE WITH SKELETON & EMPTY STATE
// ============================================================================

class AdminDataTable extends StatelessWidget {
  const AdminDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.isLoading = false,
    this.emptyTitle = 'No records found',
    this.emptyMessage = 'Try adjusting your search or filters.',
    this.onResetFilters,
    this.minWidth = 720,
    this.columnFlex,
    this.onRowTap,
  });

  final List<String> columns;
  final List<List<Widget>> rows;
  final bool isLoading;
  final String emptyTitle;
  final String emptyMessage;
  final VoidCallback? onResetFilters;
  final double minWidth;
  final List<int>? columnFlex;
  final List<VoidCallback?>? onRowTap;

  List<int> get _flex =>
      columnFlex ?? List<int>.filled(columns.length, 1, growable: false);

  @override
  Widget build(BuildContext context) {
    if (isLoading && rows.isEmpty) {
      return AdminTableSkeleton(
        columns: columns,
        rowCount: 6,
        columnFlex: _flex,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final parentWidth = constraints.maxWidth;
        final tableWidth = parentWidth.isFinite && parentWidth > 0
            ? (parentWidth < minWidth ? minWidth : parentWidth)
            : minWidth;
        final needsScroll = parentWidth.isFinite && parentWidth < minWidth;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Scrollbar(
              thumbVisibility: needsScroll,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _AdminTableHeaderRow(columns: columns, flex: _flex),
                      if (!isLoading && rows.isEmpty)
                        _AdminTableEmptyBody(
                          title: emptyTitle,
                          message: emptyMessage,
                          onResetFilters: onResetFilters,
                        )
                      else
                        for (var i = 0; i < rows.length; i++)
                          _AdminTableDataRow(
                            cells: rows[i],
                            flex: _flex,
                            onTap: onRowTap != null && i < onRowTap!.length
                                ? onRowTap![i]
                                : null,
                            showDivider: i < rows.length - 1,
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdminTableHeaderRow extends StatelessWidget {
  const _AdminTableHeaderRow({required this.columns, required this.flex});

  final List<String> columns;
  final List<int> flex;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(
              flex: i < flex.length ? flex[i] : 1,
              child: Text(
                columns[i].toUpperCase(),
                style: AppTypography.tableHeader.copyWith(
                  fontSize: 11,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdminTableDataRow extends StatefulWidget {
  const _AdminTableDataRow({
    required this.cells,
    required this.flex,
    this.onTap,
    this.showDivider = true,
  });

  final List<Widget> cells;
  final List<int> flex;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  State<_AdminTableDataRow> createState() => _AdminTableDataRowState();
}

class _AdminTableDataRowState extends State<_AdminTableDataRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;

    Widget row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _hovered && interactive
            ? AppColors.primary.withValues(alpha: 0.03)
            : AppColors.surface,
        border: widget.showDivider
            ? const Border(bottom: BorderSide(color: AppColors.border))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < widget.cells.length; i++)
            Expanded(
              flex: i < widget.flex.length ? widget.flex[i] : 1,
              child: Align(
                alignment: Alignment.centerLeft,
                child: widget.cells[i],
              ),
            ),
        ],
      ),
    );

    if (interactive) {
      row = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: widget.onTap, child: row),
        ),
      );
    }

    return row;
  }
}

class _AdminTableEmptyBody extends StatelessWidget {
  const _AdminTableEmptyBody({
    required this.title,
    required this.message,
    this.onResetFilters,
  });

  final String title;
  final String message;
  final VoidCallback? onResetFilters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTypography.cardTitle.copyWith(fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          if (onResetFilters != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: onResetFilters,
              child: const Text('Reset filters'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Primary + optional secondary line for table cells.
class AdminTableCellText extends StatelessWidget {
  const AdminTableCellText({
    super.key,
    required this.primary,
    this.secondary,
    this.primaryStyle,
  });

  final String primary;
  final String? secondary;
  final TextStyle? primaryStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          primary,
          style:
              primaryStyle ??
              AppTypography.tableBodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (secondary != null && secondary!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            secondary!,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class AdminTableApplicantCell extends StatelessWidget {
  const AdminTableApplicantCell({
    super.key,
    required this.displayName,
    this.secondaryLine,
    this.avatarName,
  });

  final String displayName;
  final String? secondaryLine;
  final String? avatarName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ThriftAvatar(imageUrl: '', name: avatarName ?? displayName, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: AdminTableCellText(
            primary: displayName,
            secondary: secondaryLine,
          ),
        ),
      ],
    );
  }
}

class AdminTableDateCell extends StatelessWidget {
  const AdminTableDateCell({
    super.key,
    required this.dateTime,
    this.showTimeTooltip = true,
  });

  final DateTime dateTime;
  final bool showTimeTooltip;

  @override
  Widget build(BuildContext context) {
    final label = formatAdminTableDate(dateTime);
    final child = Text(label, style: AppTypography.tableBody);
    if (!showTimeTooltip) return child;
    return Tooltip(
      message: formatAdminTableDateTime(dateTime),
      waitDuration: const Duration(milliseconds: 400),
      child: child,
    );
  }
}

class AdminTableLinkAction extends StatelessWidget {
  const AdminTableLinkAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ============================================================================
// 10. ADMIN TABLE SKELETON
// ============================================================================

class AdminTableSkeleton extends StatelessWidget {
  const AdminTableSkeleton({
    super.key,
    required this.columns,
    this.rowCount = 5,
    this.columnFlex,
  });

  final List<String> columns;
  final int rowCount;
  final List<int>? columnFlex;

  @override
  Widget build(BuildContext context) {
    final flex = columnFlex ?? List.filled(columns.length, 1);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Column(
          children: [
            _AdminTableHeaderRow(columns: columns, flex: flex),
            for (int i = 0; i < rowCount; i++)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  border: i < rowCount - 1
                      ? const Border(
                          bottom: BorderSide(color: AppColors.border),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    for (int j = 0; j < columns.length; j++)
                      Expanded(
                        flex: j < flex.length ? flex[j] : 1,
                        child: ShimmerBox(
                          width: j == 0
                              ? 140
                              : (j == columns.length - 1 ? 56 : 88),
                          height: 12,
                          radius: 4,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
