import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../core/utils/validators.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/keyboard_safe.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_orders_controller.dart';

class ArrangeReturnScreen extends StatefulWidget {
  const ArrangeReturnScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<ArrangeReturnScreen> createState() => _ArrangeReturnScreenState();
}

class _ArrangeReturnScreenState extends State<ArrangeReturnScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _notes = TextEditingController();
  DeliveryVehicleType _vehicle = DeliveryVehicleType.motorcycle;
  DateTime? _pickup;
  String? _nameError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    final itemReturn = context.read<SellerOrdersController>().order?.itemReturn;
    if (itemReturn != null) {
      _name.text = itemReturn.riderName ?? '';
      _phone.text = itemReturn.riderPhone ?? '';
      _plate.text = itemReturn.plateNumber ?? '';
      _notes.text = itemReturn.notes ?? '';
      if (itemReturn.vehicleType != null) {
        _vehicle = DeliveryVehicleType.fromDb(itemReturn.vehicleType);
      }
      _pickup = itemReturn.pickupScheduledAt;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _plate.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickPickup() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _pickup ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_pickup ?? now),
    );
    if (time == null || !mounted) return;
    setState(() {
      _pickup = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    final nameError = Validators.riderName(_name.text);
    final phoneError = phMobileValidationError(_phone.text);
    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
    });
    if (nameError != null || phoneError != null) return;

    final error = await context
        .read<SellerOrdersController>()
        .arrangeReturnRider(
          riderName: Validators.normalizeFullName(_name.text),
          riderPhone: _phone.text.trim(),
          vehicleType: _vehicle.dbValue,
          plateNumber: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
          pickupScheduledAt: _pickup,
          returnNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(
      context,
      'Return rider saved. The buyer can see these details.',
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerOrdersController>();
    final order = controller.order;
    final pickupLabel = _pickup == null
        ? 'Choose date and time'
        : '${formatCompactDate(_pickup!)} ${_pickup!.hour.toString().padLeft(2, '0')}:${_pickup!.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Arrange return'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: KeyboardSafeForm(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        action: ThriftButton(
          label: controller.isUpdatingDelivery
              ? 'Saving...'
              : 'Save return rider',
          isLoading: controller.isUpdatingDelivery,
          onPressed: controller.isUpdatingDelivery ? null : _submit,
        ),
        children: [
          Text(
            order == null ? 'Return pickup' : 'Order #${order.orderNumber}',
            style: AppTypography.subheading,
          ),
          const SizedBox(height: 8),
          Text(
            'You arrange and pay for this pickup. The buyer refund is already recorded and does not depend on this step.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ThriftTextField(
            label: 'Rider name',
            hint: 'Juan Dela Cruz',
            controller: _name,
            error: _nameError,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                Validators.fullNameInputCharacters,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Phone number',
            hint: '09171234567',
            controller: _phone,
            keyboardType: TextInputType.phone,
            error: _phoneError,
          ),
          const SizedBox(height: 16),
          Text('Vehicle', style: AppTypography.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final vehicle in DeliveryVehicleType.values)
                ChoiceChip(
                  label: Text(vehicle.label),
                  selected: _vehicle == vehicle,
                  selectedColor: AppColors.primaryLight,
                  onSelected: (_) => setState(() => _vehicle = vehicle),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Plate number (optional)',
            hint: 'ABC 1234',
            controller: _plate,
          ),
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Pickup time (optional)',
            hint: pickupLabel,
            readOnly: true,
            onTap: _pickPickup,
          ),
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Note for the buyer (optional)',
            hint: 'Call when the rider is outside.',
            controller: _notes,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
