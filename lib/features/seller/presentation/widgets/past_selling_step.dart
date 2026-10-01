import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/keyboard_safe.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../domain/external_selling.dart';

class PastSellingExperienceStep extends StatelessWidget {
  const PastSellingExperienceStep({
    super.key,
    required this.adding,
    required this.claimedRange,
    required this.transactions,
    required this.onClaimedRange,
    required this.onSave,
    required this.onRemove,
  });

  final bool adding;
  final ClaimedSellingRange? claimedRange;
  final List<ExternalTransactionDraft> transactions;
  final ValueChanged<ClaimedSellingRange> onClaimedRange;
  final ValueChanged<ExternalTransactionDraft> onSave;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "If you've sold items on other platforms before, you can submit some previous transactions for verification. This is optional. If you're new to selling, you can skip this step and build your transaction history on ThriftLine.",
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        Text(
          'You can cover phone numbers, addresses, and payment references, as long as the item, conversation, and payment or delivery can still be reviewed. These photos stay private. Other buyers cannot see them.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        if (adding) ...[
          const SizedBox(height: 20),
          Text(
            'Approximate previous selling experience',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'This is what you remember. It does not set your trust score. Only transactions an admin verifies are counted, and at most 10.',
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final range in ClaimedSellingRange.values)
                ChoiceChip(
                  label: Text(range.label),
                  selected: claimedRange == range,
                  onSelected: (_) => onClaimedRange(range),
                  selectedColor: AppColors.primaryLight,
                  labelStyle: AppTypography.caption.copyWith(
                    color: claimedRange == range
                        ? AppColors.primaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            transactions.isEmpty
                ? 'No previous transactions added yet.'
                : "You've added ${transactions.length} of $kMaxExternalTransactions.",
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < transactions.length; i++) ...[
            _TransactionCard(
              index: i,
              draft: transactions[i],
              onEdit: () => _edit(context, transactions[i]),
              onRemove: () => onRemove(transactions[i].localId),
            ),
            const SizedBox(height: 10),
          ],
          if (transactions.length < kMaxExternalTransactions)
            OutlinedButton.icon(
              onPressed: () => _edit(context, null),
              icon: const Icon(Icons.add),
              label: Text(
                transactions.isEmpty
                    ? 'Add a transaction'
                    : 'Add another transaction',
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    ExternalTransactionDraft? existing,
  ) async {
    final saved = await showModalBottomSheet<ExternalTransactionDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: true,
      backgroundColor: AppColors.surface,
      builder: (context) => _TransactionEditor(existing: existing),
    );
    if (saved != null) onSave(saved);
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.index,
    required this.draft,
    required this.onEdit,
    required this.onRemove,
  });

  final int index;
  final ExternalTransactionDraft draft;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.platform.label,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit transaction ${index + 1}',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Remove transaction ${index + 1}',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          Text(
            draft.itemName.trim(),
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            formatFullDate(draft.approximateDate),
            style: AppTypography.caption,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final evidence in draft.evidence)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check, size: 16, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(evidence.kind.label, style: AppTypography.caption),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Reviewed after you submit. This is outside ThriftLine.',
            style: AppTypography.caption.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}

class _TransactionEditor extends StatefulWidget {
  const _TransactionEditor({this.existing});

  final ExternalTransactionDraft? existing;

