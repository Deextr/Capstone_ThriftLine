import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../core/utils/validators.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/keyboard_safe.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/seller_orders_controller.dart';
import '../../data/seller_saved_rider.dart';
import '../../data/seller_saved_riders_service.dart';
import '../widgets/saved_rider_form_fields.dart';
import '../widgets/saved_rider_select_sheet.dart';

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

  List<SellerSavedRider> _savedRiders = const [];
  bool _loadingRiders = true;
  String? _selectedSavedRiderId;
  SellerSavedRider? get _selectedSavedRider {
    if (_selectedSavedRiderId == null) return null;
    for (final r in _savedRiders) {
      if (r.id == _selectedSavedRiderId) return r;
    }
    return null;
  }

  late final SellerSavedRidersService _savedRidersService;

  @override
  void initState() {
    super.initState();
    _savedRidersService = SellerSavedRidersService(
      context.read<SupabaseService>(),
    );
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
    _loadSavedRiders();
  }

  Future<void> _loadSavedRiders() async {
    try {
      final list = await _savedRidersService.listMine();
      if (!mounted) return;
      setState(() {
        _savedRiders = list;
        _loadingRiders = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRiders = false);
    }
  }

  void _applySavedRider(SellerSavedRider rider) {
    setState(() {
      _selectedSavedRiderId = rider.id;
      _name.text = rider.riderName;
      _phone.text = rider.riderPhone;
      _plate.text = rider.plateNumber;
      _vehicle = rider.vehicle;
      _nameError = null;
      _phoneError = null;
      _plateError = null;
      final defaultNotes = rider.defaultDeliveryNotes?.trim();
      if (defaultNotes != null && defaultNotes.isNotEmpty) {
        _notes.text = defaultNotes;
      }
    });
  }

  Future<void> _openRiderPicker() async {
    await _loadSavedRiders();
    if (!mounted) return;
    await showSavedRiderSelectSheet(
      context: context,
      riders: _savedRiders,
      selectedId: _selectedSavedRiderId,
      onSelected: (rider) {
        _applySavedRider(rider);
        if (!_savedRiders.any((r) => r.id == rider.id)) {
          setState(() => _savedRiders = [..._savedRiders, rider]);
        }
      },
    );
  }

  Future<void> _addRiderInline() async {
    final created = await context.push<SellerSavedRider>(
      RouteNames.sellerSavedRiderEditor,
    );
    if (created == null || !mounted) return;
    setState(() {
      _savedRiders = [..._savedRiders, created];
    });
    _applySavedRider(created);
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

  Widget _buildSelectedRiderSection({required bool readOnly}) {
    final selected = _selectedSavedRider;
    if (selected != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Selected rider', style: AppTypography.label),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(selected.riderName, style: AppTypography.subheading),
                const SizedBox(height: 4),
                Text(selected.maskedPhone, style: AppTypography.caption),
                if (!readOnly) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _openRiderPicker,
                      child: const Text('Change rider'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    if (readOnly) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Select rider', style: AppTypography.label),
        const SizedBox(height: 8),
        if (_loadingRiders)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else ...[
          OutlinedButton(
            onPressed: _savedRiders.isEmpty ? null : _openRiderPicker,
            child: Text(
              _savedRiders.isEmpty
                  ? 'No saved riders yet'
                  : 'Select saved rider',
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _addRiderInline,
            icon: const Icon(Icons.add),
            label: const Text('Add new rider'),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Or enter rider details below for this order only.',
          style: AppTypography.caption,
        ),
        const SizedBox(height: 16),
      ],
    );
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
        actions: [
          if (!readOnly)
            TextButton(
              onPressed: () => context.push(RouteNames.sellerMyRiders),
              child: const Text('My Riders'),
            ),
        ],
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
                label: controller.isUpdatingDelivery
                    ? 'Saving…'
                    : 'Confirm delivery',
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
          Text('Delivery information', style: AppTypography.subheading),
          Text(
            'Seller Arranged · ${order == null ? '' : '#${order.orderNumber}'}',
            style: AppTypography.caption,
          ),
          const SizedBox(height: 16),
          _buildSelectedRiderSection(readOnly: readOnly),
          Text('Rider details', style: AppTypography.label),
          const SizedBox(height: 8),
          SavedRiderFormFields(
            nameController: _name,
            phoneController: _phone,
            plateController: _plate,
            notesController: _notes,
            vehicle: _vehicle,
            onVehicleChanged: (v) => setState(() => _vehicle = v),
            nameError: _nameError,
            phoneError: _phoneError,
            plateError: _plateError,
            readOnly: readOnly,
            showDefaultNotes: false,
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
          ThriftTextField(
            label: 'Estimated delivery (optional)',
            hint: _estimated == null
                ? 'Choose date and time'
                : _estimated.toString(),
            readOnly: true,
            onTap: readOnly ? null : _pickEstimated,
          ),
        ],
      ),
    );
  }
}
