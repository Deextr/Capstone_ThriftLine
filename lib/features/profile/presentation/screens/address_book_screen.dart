import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../models/address_model.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../seller/data/davao_barangay_service.dart';
import '../../../seller/domain/davao_barangay.dart';
import '../../../seller/presentation/widgets/davao_barangay_field.dart';
import '../../data/address_service.dart';
import '../../data/buyer_address_validation.dart';

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  late final AddressService _service;
  List<AddressModel> _addresses = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = AddressService(context.read<SupabaseService>());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await _service.listMine();
      if (!mounted) return;
      setState(() {
        _addresses = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([AddressModel? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddressForm(service: _service, existing: existing),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(AddressModel address) async {
    await _service.delete(address.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Addresses'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _addresses.isEmpty
            ? const Center(
                child: Text('Add a delivery address to use at checkout.'),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _addresses.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final address = _addresses[i];
                  return ThriftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                address.recipientName,
                                style: AppTypography.subheading,
                              ),
                            ),
                            if (address.isDefault)
                              Text(
                                'Default',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(address.phoneNumber, style: AppTypography.caption),
                        Text(address.formatted, style: AppTypography.body),
                        if (address.landmark != null &&
                            address.landmark!.trim().isNotEmpty)
                          Text(
                            'Landmark: ${address.landmark}',
                            style: AppTypography.caption,
                          ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => _edit(address),
                              child: const Text('Edit'),
                            ),
                            TextButton(
                              onPressed: () => _delete(address),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _AddressForm extends StatefulWidget {
  const _AddressForm({required this.service, this.existing});
  final AddressService service;
  final AddressModel? existing;

  @override
  State<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends State<_AddressForm> {
  final _barangayService = DavaoBarangayService();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _street;
  late final TextEditingController _city;
  late final TextEditingController _postal;
  late final TextEditingController _landmark;
  late bool _isDefault;
  List<DavaoBarangay> _barangays = const [];
  DavaoBarangay? _selectedBarangay;
  bool _barangaysLoading = true;
  String? _barangayError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.recipientName ?? '');
    _phone = TextEditingController(text: existing?.phoneNumber ?? '');
    _street = TextEditingController(text: existing?.streetAddress ?? '');
    _city = TextEditingController(text: DavaoBarangay.cityName);
    _postal = TextEditingController(text: existing?.postalCode ?? '');
    _landmark = TextEditingController(text: existing?.landmark ?? '');
    _isDefault = existing?.isDefault ?? true;
    _loadBarangays();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _street.dispose();
    _city.dispose();
    _postal.dispose();
    _landmark.dispose();
    super.dispose();
  }

  Future<void> _loadBarangays({bool forceRefresh = false}) async {
    setState(() {
      _barangaysLoading = true;
      _barangayError = null;
    });
    try {
      final list = await _barangayService.load(forceRefresh: forceRefresh);
      if (!mounted) return;
      final existingName = widget.existing?.barangay ?? '';
      setState(() {
        _barangays = list;
        _barangaysLoading = false;
        if (_selectedBarangay != null &&
            !DavaoBarangay.isAllowedSelection(_selectedBarangay, list)) {
          _selectedBarangay = null;
        }
        _selectedBarangay ??= DavaoBarangay.findAllowedByName(
          existingName,
          list,
        );
      });
    } on DavaoBarangayException catch (e) {
      if (!mounted) return;
      setState(() {
        _barangays = const [];
        _barangaysLoading = false;
        _barangayError = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _barangays = const [];
        _barangaysLoading = false;
        _barangayError =
            'Could not load Davao City barangays. Check your connection and try again.';
      });
    }
  }

  Future<void> _save() async {
    final error = buyerAddressFormError(
      recipientName: _name.text,
      phoneNumber: _phone.text,
      streetAddress: _street.text,
      barangay: _selectedBarangay,
      allowedBarangays: _barangays,
    );
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.service.save(
        id: widget.existing?.id,
        recipientName: _name.text,
        phoneNumber: _phone.text,
        streetAddress: _street.text,
        barangay: _selectedBarangay!.name,
        city: DavaoBarangay.cityName,
        postalCode: _postal.text,
        landmark: _landmark.text,
        isDefault: _isDefault,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showThriftSnackBar(
          context,
          'Could not save that address.',
          isError: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null ? 'Add address' : 'Edit address',
              style: AppTypography.subheading,
            ),
            const SizedBox(height: 16),
            ThriftTextField(label: 'Recipient', controller: _name),
            const SizedBox(height: 12),
            ThriftTextField(
              label: 'Phone',
              hint: '09XXXXXXXXX',
              controller: _phone,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            ThriftTextField(label: 'Street', controller: _street, maxLines: 2),
            const SizedBox(height: 12),
            DavaoBarangayField(
              barangays: _barangays,
              selected: _selectedBarangay,
              loading: _barangaysLoading,
              error: _barangayError,
              onRetry: () => _loadBarangays(forceRefresh: true),
              onSelected: (barangay) {
                if (!barangay.isDavaoCity) return;
                setState(() => _selectedBarangay = barangay);
              },
            ),
            const SizedBox(height: 12),
            ThriftTextField(
              label: 'City',
              controller: _city,
              readOnly: true,
              icon: Icons.lock_outline,
              labelSuffix: Text(
                'Davao City only',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            ThriftTextField(label: 'Postal code', controller: _postal),
            const SizedBox(height: 12),
            ThriftTextField(label: 'Landmark', controller: _landmark),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Default address'),
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
            ),
            ThriftButton(
              label: 'Save',
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
