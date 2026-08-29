import '../../../core/services/supabase_service.dart';

class SellerApplication {
  const SellerApplication({
    required this.id,
    required this.userId,
    required this.shopName,
    required this.shopAddress,
    required this.barangay,
    required this.city,
    required this.status,
    required this.submittedAt,
    required this.livenessPassed,
    required this.livenessResult,
    this.idPath,
    this.idBackPath,
    this.idType,
    this.selfiePath,
    this.applicantName,
    this.rejectionReason,
  });

  final String id;
  final String userId;
  final String shopName;
  final String shopAddress;
  final String barangay;
  final String city;
  final String status;
  final DateTime submittedAt;
  final bool livenessPassed;
  final Map<String, dynamic> livenessResult;
  final String? idPath;
  final String? idBackPath;
  final String? idType;
  final String? selfiePath;
  final String? applicantName;
  final String? rejectionReason;

  factory SellerApplication.fromJson(Map<String, dynamic> json) {
    final user = json['users'];
    return SellerApplication(
      id: json['verification_id'] as String,
      userId: json['user_id'] as String,
      shopName: json['shop_name'] as String? ?? 'Shop',
      shopAddress: json['shop_address'] as String? ?? '',
      barangay: json['barangay'] as String? ?? '',
      city: json['city'] as String? ?? 'Davao City',
      status: json['verification_status'] as String? ?? 'pending',
      submittedAt: json['submitted_at'] != null
          ? DateTime.parse(json['submitted_at'] as String)
          : DateTime.now(),
      livenessPassed: json['liveness_passed'] as bool? ?? false,
      livenessResult: Map<String, dynamic>.from(
        json['liveness_result'] as Map? ?? const {},
      ),
      idPath: json['government_id_front'] as String?,
      idBackPath: json['government_id_back'] as String?,
      idType: json['government_id_type'] as String?,
      selfiePath: json['selfie_image'] as String?,
      applicantName: user is Map ? user['full_name'] as String? : null,
      rejectionReason: json['rejection_reason'] as String?,
    );
  }

  SellerApplication withApplicantName(String? name) {
    return SellerApplication(
      id: id,
      userId: userId,
      shopName: shopName,
      shopAddress: shopAddress,
      barangay: barangay,
      city: city,
      status: status,
      submittedAt: submittedAt,
      livenessPassed: livenessPassed,
      livenessResult: livenessResult,
      idPath: idPath,
      idBackPath: idBackPath,
      idType: idType,
      selfiePath: selfiePath,
      applicantName: (name != null && name.trim().isNotEmpty)
          ? name
          : applicantName,
      rejectionReason: rejectionReason,
    );
  }
}

class AdminVerificationService {
  AdminVerificationService(this._supabase);

  final SupabaseService _supabase;

  Future<SellerApplication?> getById(String verificationId) async {
    final row = await _supabase.client
        .from('user_verifications')
        .select()
        .eq('verification_id', verificationId)
        .maybeSingle();
    if (row == null) return null;
    var application = SellerApplication.fromJson(row);
    try {
      final profile = await _supabase.client
          .from('user_public_profiles')
          .select('full_name')
          .eq('user_id', application.userId)
          .maybeSingle();
      application = application.withApplicantName(profile?['full_name'] as String?);
    } catch (_) {}
    return application;
  }

  Future<List<SellerApplication>> listPending() async {
    final rows = await _supabase.client
        .from('user_verifications')
        .select()
        .eq('verification_status', 'pending')
        .order('submitted_at', ascending: false);
    final applications = (rows as List)
        .map((row) =>
            SellerApplication.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
    if (applications.isEmpty) return applications;

    final ids = applications.map((app) => app.userId).toSet().toList();
    try {
      final profiles = await _supabase.client
          .from('user_public_profiles')
          .select('user_id, full_name')
          .inFilter('user_id', ids);
      final names = <String, String>{
        for (final row in profiles as List)
          (row as Map)['user_id'] as String:
              (row['full_name'] as String?) ?? '',
      };
      return applications
          .map((app) => app.withApplicantName(names[app.userId]))
          .toList();
    } catch (_) {
      return applications;
    }
  }

  Future<String?> signedUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    final signed = await _supabase.client.storage
        .from('verification-docs')
        .createSignedUrl(path, 60 * 10);
    return signed;
  }

  Future<void> review({
    required String verificationId,
    required String decision,
    String? reason,
  }) async {
    await _supabase.client.rpc(
      'review_seller_verification',
      params: {
        'p_verification_id': verificationId,
        'p_decision': decision,
        'p_reason': reason,
      },
    );
  }
}
