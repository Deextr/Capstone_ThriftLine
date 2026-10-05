import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../widgets/keyboard_safe.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/seller_saved_riders_service.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../core/utils/validators.dart';
import '../../../../models/enums.dart';
import '../widgets/saved_rider_form_fields.dart';

class SellerSavedRiderEditorScreen extends StatefulWidget {
  const SellerSavedRiderEditorScreen({super.key, this.savedRiderId});

  final String? savedRiderId;

  @override
  State<SellerSavedRiderEditorScreen> createState() =>
      _SellerSavedRiderEditorScreenState();
}

class _SellerSavedRiderEditorScreenState
    extends State<SellerSavedRiderEditorScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _plate = TextEditingController();
  final _notes = TextEditingController();
  DeliveryVehicleType _vehicle = DeliveryVehicleType.motorcycle;
  bool _loadingExisting = false;
  bool _saving = false;
  String? _nameError;
  String? _phoneError;
  String? _plateError;

  late final SellerSavedRidersService _service;

  bool get _isEdit => widget.savedRiderId != null;

  @override
  void initState() {
    super.initState();
    _service = SellerSavedRidersService(context.read<SupabaseService>());
    if (_isEdit) {
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    final rider = await _service.fetchById(widget.savedRiderId!);
    if (!mounted) return;
    if (rider == null) {
      showThriftSnackBar(context, 'Rider not found.', isError: true);
      context.pop();
      return;
    }
    _name.text = rider.riderName;
    _phone.text = rider.riderPhone;
    _plate.text = rider.plateNumber;
    _notes.text = rider.defaultDeliveryNotes ?? '';
    _vehicle = rider.vehicle;
    setState(() => _loadingExisting = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _plate.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final plateTrimmed = _plate.text.trim();
    final nameError = Validators.riderName(_name.text);
    final phoneError = phMobileValidationError(_phone.text);
    final plateError = plateTrimmed.isEmpty ? 'Enter the plate number.' : null;
    setState(() {
      _nameError = nameError;
      _phoneError = phoneError;
      _plateError = plateError;
    });
    if (nameError != null || phoneError != null || plateError != null) return;

    setState(() => _saving = true);
    final notes = _notes.text.trim();
    final result = _isEdit
        ? await _service.update(
            savedRiderId: widget.savedRiderId!,
            riderName: _name.text,
            riderPhone: _phone.text,
            vehicle: _vehicle,
            plateNumber: plateTrimmed,
            defaultDeliveryNotes: notes.isEmpty ? null : notes,
          )
        : await _service.create(
            riderName: _name.text,
            riderPhone: _phone.text,
            vehicle: _vehicle,
            plateNumber: plateTrimmed,
            defaultDeliveryNotes: notes.isEmpty ? null : notes,
          );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result.error != null) {
      showThriftSnackBar(context, result.error!, isError: true);
      return;
    }
    context.pop(result.rider);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit rider' : 'Add rider'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loadingExisting
          ? const Center(child: CircularProgressIndicator())
          : KeyboardSafeForm(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              action: ThriftButton(
                label: _saving ? 'Saving…' : 'Save rider',
                onPressed: _saving ? null : _save,
              ),
              children: [
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
                ),
              ],
            ),
    );
  }
}
