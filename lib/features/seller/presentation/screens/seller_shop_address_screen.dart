import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/skeleton_widgets.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_shop_address_controller.dart';
import '../../data/seller_shop_address.dart';
import '../../domain/davao_barangay.dart';
import '../../presentation/widgets/davao_barangay_field.dart';

class SellerShopAddressScreen extends StatelessWidget {
  const SellerShopAddressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SellerShopAddressController>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(ctrl.isEditing ? 'Edit shop address' : 'Shop address'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        automaticallyImplyLeading: !ctrl.isEditing,
        leading: ctrl.isEditing
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: ctrl.cancelEditing,
              )
            : null,
      ),
      body: ctrl.isLoading
          ? const _LoadingBody()
          : ctrl.errorMessage != null && ctrl.address == null
          ? _ErrorBody(message: ctrl.errorMessage!, onRetry: ctrl.load)
          : ctrl.isEditing
          ? _EditBody(controller: ctrl)
          : _ViewBody(address: ctrl.address!, onEdit: ctrl.startEditing),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      children: const [
        SkeletonBox(width: double.infinity, height: 160),
        SizedBox(height: 16),
        SkeletonBox(width: double.infinity, height: 48),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ViewBody extends StatelessWidget {
  const _ViewBody({required this.address, required this.onEdit});

  final SellerShopAddress address;
  final Future<void> Function() onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.spacingMd,
        AppConstants.spacingMd,
        AppConstants.spacingMd,
        32,
      ),
      children: [
        Text(
          'This is your shop address from Become a Seller. It is used for '
          'seller operations and is separate from buyer delivery addresses.',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: 'Shop name', value: address.shopName),
              const SizedBox(height: 14),
              _DetailRow(label: 'Barangay', value: address.barangayName),
              const SizedBox(height: 14),
              _DetailRow(label: 'Address line 1', value: address.addressLine1),
              if (address.addressLine2.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                _DetailRow(
                  label: 'Address line 2',
                  value: address.addressLine2,
                ),
              ],
              const SizedBox(height: 14),
              _DetailRow(label: 'City', value: address.city),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ThriftButton(label: 'Edit address', onPressed: () => onEdit()),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.isNotEmpty ? value : '—',
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _EditBody extends StatefulWidget {
  const _EditBody({required this.controller});

  final SellerShopAddressController controller;

  @override
  State<_EditBody> createState() => _EditBodyState();
}

class _EditBodyState extends State<_EditBody> {
  late final TextEditingController _shopNameCtrl;
  late final TextEditingController _line1Ctrl;
  late final TextEditingController _line2Ctrl;
  DavaoBarangay? _barangay;

  @override
  void initState() {
    super.initState();
    final a = widget.controller.address!;
    _shopNameCtrl = TextEditingController(text: a.shopName);
    _line1Ctrl = TextEditingController(text: a.addressLine1);
    _line2Ctrl = TextEditingController(text: a.addressLine2);
    _syncBarangaySelection();
  }

  void _syncBarangaySelection() {
    final a = widget.controller.address!;
    _barangay = DavaoBarangay.findAllowedByName(
      a.barangayName,
      widget.controller.barangays,
    );
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _line1Ctrl.dispose();
    _line2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = await widget.controller.save(
      shopName: _shopNameCtrl.text,
      barangay: _barangay,
      addressLine1: _line1Ctrl.text,
      addressLine2: _line2Ctrl.text,
    );
    if (ok && mounted) {
      showThriftSnackBar(context, 'Shop address updated.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;

    if (ctrl.barangays.isNotEmpty && _barangay == null) {
      _syncBarangaySelection();
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        AppConstants.spacingMd,
        AppConstants.spacingMd,
        AppConstants.spacingMd,
        32 +
            MediaQuery.paddingOf(context).bottom +
            MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        Text(
          'Update your shop address. This does not change buyer checkout '
          'delivery addresses.',
          style: AppTypography.caption.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        if (ctrl.validationMessage != null) ...[
          const SizedBox(height: 12),
          Text(
            ctrl.validationMessage!,
            style: AppTypography.caption.copyWith(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.55)),
          ),
          child: Column(
            children: [
              ThriftTextField(
                label: 'Shop name',
                hint: 'e.g. Vintage Vibes PH',
                controller: _shopNameCtrl,
                icon: Icons.store_outlined,
              ),
              const SizedBox(height: 20),
              DavaoBarangayField(
                barangays: ctrl.barangays,
                selected: _barangay,
                loading: ctrl.barangaysLoading,
                error: ctrl.barangayLoadError,
                onRetry: ctrl.retryBarangays,
                onSelected: (b) {
                  if (!b.isDavaoCity) return;
                  setState(() => _barangay = b);
                },
              ),
              const SizedBox(height: 20),
              ThriftTextField(
                label: 'Address line 1',
                hint: 'Street, building, or house number',
                controller: _line1Ctrl,
                icon: Icons.location_on_outlined,
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              ThriftTextField(
                label: 'Address line 2',
                hint: 'Unit / Floor / Building / Landmark',
                controller: _line2Ctrl,
                icon: Icons.apartment_outlined,
                labelSuffix: Text(
                  'Optional',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ThriftButton(
          label: ctrl.isSaving ? 'Saving…' : 'Save changes',
          onPressed: ctrl.isSaving ? null : _save,
        ),
      ],
    );
  }
}
