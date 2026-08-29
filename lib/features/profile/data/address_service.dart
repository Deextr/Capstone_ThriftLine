import '../../../core/services/supabase_service.dart';
import '../../../models/address_model.dart';

class AddressService {
  AddressService(this._supabase);
  final SupabaseService _supabase;

  Future<List<AddressModel>> listMine() async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) return const [];
    final rows = await _supabase.client
        .from('addresses')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((row) => AddressModel.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<AddressModel?> defaultAddress() async {
    final all = await listMine();
    if (all.isEmpty) return null;
    return all.firstWhere((a) => a.isDefault, orElse: () => all.first);
  }

  Future<void> save({
    String? id,
    required String recipientName,
    required String phoneNumber,
    required String streetAddress,
    required String barangay,
    required String city,
    String? postalCode,
    String? landmark,
    required bool isDefault,
  }) async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) throw StateError('Sign in first.');
    final payload = {
      'user_id': userId,
      'recipient_name': recipientName.trim(),
      'phone_number': phoneNumber.trim(),
      'street_address': streetAddress.trim(),
      'barangay': barangay.trim(),
      'city': city.trim().isEmpty ? 'Davao City' : city.trim(),
      'postal_code': postalCode?.trim().isEmpty == true ? null : postalCode?.trim(),
      'landmark': landmark?.trim().isEmpty == true ? null : landmark?.trim(),
      'is_default': isDefault,
    };
    if (id == null) {
      await _supabase.client.from('addresses').insert(payload);
    } else {
      await _supabase.client.from('addresses').update(payload).eq('address_id', id);
    }
  }

  Future<void> delete(String id) async {
    await _supabase.client.from('addresses').delete().eq('address_id', id);
  }
}
