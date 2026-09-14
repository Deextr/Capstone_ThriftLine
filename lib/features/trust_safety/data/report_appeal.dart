import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';

const int kAppealDetailsMinLength = 10;
const int kAppealDetailsMaxLength = 2000;

String? appealDetailsError(String value) {
  final trimmed = value.trim();
  if (trimmed.length < kAppealDetailsMinLength) {
    return 'Please add a bit more detail.';
  }
  if (trimmed.length > kAppealDetailsMaxLength) {
    return 'Keep your appeal under 2,000 characters.';
  }
  return null;
}

class ReportAppealContext {
  const ReportAppealContext({
    required this.canAppeal,
    required this.alreadySubmitted,
    required this.underReview,
    this.appealId,
    this.details,
    this.createdAt,
  });

  final bool canAppeal;
  final bool alreadySubmitted;
  final bool underReview;
  final String? appealId;
  final String? details;
  final DateTime? createdAt;

  factory ReportAppealContext.fromMap(Map<String, dynamic> map) {
    DateTime? parseTime(dynamic value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return ReportAppealContext(
      canAppeal: map['can_appeal'] == true,
      alreadySubmitted: map['already_submitted'] == true,
      underReview: map['under_review'] == true,
      appealId: map['appeal_id']?.toString(),
      details: map['details']?.toString(),
      createdAt: parseTime(map['created_at']),
    );
  }
}

class ReportAppealService {
  ReportAppealService(this._supabase);

  final SupabaseService _supabase;

  Future<ReportAppealContext> load(String reportId) async {
    final rpcRes = await _supabase.client.rpc(
      'get_report_appeal_context',
      params: {'p_report_id': reportId},
    );
    if (!supabaseRpcSuccess(rpcRes)) {
      throw StateError(
        supabaseRpcError(rpcRes, fallback: 'Unable to load this review.') ??
            'Unable to load this review.',
      );
    }
    return ReportAppealContext.fromMap(supabaseRpcMap(rpcRes) ?? const {});
  }

  Future<String?> submit({
    required String reportId,
    required String details,
  }) async {
    final rpcRes = await _supabase.client.rpc(
      'submit_report_appeal',
      params: {'p_report_id': reportId, 'p_details': details.trim()},
    );
    if (!supabaseRpcSuccess(rpcRes)) {
      return supabaseRpcError(rpcRes, fallback: 'Could not send your appeal.');
    }
    return null;
  }
}