  @override
  State<_TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<_TransactionEditor> {
  final _itemCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _picker = ImagePicker();

  ExternalPlatform _platform = ExternalPlatform.facebookMarketplace;
  DateTime _date = DateTime.now();
  ExternalEvidenceKind? _firstKind;
  ExternalEvidenceKind? _secondKind;
  Uint8List? _firstBytes;
  Uint8List? _secondBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) {
      _dateCtrl.text = formatFullDate(_date);
      return;
    }
    _platform = existing.platform;
    _date = existing.approximateDate;
    _itemCtrl.text = existing.itemName;
    if (existing.amount != null) {
      _amountCtrl.text = existing.amount!.toStringAsFixed(
        existing.amount! == existing.amount!.roundToDouble() ? 0 : 2,
      );
    }
    _urlCtrl.text = existing.listingUrl ?? '';
    _dateCtrl.text = formatFullDate(_date);
    if (existing.evidence.isNotEmpty) {
      _firstKind = existing.evidence.first.kind;
      _firstBytes = existing.evidence.first.bytes;
    }
    if (existing.evidence.length > 1) {
      _secondKind = existing.evidence[1].kind;
      _secondBytes = existing.evidence[1].bytes;
    }
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _amountCtrl.dispose();
    _urlCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(2010),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _dateCtrl.text = formatFullDate(picked);
    });
  }

  Future<void> _pickPhoto(int slot) async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 60,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      if (slot == 0) {
        _firstBytes = bytes;
      } else {
        _secondBytes = bytes;
      }
    });
  }

  void _save() {
    final amountText = _amountCtrl.text.trim();
    double? amount;
    if (amountText.isNotEmpty) {
      amount = double.tryParse(amountText.replaceAll(',', ''));
      if (amount == null) {
        setState(
          () => _error = 'Enter the amount as a number, or leave it blank.',
        );
        return;
      }
    }
    final firstKind = _firstKind;
    final secondKind = _secondKind;
    final firstBytes = _firstBytes;
    final secondBytes = _secondBytes;
    if (firstKind == null ||
        secondKind == null ||
        firstBytes == null ||
        secondBytes == null) {
      setState(
        () => _error =
            'Add two photos of different kinds, such as the conversation and a payment or delivery confirmation.',
      );
      return;
    }
    final draft = ExternalTransactionDraft(
      localId:
          widget.existing?.localId ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      platform: _platform,
      approximateDate: _date,
      itemName: _itemCtrl.text,
      amount: amount,
      listingUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
      evidence: [
        ExternalEvidenceDraft(kind: firstKind, bytes: firstBytes),
        ExternalEvidenceDraft(kind: secondKind, bytes: secondBytes),
      ],
    );
    final error = validateExternalTransaction(draft);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardSafeSheet(
      action: ThriftButton(label: 'Save transaction', onPressed: _save),
      children: [
        Text(
          widget.existing == null ? 'Add a transaction' : 'Edit transaction',
          style: AppTypography.subheading.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Upload evidence that helps confirm the transaction, such as your conversation together with payment or delivery confirmation.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Text('Platform', style: AppTypography.caption),
        const SizedBox(height: 6),
        DropdownButtonFormField<ExternalPlatform>(
          // ignore: deprecated_member_use
          value: _platform,
          items: [
            for (final platform in ExternalPlatform.values)
              DropdownMenuItem(value: platform, child: Text(platform.label)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _platform = value);
          },
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'Item sold',
          controller: _itemCtrl,
          hint: 'Vintage shirt',
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'Approximate date',
          readOnly: true,
          onTap: _pickDate,
          controller: _dateCtrl,
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'Amount (optional)',
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          hint: '850',
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'Listing link (optional)',
          controller: _urlCtrl,
          hint: 'https://',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 16),
        _EvidenceSlot(
          title: 'First photo',
          kind: _firstKind,
          hasPhoto: _firstBytes != null,
          excluded: _secondKind,
          onKind: (kind) => setState(() {
            _firstKind = kind;
            if (_secondKind == kind) _secondKind = null;
          }),
          onPick: () => _pickPhoto(0),
        ),
        const SizedBox(height: 12),
        _EvidenceSlot(
          title: 'Second photo',
          kind: _secondKind,
          hasPhoto: _secondBytes != null,
          excluded: _firstKind,
          onKind: (kind) => setState(() {
            _secondKind = kind;
            if (_firstKind == kind) _firstKind = null;
          }),
          onPick: () => _pickPhoto(1),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

class _EvidenceSlot extends StatelessWidget {
  const _EvidenceSlot({
    required this.title,
    required this.kind,
    required this.hasPhoto,
    required this.excluded,
    required this.onKind,
    required this.onPick,
  });

  final String title;
  final ExternalEvidenceKind? kind;
  final bool hasPhoto;
  final ExternalEvidenceKind? excluded;
  final ValueChanged<ExternalEvidenceKind> onKind;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<ExternalEvidenceKind>(
          // ignore: deprecated_member_use
          value: kind,
          hint: const Text('What does this photo show?'),
          items: [
            for (final item in ExternalEvidenceKind.values)
              if (item != excluded)
                DropdownMenuItem(value: item, child: Text(item.label)),
          ],
          onChanged: (value) {
            if (value != null) onKind(value);
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onPick,
          icon: Icon(hasPhoto ? Icons.check : Icons.photo_outlined),
          label: Text(hasPhoto ? 'Photo added' : 'Choose photo'),
        ),
      ],
    );
  }
}
