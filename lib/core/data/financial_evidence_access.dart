import 'package:flutter/foundation.dart';

import '../services/supabase_service.dart';

/// Matches [kFinancialEvidenceBucket] in admin financial evidence upload.
const kFinancialEvidenceBucket = 'financial-evidence';

const int kFinancialEvidenceSignedUrlSeconds = 3600;

Future<String?> signedUrlForFinancialEvidencePath(
  SupabaseService supabase,
  String? storagePath,
) async {
  final path = storagePath?.trim();
  if (path == null || path.isEmpty) return null;
  try {
    return await supabase.client.storage
        .from(kFinancialEvidenceBucket)
        .createSignedUrl(path, kFinancialEvidenceSignedUrlSeconds);
  } catch (e) {
    debugPrint('signedUrlForFinancialEvidencePath error: $e');
    return null;
  }
}

Future<String?> fetchRefundProofStoragePath(
  SupabaseService supabase,
  String escrowId,
) async {
  if (escrowId.trim().isEmpty) return null;
  try {
    final row = await supabase.client
        .from('escrow_refund_details')
        .select('manual_evidence_path')
        .eq('escrow_id', escrowId)
        .maybeSingle();
    final path = row?['manual_evidence_path'] as String?;
    final trimmed = path?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  } catch (e) {
    debugPrint('fetchRefundProofStoragePath error: $e');
    return null;
  }
}

Future<String?> fetchPayoutProofStoragePath(
  SupabaseService supabase,
  String payoutId,
) async {
  if (payoutId.trim().isEmpty) return null;
  try {
    final row = await supabase.client
        .from('seller_payouts')
        .select('evidence_path')
        .eq('payout_id', payoutId)
        .maybeSingle();
    final path = row?['evidence_path'] as String?;
    final trimmed = path?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  } catch (e) {
    debugPrint('fetchPayoutProofStoragePath error: $e');
    return null;
  }
}

Future<String?> loadRefundProofSignedUrl(
  SupabaseService supabase,
  String escrowId,
) async {
  final path = await fetchRefundProofStoragePath(supabase, escrowId);
  return signedUrlForFinancialEvidencePath(supabase, path);
}

Future<String?> loadPayoutProofSignedUrl(
  SupabaseService supabase,
  String payoutId,
) async {
  final path = await fetchPayoutProofStoragePath(supabase, payoutId);
  return signedUrlForFinancialEvidencePath(supabase, path);
}
