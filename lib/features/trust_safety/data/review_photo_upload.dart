import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../controllers/report_user_controller.dart';
import 'report_reasons.dart';

const _uuid = Uuid();
const _reviewPhotosBucket = 'review-photos';

Future<String?> uploadReviewPhotos({
  required SupabaseService supabase,
  required String uid,
  required String reviewId,
  required List<ReportEvidenceDraft> photos,
}) async {
  for (final file in photos) {
    final ext = reportImageExtension(file.name);
    final path = '$uid/$reviewId/${_uuid.v4()}.$ext';
    try {
      await supabase.client.storage
          .from(_reviewPhotosBucket)
          .uploadBinary(
            path,
            file.bytes,
            fileOptions: FileOptions(
              contentType: file.contentType,
              upsert: false,
            ),
          );
    } catch (e) {
      debugPrint('review photo upload error: $e');
      return 'A photo could not be uploaded. Please try again.';
    }

    try {
      final rpcRes = await supabase.client.rpc(
        'attach_review_photo',
        params: {'p_review_id': reviewId, 'p_file_path': path},
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        await _bestEffortRemove(supabase, path);
        return supabaseRpcError(
          rpcRes,
          fallback: 'A photo could not be attached to your review.',
        );
      }
    } catch (e) {
      debugPrint('attach_review_photo error: $e');
      await _bestEffortRemove(supabase, path);
      return 'A photo could not be attached to your review.';
    }
  }
  return null;
}

Future<void> rollbackReviewWithoutPhotos(
  SupabaseService supabase,
  String reviewId,
) async {
  try {
    await supabase.client.rpc(
      'rollback_review_without_photos',
      params: {'p_review_id': reviewId},
    );
  } catch (e) {
    debugPrint('rollback_review_without_photos error: $e');
  }
}

Future<void> removeReviewPhoto(
  SupabaseService supabase,
  String reviewPhotoId,
) async {
  try {
    await supabase.client.rpc(
      'remove_review_photo',
      params: {'p_review_photo_id': reviewPhotoId},
    );
  } catch (e) {
    debugPrint('remove_review_photo error: $e');
  }
}

String reviewPhotoPublicUrl(SupabaseService supabase, String filePath) {
  return supabase.client.storage
      .from(_reviewPhotosBucket)
      .getPublicUrl(filePath);
}

Future<void> _bestEffortRemove(SupabaseService supabase, String path) async {
  try {
    await supabase.client.storage.from(_reviewPhotosBucket).remove([path]);
  } catch (e) {
    debugPrint('review photo cleanup error: $e');
  }
}
