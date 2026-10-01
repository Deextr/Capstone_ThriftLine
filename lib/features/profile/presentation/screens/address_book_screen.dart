import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/utils/ph_phone.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../models/address_model.dart';
import '../../../../widgets/keyboard_safe.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../seller/data/davao_barangay_service.dart';
import '../../../seller/domain/davao_barangay.dart';
import '../../../seller/presentation/widgets/davao_barangay_field.dart';
import '../../data/address_service.dart';
import '../../data/buyer_address_validation.dart';

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key, this.currentAddressId});

  final String? currentAddressId;

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  late final AddressService _service;
  List<AddressModel> _addresses = const [];
  bool _loading = true;
  String? _settingDefaultId;

  @override
  void initState() {
    super.initState();
    _service = AddressService(context.read<SupabaseService>());
    unawaited(DavaoBarangayService.prefetch());
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
      enableDrag: true,
      useSafeArea: true,
      builder: (_) => _AddressForm(service: _service, existing: existing),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(AddressModel address) async {
    await _service.delete(address.id);
    await _load();
  }

  Future<void> _useAddress(AddressModel address) async {
    if (widget.currentAddressId != null) {
<<<<<<< HEAD
=======
      if (!address.hasValidPhoneContact) {
        showThriftSnackBar(
          context,
          'Edit this address and enter a valid phone contact (09XXXXXXXXX) '
          'before using it at checkout.',
          isError: true,
        );
        await _edit(address);
        return;
      }
>>>>>>> checkout-address-label-fix
      context.pop(address);
      return;
    }
    if (address.isDefault) return;

    setState(() => _settingDefaultId = address.id);
    try {
      await _service.setDefault(address.id);
      await _load();
    } catch (_) {
      if (mounted) {
        showThriftSnackBar(
          context,
          'Could not set that address as your checkout address.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _settingDefaultId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
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
                  final settingDefault = _settingDefaultId == address.id;
                  final isInUse = widget.currentAddressId != null
                      ? address.id == widget.currentAddressId
                      : address.isDefault;
                  return ThriftCard(
                    onTap: settingDefault ? null : () => _useAddress(address),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isInUse) ...[
                              const Icon(
                                Icons.check_circle,
                                size: 16,
                                color: AppColors.success,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                address.recipientName,
                                style: AppTypography.subheading,
                              ),
                            ),
                            if (isInUse)
                              ThriftBadge(
                                label: widget.currentAddressId != null
                                    ? 'In use for this checkout'
                                    : 'Used by default at checkout',
                                variant: BadgeVariant.success,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(address.phoneNumber, style: AppTypography.caption),
                        if (!address.hasValidPhoneContact)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Phone contact invalid — edit before checkout',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Text(address.formatted, style: AppTypography.body),
                        if (address.landmark != null &&
                            address.landmark!.trim().isNotEmpty)
                          Text(
                            'Landmark: ${address.landmark}',
                            style: AppTypography.caption,
                          ),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: settingDefault
                                  ? null
                                  : () => _useAddress(address),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 16,
                              ),
                              label: settingDefault
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Use this address'),
                            ),
                            const Spacer(),
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
  String? _phoneError;

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
    if (forceRefresh || _barangays.isEmpty) {
      setState(() {
        _barangaysLoading = true;
        _barangayError = null;
      });
    }
    try {
      final list = await _barangayService.load(forceRefresh: forceRefresh);
      if (!mounted) return;
      final existingName = widget.existing?.barangay ?? '';
      final wasLoading = _barangaysLoading || _barangays.isEmpty;
      _barangays = list;
      _barangaysLoading = false;
      _barangayError = null;
      if (_selectedBarangay != null &&
          !DavaoBarangay.isAllowedSelection(_selectedBarangay, list)) {
        _selectedBarangay = null;
      }
      _selectedBarangay ??= DavaoBarangay.findAllowedByName(existingName, list);
      if (wasLoading) setState(() {});
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

  void _validatePhoneInline([String? value]) {
    final text = value ?? _phone.text;
    setState(() {
      if (text.isEmpty) {
        _phoneError = null;
        return;
      }
      _phoneError = phMobile09FormatValidationError(text);
    });
  }

  Future<void> _save() async {
    _validatePhoneInline();
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
    return KeyboardSafeSheet(
      action: ThriftButton(
        label: 'Save',
        isLoading: _saving,
        onPressed: _saving ? null : _save,
      ),
      children: [
        Text(
          widget.existing == null ? 'Add address' : 'Edit address',
          style: AppTypography.subheading,
        ),
        const SizedBox(height: 16),
        ThriftTextField(
          key: const ValueKey('address_recipient'),
          label: 'Recipient',
          controller: _name,
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          key: const ValueKey('address_phone'),
          label: 'Phone contact',
          hint: '09XXXXXXXXX',
          controller: _phone,
          keyboardType: TextInputType.phone,
          error: _phoneError,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          onChanged: _validatePhoneInline,
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          key: const ValueKey('address_street'),
          label: 'Street',
          controller: _street,
          maxLines: 2,
        ),
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
          key: const ValueKey('address_city'),
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
        ThriftTextField(
          key: const ValueKey('address_postal'),
          label: 'Postal code',
          controller: _postal,
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          key: const ValueKey('address_landmark'),
          label: 'Landmark',
          controller: _landmark,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Default address'),
          value: _isDefault,
          onChanged: (v) => setState(() => _isDefault = v),
        ),
      ],
    );
  }
}
