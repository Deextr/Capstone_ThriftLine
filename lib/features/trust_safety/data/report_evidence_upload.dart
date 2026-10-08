import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../controllers/report_user_controller.dart';
import 'report_reasons.dart';

const _uuid = Uuid();

Future<String?> uploadReportEvidence({
  required SupabaseService supabase,
  required String uid,
  required String reportId,
  required List<ReportEvidenceDraft> evidence,
}) async {
  for (final file in evidence) {
    final ext = reportImageExtension(file.name);
    final path = '$uid/$reportId/${_uuid.v4()}.$ext';
    try {
      await supabase.client.storage
          .from('report-evidence')
          .uploadBinary(
            path,
            file.bytes,
            fileOptions: FileOptions(
              contentType: file.contentType,
              upsert: false,
            ),
          );
    } catch (e) {
      debugPrint('report evidence upload error: $e');
      return 'We couldn\'t upload your evidence. Please try again.';
    }

    try {
      final rpcRes = await supabase.client.rpc(
        'attach_report_evidence',
        params: {'p_report_id': reportId, 'p_file_path': path},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        await _bestEffortRemove(supabase, path);
        return supabaseRpcError(
          rpcRes,
          fallback: 'A photo could not be attached to your report.',
        );
      }
    } catch (e) {
      debugPrint('attach_report_evidence error: $e');
      await _bestEffortRemove(supabase, path);
      return 'A photo could not be attached to your report.';
    }
  }
  return null;
}

Future<String?> resubmitReportEvidence({
  required SupabaseService supabase,
  required String reportId,
}) async {
  try {
    final rpcRes = await supabase.client.rpc(
      'resubmit_report_evidence',
      params: {'p_report_id': reportId},
    );
    if (!supabaseRpcSuccess(rpcRes)) {
      return supabaseRpcError(
        rpcRes,
        fallback: 'Could not submit additional evidence.',
      );
    }
    return null;
  } catch (e) {
    debugPrint('resubmit_report_evidence error: $e');
    return 'Could not submit additional evidence.';
  }
}

Future<void> abandonOpenReport(
  SupabaseService supabase,
  String reportId,
) async {
  try {
    await supabase.client.rpc(
      'abandon_open_report',
      params: {'p_report_id': reportId},
    );
  } catch (e) {
    debugPrint('abandon_open_report error: $e');
  }
}

Future<String?> confirmCommunityReportSubmission(
  SupabaseService supabase,
  String reportId,
) async {
  try {
    final rpcRes = await supabase.client.rpc(
      'confirm_community_report_submission',
      params: {'p_report_id': reportId},
    );
    if (!supabaseRpcSuccess(rpcRes)) {
      return supabaseRpcError(
        rpcRes,
        fallback: 'We couldn\'t submit your report. Please try again.',
      );
    }
    return null;
  } catch (e) {
    debugPrint('confirm_community_report_submission error: $e');
    return 'We couldn\'t submit your report. Please try again.';
  }
}

Future<void> _bestEffortRemove(SupabaseService supabase, String path) async {
  try {
    await supabase.client.storage.from('report-evidence').remove([path]);
  } catch (e) {
    debugPrint('report evidence cleanup error: $e');
  }
}
