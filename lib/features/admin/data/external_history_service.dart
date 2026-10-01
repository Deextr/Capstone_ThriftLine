import '../../../core/services/supabase_service.dart';
import '../../seller/domain/external_selling.dart';

class ExternalHistoryEvidence {
  const ExternalHistoryEvidence({
    required this.kindLabel,
    required this.storagePath,
    this.signedUrl,
  });

  final String kindLabel;
  final String storagePath;
  final String? signedUrl;

  ExternalHistoryEvidence copyWith({String? signedUrl}) {
    return ExternalHistoryEvidence(
      kindLabel: kindLabel,
      storagePath: storagePath,
      signedUrl: signedUrl ?? this.signedUrl,
    );
  }
}

class ExternalHistoryItem {
  const ExternalHistoryItem({
    required this.id,
    required this.platformLabel,
    required this.itemName,
    required this.transactionDate,
    required this.status,
    required this.evidence,
    this.amount,
    this.listingUrl,
    this.adminNote,
  });

  final String id;
  final String platformLabel;
  final String itemName;
  final DateTime transactionDate;
  final ExternalReviewStatus status;
  final List<ExternalHistoryEvidence> evidence;
  final double? amount;
  final String? listingUrl;
  final String? adminNote;

  factory ExternalHistoryItem.fromJson(Map<String, dynamic> json) {
    final rawEvidence = json['external_transaction_evidence'];
    final evidence = <ExternalHistoryEvidence>[];
    if (rawEvidence is List) {
      for (final row in rawEvidence) {
        if (row is! Map) continue;
        final kind = ExternalEvidenceKind.tryParse(
          row['evidence_type'] as String?,
        );
        final path = row['storage_path'] as String? ?? '';
        if (path.isEmpty) continue;
        evidence.add(
          ExternalHistoryEvidence(
            kindLabel: kind?.label ?? 'Evidence',
            storagePath: path,
          ),
        );
      }
    }
    return ExternalHistoryItem(
      id: json['transaction_id'] as String,
      platformLabel:
          ExternalPlatform.tryParse(json['platform'] as String?)?.label ??
          'Other',
      itemName: json['item_name'] as String? ?? 'Item',
      amount: (json['amount'] as num?)?.toDouble(),
      transactionDate:
          DateTime.tryParse(json['transaction_date'] as String? ?? '') ??
          DateTime.now(),
      listingUrl: json['listing_url'] as String?,
      status: ExternalReviewStatus.tryParse(json['review_status'] as String?),
      adminNote: json['admin_review_note'] as String?,
      evidence: evidence,
    );
  }
}

class ExternalHistoryService {
  ExternalHistoryService(this._supabase);

  final SupabaseService _supabase;

  Future<List<ExternalHistoryItem>> load(String verificationId) async {
    final rows = await _supabase.client
        .from('external_transactions')
        .select(
          'transaction_id, platform, item_name, amount, transaction_date, listing_url, review_status, admin_review_note, external_transaction_evidence(evidence_type, storage_path)',
        )
        .eq('verification_id', verificationId)
        .order('created_at');
    final items = <ExternalHistoryItem>[];
    for (final row in rows as List) {
      if (row is! Map) continue;
      final item = ExternalHistoryItem.fromJson(Map<String, dynamic>.from(row));
      final signed = <ExternalHistoryEvidence>[];
      for (final evidence in item.evidence) {
        String? url;
        try {
          url = await _supabase.client.storage
              .from('verification-docs')
              .createSignedUrl(evidence.storagePath, 60 * 10);
        } catch (_) {}
        signed.add(evidence.copyWith(signedUrl: url));
      }
      items.add(
        ExternalHistoryItem(
          id: item.id,
          platformLabel: item.platformLabel,
          itemName: item.itemName,
          transactionDate: item.transactionDate,
          status: item.status,
          evidence: signed,
          amount: item.amount,
          listingUrl: item.listingUrl,
          adminNote: item.adminNote,
        ),
      );
    }
    return items;
  }

  Future<void> review({
    required String transactionId,
    required ExternalReviewStatus decision,
    String? note,
  }) async {
    await _supabase.client.rpc(
      'review_external_transaction',
      params: {
        'p_transaction_id': transactionId,
        'p_decision': decision.storageValue,
        'p_note': note,
      },
    );
  }
}
