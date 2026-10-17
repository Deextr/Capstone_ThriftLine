import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:uuid/uuid.dart';

import '../../../core/services/supabase_service.dart';

/// Private bucket for payout and manual refund receipts. Admin-only.
const kFinancialEvidenceBucket = 'financial-evidence';

/// Max receipt size; matches the `financial-evidence` bucket limit.
const kMaxEvidenceBytes = 5 * 1024 * 1024;

const _uuid = Uuid();

class PickedEvidence {
  const PickedEvidence({
    required this.bytes,
    required this.fileName,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
}

String evidenceExtension(String fileName, String contentType) {
  final lower = fileName.toLowerCase();
  if (contentType == 'application/pdf' || lower.endsWith('.pdf')) return 'pdf';
  if (contentType == 'image/png' || lower.endsWith('.png')) return 'png';
  if (contentType == 'image/webp' || lower.endsWith('.webp')) return 'webp';
  return 'jpg';
}

String evidenceContentType(String fileName, String? mimeType) {
  final mime = (mimeType ?? '').toLowerCase();
  if (mime.isNotEmpty && mime != 'application/octet-stream') return mime;
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// Picks a receipt image. Returns null when the admin closes the picker.
/// Throws [EvidenceTooLargeException] for files over [kMaxEvidenceBytes].
Future<PickedEvidence?> pickEvidenceImage(ImagePicker picker) async {
  final file = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 2400,
    imageQuality: 88,
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  if (bytes.length > kMaxEvidenceBytes) throw const EvidenceTooLargeException();
  return PickedEvidence(
    bytes: bytes,
    fileName: file.name,
    mimeType: file.mimeType,
  );
}

class EvidenceTooLargeException implements Exception {
  const EvidenceTooLargeException();
}

class FinancialEvidenceStorage {
  FinancialEvidenceStorage(this._supabase);

  final SupabaseService _supabase;

  /// Uploads a receipt under `<folder>/<ownerId>/...` and returns the object path.
  Future<String> upload({
    required String folder,
    required String ownerId,
    required PickedEvidence file,
  }) async {
    final contentType = evidenceContentType(file.fileName, file.mimeType);
    final path =
        '$folder/$ownerId/${_uuid.v4()}.${evidenceExtension(file.fileName, contentType)}';
    await _supabase.client.storage
        .from(kFinancialEvidenceBucket)
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  Future<void> remove(String path) async {
    final referenced = await _supabase.client.rpc(
      'financial_evidence_path_is_referenced',
      params: {'p_path': path},
    );
    if (referenced == true) {
      throw StateError('Evidence is linked to a payout or refund record.');
    }
    await _supabase.client.storage.from(kFinancialEvidenceBucket).remove([
      path,
    ]);
  }

  Future<String> signedUrl(String path) {
    return _supabase.client.storage
        .from(kFinancialEvidenceBucket)
        .createSignedUrl(path, 60 * 10);
  }
}
