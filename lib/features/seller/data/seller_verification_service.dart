import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/davao_barangay.dart';
import '../domain/external_selling.dart';
import '../domain/seller_address_draft.dart';
import '../domain/seller_id_type.dart';

class SellerVerificationService {
  SellerVerificationService(this._supabase);

  final SupabaseService _supabase;

  Future<void> submitApplication({
    required SellerAddressDraft address,
    required SellerIdType idType,
    required Uint8List idFrontBytes,
    Uint8List? idBackBytes,
    required Uint8List selfieBytes,
    required String selfieFileName,
    required Map<String, bool> liveness,
    List<ExternalTransactionDraft> externalTransactions = const [],
    ClaimedSellingRange? claimedSellingRange,
  }) async {
    final userId = _supabase.currentUser?.id;
    if (userId == null) {
      throw StateError('You must be signed in to apply.');
    }
    final profile = await _supabase.client
        .from('users')
        .select('is_phone_verified, phone_number')
        .eq('user_id', userId)
        .maybeSingle();
    final verified = profile?['is_phone_verified'] == true;
    final phone = profile?['phone_number']?.toString() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (!verified || digits.length != 11 || !digits.startsWith('09')) {
      throw SellerSubmitException(
        'Verify your mobile number before submitting your seller application.',
      );
    }
    if (!address.barangay!.isDavaoCity) {
      throw StateError('Shop address must be in Davao City.');
    }

    final shopFields = <String, dynamic>{
      'shop_name': address.storeName.trim(),
      'shop_address': address.composedShopAddress,
      'barangay': address.barangay!.name,
      'city': DavaoBarangay.cityName,
      'application_type': 'seller',
      'government_id_type': idType.storageValue,
      'liveness_passed': true,
      'liveness_result': liveness,
      'claimed_selling_range': claimedSellingRange?.storageValue,
    };

    try {
      final existing = await _supabase.client
          .from('user_verifications')
          .select('verification_id')
          .eq('user_id', userId)
          .eq('verification_status', 'pending')
          .maybeSingle();

      final String verificationId;
      if (existing != null) {
        verificationId = existing['verification_id'] as String;
        await _supabase.client
            .from('user_verifications')
            .update(shopFields)
            .eq('verification_id', verificationId);
      } else {
        final inserted = await _supabase.client
            .from('user_verifications')
            .insert({
              ...shopFields,
              'user_id': userId,
              'verification_status': 'pending',
              'submitted_at': DateTime.now().toUtc().toIso8601String(),
            })
            .select('verification_id')
            .single();
        verificationId = inserted['verification_id'] as String;
      }

      final frontPath = '$userId/$verificationId/id_front.jpg';
      final backBytes = idBackBytes;
      final backPath = backBytes != null && backBytes.isNotEmpty
          ? '$userId/$verificationId/id_back.jpg'
          : null;
      final selfiePath =
          '$userId/$verificationId/selfie${_ext(selfieFileName)}';

      await _supabase.client.storage
          .from('verification-docs')
          .uploadBinary(
            frontPath,
            idFrontBytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      if (backPath != null && backBytes != null) {
        await _supabase.client.storage
            .from('verification-docs')
            .uploadBinary(
              backPath,
              backBytes,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      }
      await _supabase.client.storage
          .from('verification-docs')
          .uploadBinary(
            selfiePath,
            selfieBytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentType(selfieFileName),
            ),
          );

      await _supabase.client
          .from('user_verifications')
          .update({
            'government_id_front': frontPath,
            'government_id_back': backPath,
            'selfie_image': selfiePath,
          })
          .eq('verification_id', verificationId);

      await _replaceExternalHistory(
        userId: userId,
        verificationId: verificationId,
        transactions: externalTransactions,
      );
    } catch (error) {
      debugPrint(
        'SellerVerificationService.submitApplication: ${_describe(error)}',
      );
      throw SellerSubmitException(sellerSubmitUserMessage(error), error);
    }
  }

  Future<void> _replaceExternalHistory({
    required String userId,
    required String verificationId,
    required List<ExternalTransactionDraft> transactions,
  }) async {
    final existing = await _supabase.client
        .from('external_transactions')
        .select('transaction_id')
        .eq('verification_id', verificationId);
    final ids = <String>[
      for (final row in existing as List)
        if (row is Map && row['transaction_id'] is String)
          row['transaction_id'] as String,
    ];
    if (ids.isNotEmpty) {
      final evidence = await _supabase.client
          .from('external_transaction_evidence')
          .select('storage_path')
          .inFilter('transaction_id', ids);
      final paths = <String>[
        for (final row in evidence as List)
          if (row is Map &&
              (row['storage_path'] as String?)?.isNotEmpty == true)
            row['storage_path'] as String,
      ];
      if (paths.isNotEmpty) {
        await _supabase.client.storage.from('verification-docs').remove(paths);
      }
      await _supabase.client
          .from('external_transactions')
          .delete()
          .eq('verification_id', verificationId);
    }

    for (final draft in transactions) {
      final inserted = await _supabase.client
          .from('external_transactions')
          .insert({
            'verification_id': verificationId,
            'user_id': userId,
            'platform': draft.platform.storageValue,
            'item_name': draft.itemName.trim(),
            'amount': draft.amount,
            'transaction_date':
                '${draft.approximateDate.year.toString().padLeft(4, '0')}-'
                '${draft.approximateDate.month.toString().padLeft(2, '0')}-'
                '${draft.approximateDate.day.toString().padLeft(2, '0')}',
            'listing_url': draft.listingUrl,
            'review_status': 'pending',
          })
          .select('transaction_id')
          .single();
      final transactionId = inserted['transaction_id'] as String;
      for (var i = 0; i < draft.evidence.length; i++) {
        final evidence = draft.evidence[i];
        final path = '$userId/$verificationId/external/$transactionId/$i.jpg';
        await _supabase.client.storage
            .from('verification-docs')
            .uploadBinary(
              path,
              evidence.bytes,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
        await _supabase.client.from('external_transaction_evidence').insert({
          'transaction_id': transactionId,
          'user_id': userId,
          'evidence_type': evidence.kind.storageValue,
          'storage_path': path,
        });
      }
    }
  }

  String _ext(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.webp')) return '.webp';
    return '.jpg';
  }

  String _contentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return 'postgrest ${error.code} ${error.message}';
    }
    if (error is StorageException) {
      return 'storage ${error.statusCode} ${error.message}';
    }
    return error.toString();
  }
}

class SellerSubmitException implements Exception {
  SellerSubmitException(this.userMessage, [this.cause]);

  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

String sellerSubmitUserMessage(Object error) {
  if (error is SellerSubmitException) return error.userMessage;
  if (error is PostgrestException) {
    final code = error.code ?? '';
    final message = error.message.toLowerCase();
    if (code == '23505' || message.contains('one_pending')) {
      return 'You already have an application under review.';
    }
    if (code == '23502' ||
        message.contains('not-null') ||
        message.contains('null value')) {
      return 'The application is missing a required field. Please try again.';
    }
    if (message.contains('mobile number') ||
        message.contains('verify your philippine')) {
      return 'Verify your mobile number before submitting your seller application.';
    }
    if (code == '42501' || message.contains('row-level security')) {
      return 'Could not save the application. Please sign in again and retry.';
    }
  }
  if (error is StorageException) {
    return 'Could not upload your documents. Check your connection and try again.';
  }
  return 'Could not submit the application. Check your connection and try again.';
}
