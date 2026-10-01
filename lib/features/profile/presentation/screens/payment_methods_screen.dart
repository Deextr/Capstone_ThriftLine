import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../widgets/keyboard_safe.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../seller/controllers/seller_payout_method_controller.dart';
import '../../../seller/data/seller_payout_method.dart';

class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerPayoutMethodController>();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Payment Methods'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: context.read<SellerPayoutMethodController>().load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Text('Payout method', style: AppTypography.subheading),
              const SizedBox(height: 6),
              Text(
                'Saved GCash details are used when you request a payout from Available Earnings.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              if (controller.offlineMessage != null) ...[
                Text(
                  controller.offlineMessage!,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                ThriftButton(
                  label: 'Retry',
                  expand: false,
                  onPressed: context.read<SellerPayoutMethodController>().load,
                ),
                const SizedBox(height: 16),
              ],
              if (controller.isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (controller.errorMessage != null)
                Column(
                  children: [
                    Text(
                      controller.errorMessage!,
                      style: AppTypography.body,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ThriftButton(
                      label: 'Retry',
                      onPressed: context
                          .read<SellerPayoutMethodController>()
                          .load,
                    ),
                  ],
                )
              else if (controller.hasGcash)
                _SavedGcashCard(controller: controller)
              else
                _EmptyGcashCard(onAdd: () => _edit(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyGcashCard extends StatelessWidget {
  const _EmptyGcashCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GCash', style: AppTypography.subheading),
          const SizedBox(height: 6),
          Text(
            'Add your GCash account name and mobile number so you can request a payout.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 16),
          ThriftButton(label: 'Add GCash', onPressed: onAdd),
        ],
      ),
    );
  }
}

class _SavedGcashCard extends StatelessWidget {
  const _SavedGcashCard({required this.controller});

  final SellerPayoutMethodController controller;

  @override
  Widget build(BuildContext context) {
    final method = controller.method!;
    return ThriftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GCash', style: AppTypography.subheading),
          const SizedBox(height: 12),
          Text('Account name', style: AppTypography.caption),
          Text(method.accountName, style: AppTypography.body),
          const SizedBox(height: 12),
          Text('Mobile number', style: AppTypography.caption),
          Text(formatPhMobile(method.mobileNumber), style: AppTypography.body),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Edit GCash',
            onPressed: controller.isSaving ? null : () => _edit(context),
          ),
          const SizedBox(height: 8),
          ThriftButton(
            label: 'Remove',
            variant: ThriftButtonVariant.outline,
            color: AppColors.error,
            isLoading: controller.isSaving,
            onPressed: controller.isSaving
                ? null
                : () => _remove(context, controller),
          ),
        ],
      ),
    );
  }
}

Future<void> _edit(BuildContext context) async {
  final controller = context.read<SellerPayoutMethodController>();
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    useSafeArea: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: controller,
      child: _GcashForm(existing: controller.method),
    ),
  );
  if (saved == true && context.mounted) {
    showThriftSnackBar(context, 'GCash details saved.');
  }
}

Future<void> _remove(
  BuildContext context,
  SellerPayoutMethodController controller,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove GCash?'),
      content: const Text(
        'You will need to add GCash again before you can request a payout.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Keep'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final error = await controller.remove();
  if (!context.mounted) return;
  if (error != null) {
    showThriftSnackBar(context, error, isError: true);
    return;
  }
  showThriftSnackBar(context, 'GCash details removed.');
}

class _GcashForm extends StatefulWidget {
  const _GcashForm({this.existing});

  final SellerPayoutMethod? existing;

  @override
  State<_GcashForm> createState() => _GcashFormState();
}

class _GcashFormState extends State<_GcashForm> {
  late final TextEditingController _name;
  late final TextEditingController _mobile;
  String? _nameError;
  String? _mobileError;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.accountName ?? '');
    _mobile = TextEditingController(text: widget.existing?.mobileNumber ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = gcashAccountNameError(_name.text);
    final mobileError = gcashMobileError(_mobile.text);
    setState(() {
      _nameError = nameError;
      _mobileError = mobileError;
    });
    if (nameError != null || mobileError != null) return;

    final error = await context.read<SellerPayoutMethodController>().save(
      accountName: _name.text,
      mobileNumber: _mobile.text,
    );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final saving = context.watch<SellerPayoutMethodController>().isSaving;

    return KeyboardSafeSheet(
      action: ThriftButton(
        label: saving ? 'Saving…' : 'Save GCash',
        isLoading: saving,
        onPressed: saving ? null : _save,
      ),
      children: [
        Text('GCash details', style: AppTypography.heading),
        const SizedBox(height: 16),
        ThriftTextField(
          label: 'GCash Account Name',
          hint: 'Name on the GCash account',
          controller: _name,
          error: _nameError,
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'GCash Mobile Number',
          hint: '09XXXXXXXXX',
          controller: _mobile,
          error: _mobileError,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          icon: Icons.phone_outlined,
        ),
      ],
    );
  }
}
