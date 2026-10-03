import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../core/utils/validators.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/keyboard_safe.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_orders_controller.dart';

class ArrangeDeliveryScreen extends StatefulWidget {
  const ArrangeDeliveryScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<ArrangeDeliveryScreen> createState() => _ArrangeDeliveryScreenState();
}

class _ArrangeDeliveryScreenState extends State<ArrangeDeliveryScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _notes = TextEditingController();
  DeliveryVehicleType _vehicle = DeliveryVehicleType.motorcycle;
  DateTime? _estimated;
  String? _nameError;
  String? _phoneError;
  String? _plateError;

  @override
  void initState() {
    super.initState();
    final shipment = context.read<SellerOrdersController>().order?.shipment;
    if (shipment != null) {
      _name.text = shipment.riderName ?? '';
      _phone.text = shipment.riderPhone ?? '';
      _plate.text = shipment.plateNumber ?? '';
      _notes.text = shipment.deliveryNotes ?? '';
      if (shipment.vehicleType != null) {
        _vehicle = DeliveryVehicleType.fromDb(shipment.vehicleType);
      }
      _estimated = shipment.estimatedDeliveryAt;
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

  Future<void> _pickEstimated() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _estimated ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_estimated ?? now),
    );
    if (time == null || !mounted) return;
    setState(() {
      _estimated = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    final shipment = context.read<SellerOrdersController>().order?.shipment;
    if (shipment != null && !shipment.canEditRider) {
      showThriftSnackBar(
        context,
        'Rider details are locked while delivery is in progress.',
        isError: true,
      );
      return;
    }
    final nameError = Validators.riderName(_name.text);
    final phoneError = phMobileValidationError(_phone.text);
    final plateTrimmed = _plate.text.trim();
    final plateError = plateTrimmed.isEmpty ? 'Enter the plate number.' : null;
    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
      _plateError = plateError;
    });
    if (nameError != null || phoneError != null || plateError != null) return;

    final error = await context.read<SellerOrdersController>().assignRider(
      riderName: Validators.normalizeFullName(_name.text),
      riderPhone: _phone.text.trim(),
      vehicleType: _vehicle.dbValue,
      plateNumber: plateTrimmed,
      estimatedDeliveryAt: _estimated,
      deliveryNotes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Freelance rider saved.');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SellerOrdersController>();
    final order = controller.order;
    final shipment = order?.shipment;
    final readOnly = shipment != null && !shipment.canEditRider;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arrange Delivery'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: KeyboardSafeForm(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        action: readOnly
            ? ThriftButton(
                label: 'Back to order',
                variant: ThriftButtonVariant.outline,
                onPressed: () => context.pop(),
              )
            : ThriftButton(
                label: controller.isUpdatingDelivery ? 'Saving…' : 'Save rider',
                onPressed: controller.isUpdatingDelivery ? null : _submit,
              ),
        children: [
          if (readOnly) ...[
            Text(
              'Rider details are locked while delivery is in progress.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: 12),
          ],
          Text('Freelance / Local Rider', style: AppTypography.subheading),
          Text(
            'Seller Arranged · ${order == null ? '' : '#${order.orderNumber}'}',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 16),
          ThriftTextField(
            label: 'Rider name',
            hint: 'Juan Dela Cruz',
            controller: _name,
            error: _nameError,
            readOnly: readOnly,
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
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
          Text('Vehicle type', style: AppTypography.label),
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
                  onSelected: readOnly
                      ? null
                      : (_) => setState(() => _vehicle = vehicle),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Plate number',
            hint: 'ABC 1234',
            controller: _plate,
            error: _plateError,
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Estimated delivery (optional)',
            hint: _estimated == null
                ? 'Choose date and time'
                : _estimated.toString(),
            readOnly: true,
            onTap: readOnly ? null : _pickEstimated,
          ),
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Delivery notes (optional)',
            hint: 'Meet at the gate, call on arrival…',
            controller: _notes,
            maxLines: 3,
            readOnly: readOnly,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
