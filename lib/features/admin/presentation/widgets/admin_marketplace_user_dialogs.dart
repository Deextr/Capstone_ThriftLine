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
      'invited' => (AppColors.warningForeground, AppColors.warningSoft),
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
              ] else if (user.effectiveAccountStatus == 'banned') ...[
                const SizedBox(height: 8),
                const _Notice(
                  message:
                      'Account banned. Reactivation is not available through User Management.',
                ),
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

Future<void> showEnableMarketplaceAccountDialog({
  required BuildContext context,
  required MarketplaceUserRow user,
  required Future<String?> Function(String notes) onConfirm,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return _EnableDialog(user: user, onConfirm: onConfirm);
    },
  );
}

class _EnableDialog extends StatefulWidget {
  const _EnableDialog({required this.user, required this.onConfirm});

  final MarketplaceUserRow user;
  final Future<String?> Function(String notes) onConfirm;

  @override
  State<_EnableDialog> createState() => _EnableDialogState();
}

class _EnableDialogState extends State<_EnableDialog> {
  final _notesController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onConfirm(_notesController.text);
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
      title: const Text('Re-enable account'),
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
                    'This restores marketplace access for a temporarily disabled account. Role, seller verification, and other profile details stay unchanged. Banned accounts cannot be re-enabled here.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Internal notes (optional)',
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
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm re-enable'),
        ),
      ],
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
    final dialogWidth = width < 560 ? width - 40 : 520.0;
    const disableAccent = Color(0xFF9F1239);

    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.85)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: disableAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.pause_circle_outline_rounded,
                      color: disableAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Temporarily disable account',
                          style: AppTypography.subheading.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Restrict marketplace access until you re-enable the account.',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    visualDensity: VisualDensity.compact,
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DialogUserSummaryCard(user: user),
              const SizedBox(height: 20),
              const _FormSectionLabel(title: 'What changes'),
              const SizedBox(height: 8),
              const _DisableImpactPanel(),
              const SizedBox(height: 20),
              const _FormSectionLabel(title: 'Reason'),
              const SizedBox(height: 4),
              Text(
                'Select the closest match. This is stored in the audit log.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              _DisableReasonPicker(
                selectedValue: _reason,
                enabled: !_saving,
                onSelected: (value) => setState(() {
                  _reason = value;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              const _FormSectionLabel(title: 'Notes'),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                style: AppTypography.body,
                decoration: InputDecoration(
                  hintText: 'Optional context for other admins…',
                  hintStyle: AppTypography.body.copyWith(
                    color: AppColors.textHint,
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceVariant.withValues(alpha: 0.45),
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: disableAccent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _InlineError(message: _error!),
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
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: disableAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.lock_outline_rounded, size: 18),
          label: Text(_saving ? 'Disabling…' : 'Disable account'),
        ),
      ],
    );
  }
}

class _DialogUserSummaryCard extends StatelessWidget {
  const _DialogUserSummaryCard({required this.user});

  final MarketplaceUserRow user;

  @override
  Widget build(BuildContext context) {
    final initial = user.displayName.trim().isNotEmpty
        ? user.displayName.trim()[0].toUpperCase()
        : '?';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              initial,
              style: AppTypography.tableBodyMedium.copyWith(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName, style: AppTypography.tableBodyMedium),
                if (user.email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MarketplaceStatusBadge(status: user.effectiveAccountStatus),
                    _MetaChip(label: user.accountTypeLabel),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisableImpactPanel extends StatelessWidget {
  const _DisableImpactPanel();

  static const _items = [
    'Signs the user out of active sessions',
    'Blocks new listings, bids, purchases, messages, and Looking For posts',
    'Keeps existing orders, reports, and history intact',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.warningSoft.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.warningForeground.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.warningForeground.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Temporary disable — not a permanent ban',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF92400E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF92400E),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      line,
                      style: AppTypography.caption.copyWith(
                        color: const Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DisableReasonPicker extends StatelessWidget {
  const _DisableReasonPicker({
    required this.selectedValue,
    required this.enabled,
    required this.onSelected,
  });

  final String? selectedValue;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < marketplaceDisableReasonOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _DisableReasonTile(
            option: marketplaceDisableReasonOptions[i],
            selected: selectedValue == marketplaceDisableReasonOptions[i].value,
            enabled: enabled,
            onTap: () => onSelected(marketplaceDisableReasonOptions[i].value),
          ),
        ],
      ],
    );
  }
}

class _DisableReasonTile extends StatelessWidget {
  const _DisableReasonTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final MarketplaceDisableReasonOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const selectedBorder = Color(0xFF9F1239);
    return Material(
      color: selected
          ? selectedBorder.withValues(alpha: 0.06)
          : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected
              ? selectedBorder.withValues(alpha: 0.55)
              : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected ? selectedBorder : AppColors.textHint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textHint,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.description,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormSectionLabel extends StatelessWidget {
  const _FormSectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: AppTypography.badge.copyWith(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        fontSize: 11,
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.errorForeground.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.errorForeground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                color: AppColors.errorForeground,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
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
