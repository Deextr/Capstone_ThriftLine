import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/ph_phone.dart';
import '../../../core/utils/validators.dart';
import '../../../models/enums.dart';
import 'seller_saved_rider.dart';

class SellerSavedRidersService {
  SellerSavedRidersService(this._supabase);

  final SupabaseService _supabase;

  Future<List<SellerSavedRider>> listMine() async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return [];

    final rows = await _supabase.client
        .from('seller_saved_riders')
        .select()
        .eq('seller_id', userId)
        .order('rider_name');

    return rows
        .map((row) => SellerSavedRider.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<SellerSavedRider?> fetchById(String savedRiderId) async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return null;

    final row = await _supabase.client
        .from('seller_saved_riders')
        .select()
        .eq('saved_rider_id', savedRiderId)
        .eq('seller_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return SellerSavedRider.fromRow(Map<String, dynamic>.from(row));
  }

  /// Returns validation message, or null when valid.
  String? validateDraft({
    required String riderName,
    required String riderPhone,
    required DeliveryVehicleType vehicle,
    required String plateNumber,
  }) {
    final nameError = Validators.riderName(riderName);
    if (nameError != null) return nameError;
    final phoneError = phMobileValidationError(riderPhone);
    if (phoneError != null) return phoneError;
    if (plateNumber.trim().isEmpty) return 'Enter the plate number.';
    return null;
  }

  Future<({SellerSavedRider? rider, String? error})> create({
    required String riderName,
    required String riderPhone,
    required DeliveryVehicleType vehicle,
    required String plateNumber,
    String? defaultDeliveryNotes,
  }) async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) {
      return (rider: null, error: 'Please sign in.');
    }

    final validation = validateDraft(
      riderName: riderName,
      riderPhone: riderPhone,
      vehicle: vehicle,
      plateNumber: plateNumber,
    );
    if (validation != null) {
      return (rider: null, error: validation);
    }

    final normalizedPhone = normalizePhMobile(riderPhone.trim())!;
    final draft = SellerSavedRider(
      id: '',
      sellerId: userId,
      riderName: Validators.normalizeFullName(riderName),
      riderPhone: normalizedPhone,
      vehicleType: vehicle.dbValue,
      plateNumber: plateNumber.trim(),
      defaultDeliveryNotes: defaultDeliveryNotes?.trim().isEmpty == true
          ? null
          : defaultDeliveryNotes?.trim(),
    );

    try {
      final row = await _supabase.client
          .from('seller_saved_riders')
          .insert(draft.toInsertPayload(sellerId: userId))
          .select()
          .single();
      return (
        rider: SellerSavedRider.fromRow(Map<String, dynamic>.from(row)),
        error: null,
      );
    } catch (e) {
      debugPrint('SellerSavedRidersService.create: $e');
      return (rider: null, error: 'Could not save rider. Please try again.');
    }
  }

  Future<({SellerSavedRider? rider, String? error})> update({
    required String savedRiderId,
    required String riderName,
    required String riderPhone,
    required DeliveryVehicleType vehicle,
    required String plateNumber,
    String? defaultDeliveryNotes,
  }) async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) {
      return (rider: null, error: 'Please sign in.');
    }

    final validation = validateDraft(
      riderName: riderName,
      riderPhone: riderPhone,
      vehicle: vehicle,
      plateNumber: plateNumber,
    );
    if (validation != null) {
      return (rider: null, error: validation);
    }

    final normalizedPhone = normalizePhMobile(riderPhone.trim())!;
    final draft = SellerSavedRider(
      id: savedRiderId,
      sellerId: userId,
      riderName: Validators.normalizeFullName(riderName),
      riderPhone: normalizedPhone,
      vehicleType: vehicle.dbValue,
      plateNumber: plateNumber.trim(),
      defaultDeliveryNotes: defaultDeliveryNotes?.trim().isEmpty == true
          ? null
          : defaultDeliveryNotes?.trim(),
    );

    try {
      final row = await _supabase.client
          .from('seller_saved_riders')
          .update(draft.toUpdatePayload())
          .eq('saved_rider_id', savedRiderId)
          .eq('seller_id', userId)
          .select()
          .maybeSingle();
      if (row == null) {
        return (rider: null, error: 'Rider not found.');
      }
      return (
        rider: SellerSavedRider.fromRow(Map<String, dynamic>.from(row)),
        error: null,
      );
    } catch (e) {
      debugPrint('SellerSavedRidersService.update: $e');
      return (rider: null, error: 'Could not update rider. Please try again.');
    }
  }

  Future<String?> delete(String savedRiderId) async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return 'Please sign in.';

    try {
      await _supabase.client
          .from('seller_saved_riders')
          .delete()
          .eq('saved_rider_id', savedRiderId)
          .eq('seller_id', userId);
      return null;
    } catch (e) {
      debugPrint('SellerSavedRidersService.delete: $e');
      return 'Could not remove rider. Please try again.';
    }
  }
}
