import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
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

  List<SellerSavedRider> _savedRiders = const [];
  bool _loadingRiders = true;
  String? _loadRidersError;
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
    _loadSavedRiders();
  }

  Future<void> _loadSavedRiders() async {
    setState(() {
      _loadingRiders = true;
      _loadRidersError = null;
    });
    try {
      final list = await _savedRidersService.listMine();
      if (!mounted) return;
      setState(() {
        _savedRiders = list;
        _loadingRiders = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingRiders = false;
        _loadRidersError = 'Could not load your saved riders. You can still enter details below.';
      });
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
      final defaultNotes = rider.defaultDeliveryNotes?.trim();
      if (defaultNotes != null &&
          defaultNotes.isNotEmpty &&
          _notes.text.trim().isEmpty) {
        _notes.text = defaultNotes;
      }
    });
  }

  Future<void> _openRiderPicker() async {
    await _loadSavedRiders();
    if (!mounted) return;
    if (_loadRidersError != null) {
      showThriftSnackBar(context, _loadRidersError!, isError: true);
      return;
    }
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
      _loadRidersError = null;
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

  Widget _buildSelectedRiderSection() {
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
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _openRiderPicker,
                    child: const Text('Change rider'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

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
          if (_loadRidersError != null) ...[
            Text(
              _loadRidersError!,
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadSavedRiders, child: const Text('Retry')),
            const SizedBox(height: 8),
          ],
          OutlinedButton(
            onPressed: _savedRiders.isEmpty || _loadRidersError != null
                ? null
                : _openRiderPicker,
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
          'Or enter rider details below for this return only.',
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
        actions: [
          TextButton(
            onPressed: () => context.push(RouteNames.sellerMyRiders),
            child: const Text('My Riders'),
          ),
        ],
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
          _buildSelectedRiderSection(),
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
            showDefaultNotes: false,
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
