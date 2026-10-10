import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/admin_users_service.dart';
import '../../domain/marketplace_user_management.dart';

class MarketplaceStatusBadge extends StatelessWidget {
  const MarketplaceStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final key = status.trim().toLowerCase();
    final (Color foreground, Color background) = switch (key) {
      'active' => (AppColors.primaryDark, AppColors.primaryLight),
      'suspended' => (AppColors.warningForeground, AppColors.warningSoft),
      'banned' => (AppColors.errorForeground, AppColors.errorSoft),
      _ => (AppColors.textSecondary, AppColors.surfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: foreground.withValues(alpha: 0.18)),
      ),
      child: Text(
        marketplaceAccountStatusLabel(status),
        style: AppTypography.badge.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

Future<void> showMarketplaceUserDetailDialog({
  required BuildContext context,
  required MarketplaceUserRow user,
  required Future<MarketplaceUserRow?> Function() loadDetail,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _UserDetailDialog(user: user, loadDetail: loadDetail);
    },
  );
}

class _UserDetailDialog extends StatefulWidget {
  const _UserDetailDialog({required this.user, required this.loadDetail});

  final MarketplaceUserRow user;
  final Future<MarketplaceUserRow?> Function() loadDetail;

  @override
  State<_UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends State<_UserDetailDialog> {
  late MarketplaceUserRow _user = widget.user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final detail = await widget.loadDetail();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (detail != null) _user = detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final blocked = user.disableBlockedMessage;
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Row(
        children: [
          Expanded(
            child: Text('User details', style: AppTypography.subheading),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
      content: SizedBox(
        width: width < 560 ? width : 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName, style: AppTypography.tableBodyMedium),
              if (user.username.isNotEmpty) ...[
                SizedBox(height: 2),
                Text(
                  '@${user.username}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MarketplaceStatusBadge(status: user.effectiveAccountStatus),
                  _MetaChip(label: user.accountTypeLabel),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(
                label: 'Email',
                value: user.email.isEmpty ? '—' : user.email,
              ),
              _DetailRow(
                label: 'Date joined',
                value: formatAdminTableDate(user.createdAt),
              ),
              _DetailRow(
                label: 'Seller verification',
                value: marketplaceVerificationLabel(user.verificationStatus),
              ),
              if (user.shopName != null)
                _DetailRow(label: 'Shop', value: user.shopName!),
              if (blocked != null) ...[
                const SizedBox(height: 8),
                _Notice(message: blocked),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              else
                _RestrictionBlock(user: user),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _RestrictionBlock extends StatelessWidget {
  const _RestrictionBlock({required this.user});

  final MarketplaceUserRow user;

  @override
  Widget build(BuildContext context) {
    final reason = user.adminDisableReason ?? user.sanctionReason;
    final notes = user.adminDisableNotes;
    final when = user.adminDisabledAt ?? user.permanentlyDisabledAt;
    if (user.effectiveAccountStatus == 'active' &&
        reason == null &&
        notes == null) {
      return const SizedBox.shrink();
    }
    if (reason == null &&
        notes == null &&
        when == null &&
        user.restrictedUntil == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Administrative restriction',
            style: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (reason != null) _DetailRow(label: 'Reason', value: reason),
          if (notes != null) _DetailRow(label: 'Notes', value: notes),
          if (when != null)
            _DetailRow(
              label: 'Recorded',
              value: formatAdminTableDateTime(when),
            ),
          if (user.restrictedUntil != null)
            _DetailRow(
              label: 'Looking For pause until',
              value: formatAdminTableDateTime(user.restrictedUntil!),
            ),
        ],
      ),
    );
  }
}

Future<void> showDisableMarketplaceAccountDialog({
  required BuildContext context,
  required MarketplaceUserRow user,
  required Future<String?> Function(String reason, String notes) onConfirm,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _DisableDialog(user: user, onConfirm: onConfirm);
    },
  );
}

class _DisableDialog extends StatefulWidget {
  const _DisableDialog({required this.user, required this.onConfirm});

  final MarketplaceUserRow user;
  final Future<String?> Function(String reason, String notes) onConfirm;

  @override
  State<_DisableDialog> createState() => _DisableDialogState();
}

class _DisableDialogState extends State<_DisableDialog> {
  final _notesController = TextEditingController();
  String? _reason;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || !marketplaceDisableReasonAllowed(reason)) {
      setState(() => _error = 'Choose a reason for disabling this account.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onConfirm(reason, _notesController.text);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final width = MediaQuery.sizeOf(context).width;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text('Disable account'),
      content: SizedBox(
        width: width < 560 ? width : 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.displayName, style: AppTypography.tableBodyMedium),
              if (user.email.isNotEmpty) ...[
                SizedBox(height: 2),
                Text(
                  user.email,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Current status',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  MarketplaceStatusBadge(status: user.effectiveAccountStatus),
                ],
              ),
              const SizedBox(height: 12),
              const _Notice(
                message:
                    'This signs the person out and blocks new listings, bids, purchases, messages, and Looking For posts. Existing orders, reports, and records stay in place. This is a disable, not a permanent ban.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final reason in marketplaceDisableReasons)
                    DropdownMenuItem(value: reason, child: Text(reason)),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _reason = value;
                        _error = null;
                      }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Additional notes (optional)',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: AppTypography.caption.copyWith(color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF9F1239),
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Confirm disable'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value, style: AppTypography.body)),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: AppTypography.badge.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.warningForeground.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        message,
        style: AppTypography.caption.copyWith(
          color: const Color(0xFF92400E),
          height: 1.4,
        ),
      ),
    );
  }
}
