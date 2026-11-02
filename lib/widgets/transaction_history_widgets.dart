import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/app_typography.dart';
import '../core/utils/transaction_history_format.dart';
import '../features/buyer/data/buyer_transaction.dart';
import 'thrift_widgets.dart';

/// One row in a grouped transaction list (section header or transaction).
sealed class TransactionHistoryGroupedEntry<T> {
  const TransactionHistoryGroupedEntry();

  factory TransactionHistoryGroupedEntry.header(String label) =
      TransactionHistorySectionHeaderEntry<T>;

  factory TransactionHistoryGroupedEntry.item(T transaction) =
      TransactionHistoryTransactionEntry<T>;
}

final class TransactionHistorySectionHeaderEntry<T>
    extends TransactionHistoryGroupedEntry<T> {
  TransactionHistorySectionHeaderEntry(this.label);
  final String label;
}

final class TransactionHistoryTransactionEntry<T>
    extends TransactionHistoryGroupedEntry<T> {
  TransactionHistoryTransactionEntry(this.transaction);
  final T transaction;
}

List<TransactionHistoryGroupedEntry<T>> groupTransactionsByDay<T>(
  List<T> sortedTransactions,
  DateTime Function(T) dateFor,
) {
  final entries = <TransactionHistoryGroupedEntry<T>>[];
  String? lastHeader;
  for (final transaction in sortedTransactions) {
    final header = transactionHistoryDateGroupHeader(dateFor(transaction));
    if (header != lastHeader) {
      entries.add(TransactionHistoryGroupedEntry.header(header));
      lastHeader = header;
    }
    entries.add(TransactionHistoryGroupedEntry.item(transaction));
  }
  return entries;
}

class TransactionHistoryFilterBar extends StatelessWidget {
  const TransactionHistoryFilterBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(BuyerTransactionFilter filter, String label, int count)> options;
  final BuyerTransactionFilter selected;
  final ValueChanged<BuyerTransactionFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingMd,
        12,
        AppConstants.spacingMd,
        16,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _FilterChip(
                label: options[i].$3 > 0
                    ? '${options[i].$2} (${options[i].$3})'
                    : options[i].$2,
                selected: selected == options[i].$1,
                onTap: () => onSelected(options[i].$1),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primaryDark : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class TransactionHistoryDateHeader extends StatelessWidget {
  const TransactionHistoryDateHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class TransactionHistorySectionTitle extends StatelessWidget {
  const TransactionHistorySectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: AppTypography.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class TransactionHistoryDetailRow extends StatelessWidget {
  const TransactionHistoryDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: AppTypography.body.copyWith(
                fontWeight: emphasis ? FontWeight.w700 : FontWeight.w400,
                color: valueColor ?? AppColors.textPrimary,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionHistoryProductThumb extends StatelessWidget {
  const TransactionHistoryProductThumb({
    super.key,
    required this.imageUrl,
    this.size = 52,
  });

  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = sanitizeTransactionProductImageUrl(imageUrl) ?? '';
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: url.isEmpty
            ? ColoredBox(
                color: AppColors.surfaceVariant,
                child: Icon(
                  Icons.image_outlined,
                  size: size * 0.42,
                  color: AppColors.textSecondary,
                ),
              )
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) =>
                    ColoredBox(color: AppColors.surfaceVariant),
                errorWidget: (_, _, _) => ColoredBox(
                  color: AppColors.surfaceVariant,
                  child: Icon(
                    Icons.image_outlined,
                    size: size * 0.42,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
      ),
    );
  }
}

class TransactionHistoryListTile extends StatelessWidget {
  const TransactionHistoryListTile({
    super.key,
    this.productImageUrl,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.amountCaption,
    required this.amountColor,
    required this.statusLabel,
    required this.statusVariant,
    required this.onTap,
    this.orderNumber,
    this.displayDate,
    this.notice,
    this.noticeIsAction = false,
    this.semanticsLabel,
  });

  final String? productImageUrl;
  final String title;
  final String subtitle;
  final String amount;
  final String amountCaption;
  final Color amountColor;
  final String statusLabel;
  final BadgeVariant statusVariant;
  final VoidCallback onTap;
  final String? orderNumber;
  final DateTime? displayDate;
  final String? notice;
  final bool noticeIsAction;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final orderRef = orderNumber != null
        ? formatTransactionOrderReference(orderNumber!)
        : '';
    final timeLabel = displayDate != null
        ? formatTransactionHistoryListTime(displayDate!)
        : null;

    return Semantics(
      button: true,
      label: semanticsLabel ?? '$title, $statusLabel, $amount',
      child: ThriftCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TransactionHistoryProductThumb(imageUrl: productImageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ThriftBadge(
                          label: statusLabel,
                          variant: statusVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        title,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (orderRef.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          orderRef,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (notice != null && notice!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          noticeIsAction ? '$notice Tap for details.' : notice!,
                          style: AppTypography.caption.copyWith(
                            color: noticeIsAction
                                ? AppColors.warning
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amount,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: amountColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      amountCaption,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (timeLabel != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  timeLabel,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

BadgeVariant transactionHistoryStatusVariant(BuyerTransactionStatus status) =>
    switch (status) {
      BuyerTransactionStatus.successful => BadgeVariant.success,
      BuyerTransactionStatus.refundInProgress => BadgeVariant.primary,
      BuyerTransactionStatus.refunded => BadgeVariant.warning,
    };

class TransactionHistoryEmptyState extends StatelessWidget {
  const TransactionHistoryEmptyState({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: AppTypography.subheading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class TransactionHistoryErrorState extends StatelessWidget {
  const TransactionHistoryErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Couldn\'t load transactions',
            style: AppTypography.subheading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ThriftButton(
            label: 'Try again',
            variant: ThriftButtonVariant.outline,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class GroupedTransactionHistorySliver<T> extends StatelessWidget {
  const GroupedTransactionHistorySliver({
    super.key,
    required this.transactions,
    required this.dateFor,
    required this.tileBuilder,
  });

  final List<T> transactions;
  final DateTime Function(T) dateFor;
  final Widget Function(T transaction) tileBuilder;

  @override
  Widget build(BuildContext context) {
    final grouped = groupTransactionsByDay(transactions, dateFor);
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final entry = grouped[index];
        return switch (entry) {
          TransactionHistorySectionHeaderEntry(:final label) =>
            TransactionHistoryDateHeader(label: label),
          TransactionHistoryTransactionEntry(:final transaction) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: tileBuilder(transaction),
          ),
        };
      }, childCount: grouped.length),
    );
  }
}

/// Buyer transaction history: sort order + optional date / date-range filter.
Future<void> showBuyerTransactionHistorySortSheet({
  required BuildContext context,
  required BuyerTransactionSort sort,
  required bool hasDateFilter,
  required ValueChanged<BuyerTransactionSort> onSort,
  required Future<void> Function(DateTime day) onPickSingleDate,
  required Future<void> Function(DateTime start, DateTime end) onPickDateRange,
  required VoidCallback onClearDateFilter,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sort & date', style: AppTypography.subheading),
              const SizedBox(height: 16),
              const TransactionHistorySectionTitle(title: 'ORDER'),
              for (final option in BuyerTransactionSort.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option.menuLabel),
                  trailing: sort == option
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () {
                    onSort(option);
                    Navigator.pop(sheetContext);
                  },
                ),
              const SizedBox(height: 8),
              const TransactionHistorySectionTitle(title: 'SHOW TRANSACTIONS'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined, size: 22),
                title: const Text('On a specific date'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    await onPickSingleDate(picked);
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range_outlined, size: 22),
                title: const Text('Date range'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final now = DateTime.now();
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: now,
                    initialDateRange: DateTimeRange(
                      start: now.subtract(const Duration(days: 30)),
                      end: now,
                    ),
                  );
                  if (range != null) {
                    await onPickDateRange(range.start, range.end);
                  }
                },
              ),
              if (hasDateFilter)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.clear_all_rounded, size: 22),
                  title: const Text('Clear date filter'),
                  onTap: () {
                    onClearDateFilter();
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class TransactionHistoryActiveDateChip extends StatelessWidget {
  const TransactionHistoryActiveDateChip({
    super.key,
    required this.label,
    required this.onClear,
  });

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingMd,
        0,
        AppConstants.spacingMd,
        8,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          label: Text(label),
          deleteIcon: const Icon(Icons.close, size: 18),
          onDeleted: onClear,
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.35)),
          labelStyle: AppTypography.caption.copyWith(
            color: AppColors.primaryDark,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Refund or payout proof image (private bucket, signed URL).
class TransactionFinancialProofSection extends StatefulWidget {
  const TransactionFinancialProofSection({
    super.key,
    required this.title,
    required this.emptyMessage,
    required this.loadSignedUrl,
    this.showWhenUnavailable = true,
  });

  final String title;
  final String emptyMessage;
  final Future<String?> Function() loadSignedUrl;

  /// When false, hide the section entirely if no proof exists (skip empty state).
  final bool showWhenUnavailable;

  @override
  State<TransactionFinancialProofSection> createState() =>
      _TransactionFinancialProofSectionState();
}

class _TransactionFinancialProofSectionState
    extends State<TransactionFinancialProofSection> {
  String? _url;
  bool _loading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final url = await widget.loadSignedUrl();
      if (!mounted) return;
      setState(() {
        _url = url;
        _loading = false;
        _loadFailed = url == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
        _url = null;
      });
    }
  }

  void _openFullscreen(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _url == null && !widget.showWhenUnavailable) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TransactionHistorySectionTitle(title: widget.title),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_url == null)
          _ProofPlaceholder(
            message: _loadFailed
                ? 'Could not load proof image. Pull to refresh and try again.'
                : widget.emptyMessage,
            icon: Icons.receipt_long_outlined,
          )
        else
          Material(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openFullscreen(_url!),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: _url!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          ColoredBox(color: AppColors.surfaceVariant),
                      errorWidget: (_, _, _) => _ProofPlaceholder(
                        message: 'Could not load proof image.',
                        icon: Icons.broken_image_outlined,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fullscreen_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Tap to enlarge',
                              style: AppTypography.caption.copyWith(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProofPlaceholder extends StatelessWidget {
  const _ProofPlaceholder({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class TransactionHistoryEmptyFilterState extends StatelessWidget {
  const TransactionHistoryEmptyFilterState({
    super.key,
    required this.message,
    required this.showClear,
    required this.onClear,
  });

  final String message;
  final bool showClear;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          if (showClear) ...[
            const SizedBox(height: 16),
            ThriftButton(
              label: 'Show all transactions',
              variant: ThriftButtonVariant.outline,
              onPressed: onClear,
            ),
          ],
        ],
      ),
    );
  }
}
