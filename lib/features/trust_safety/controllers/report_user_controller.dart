import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../features/profile/data/followed_shop_item.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/following_shops_provider.dart';
import '../data/report_evidence_upload.dart';
import '../data/report_reasons.dart';
import '../data/report_seller_search.dart';

class ReportEvidenceDraft {
  const ReportEvidenceDraft({
    required this.bytes,
    required this.name,
    required this.contentType,
  });

  final Uint8List bytes;
  final String name;
  final String contentType;
}

class ReportUserController extends ChangeNotifier {
  ReportUserController({
    required SupabaseService supabase,
    required AuthProvider auth,
    FollowingShopsProvider? followingShops,
    String? username,
    String? userId,
    ImagePicker? picker,
  }) : _supabase = supabase,
       _auth = auth,
       _followingShops = followingShops,
       _initialUsername = username?.trim(),
       _initialUserId = userId?.trim(),
       _picker = picker ?? ImagePicker() {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final FollowingShopsProvider? _followingShops;
  final String? _initialUsername;
  final String? _initialUserId;
  final ImagePicker _picker;

  String? _reportedUserId;
  String? _reportedUsername;
  String? _reportedDisplayName;
  String? _reportedAvatarUrl;
  String? _reportedShopName;
  String? _selectedCategory;
  String _details = '';
  final List<ReportEvidenceDraft> _evidence = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _submitLocked = false;
  String? _errorMessage;
  String? _evidenceError;

  String _searchQuery = '';
  List<ReportSellerCandidate> _searchResults = [];
  bool _isSearching = false;
  int _searchGeneration = 0;
  Timer? _searchDebounce;

  String? get reportedUserId => _reportedUserId;
  String? get reportedUsername => _reportedUsername;
  String? get reportedDisplayName => _reportedDisplayName;
  String? get reportedAvatarUrl => _reportedAvatarUrl;
  String? get reportedShopName => _reportedShopName;
  String? get selectedCategory => _selectedCategory;
  String get details => _details;
  List<ReportEvidenceDraft> get evidence => List.unmodifiable(_evidence);
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  String? get evidenceError => _evidenceError;
  String get searchQuery => _searchQuery;
  List<ReportSellerCandidate> get searchResults =>
      List.unmodifiable(_searchResults);
  bool get isSearching => _isSearching;
  bool get isSearchActive => _searchQuery.trim().length >= kReportSellerSearchMinChars;

  bool get hasResolvedTarget =>
      _reportedUserId != null && _reportedUserId!.isNotEmpty;

  ReportSellerCandidate? get selectedSeller {
    if (!hasResolvedTarget) return null;
    return ReportSellerCandidate(
      sellerId: _reportedUserId!,
      username: _reportedUsername ?? '',
      displayName: _reportedDisplayName ?? 'Seller',
      shopName: _reportedShopName ?? _reportedDisplayName ?? 'Seller',
      avatarUrl: _reportedAvatarUrl ?? '',
    );
  }

  List<FollowedShopItem> get allFollowedShops =>
      _followingShops?.followedShops ?? const [];

  List<FollowedShopItem> get followedShopPreview {
    return allFollowedShops.take(kReportFollowingShopsPreviewLimit).toList();
  }

  bool get hasMoreFollowedShops =>
      allFollowedShops.length > kReportFollowingShopsPreviewLimit;

  bool get isLoadingFollowedShops => _followingShops?.isLoading ?? false;

  bool get detailsRequired => _selectedCategory == 'other';

  bool get canSubmit {
    if (_isSubmitting || _submitLocked || !hasResolvedTarget) return false;
    if (_selectedCategory == null) return false;
    if (communityReportDetailsError(_details, _selectedCategory) != null) {
      return false;
    }
    return _evidence.length >= kReportEvidenceMinCount;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      unawaited(_followingShops?.refresh());
      if (_initialUserId != null || _initialUsername != null) {
        final error = await _resolveTarget(
          username: _initialUsername,
          userId: _initialUserId,
        );
        if (error != null) {
          _errorMessage = error;
        }
      }
    } catch (e) {
      debugPrint('ReportUserController.load error: $e');
      _errorMessage = 'Unable to load this report.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String value) {
    _searchQuery = value;
    _searchDebounce?.cancel();

    if (value.trim().length < kReportSellerSearchMinChars) {
      _searchGeneration++;
      _searchResults = [];
      _isSearching = false;
      notifyListeners();
      return;
    }

    _isSearching = true;
    notifyListeners();

    _searchDebounce = Timer(
      const Duration(milliseconds: kReportSellerSearchDebounceMs),
      () => _runSellerSearch(value.trim()),
    );
  }

  Future<void> _runSellerSearch(String query) async {
    final generation = ++_searchGeneration;
    try {
      final results = await searchReportableSellers(_supabase, query);
      if (generation != _searchGeneration) return;
      _searchResults = results;
    } catch (e) {
      debugPrint('ReportUserController._runSellerSearch error: $e');
      if (generation != _searchGeneration) return;
      _searchResults = [];
    } finally {
      if (generation == _searchGeneration) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  String? selectSeller(ReportSellerCandidate candidate) {
    if (candidate.sellerId.isEmpty) {
      return 'That seller could not be selected.';
    }
    if (candidate.sellerId == _auth.user?.id) {
      return 'You cannot report yourself.';
    }
    _applyCandidate(candidate);
    _searchDebounce?.cancel();
    _searchGeneration++;
    _searchResults = [];
    _isSearching = false;
    notifyListeners();
    return null;
  }

  void clearSelectedSeller() {
    _reportedUserId = null;
    _reportedUsername = null;
    _reportedDisplayName = null;
    _reportedAvatarUrl = null;
    _reportedShopName = null;
    notifyListeners();
  }

  void selectCategory(String slug) {
    _selectedCategory = slug;
    notifyListeners();
  }

  void setDetails(String value) {
    if (value.length > kReportDetailsMaxLength) return;
    _details = value;
    notifyListeners();
  }

  Future<String?> addEvidenceFromGallery() =>
      _addEvidence(ImageSource.gallery, multi: true);

  Future<String?> addEvidenceFromCamera() =>
      _addEvidence(ImageSource.camera, multi: false);

  Future<String?> _addEvidence(
    ImageSource source, {
    required bool multi,
  }) async {
    _evidenceError = null;
    if (_evidence.length >= kReportEvidenceMaxCount) {
      return 'You can upload up to $kReportEvidenceMaxCount photos.';
    }
    try {
      if (multi) {
        final files = await _picker.pickMultiImage(imageQuality: 80);
        if (files.isEmpty) return null;
        for (final file in files) {
          if (_evidence.length >= kReportEvidenceMaxCount) break;
          final err = await _appendEvidenceFile(file);
          if (err != null) return err;
        }
      } else {
        final file = await _picker.pickImage(source: source, imageQuality: 80);
        if (file == null) return null;
        final err = await _appendEvidenceFile(file);
        if (err != null) return err;
      }
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('ReportUserController.addEvidence error: $e');
      return 'Could not add that photo.';
    }
  }

  Future<String?> _appendEvidenceFile(XFile file) async {
    if (!isAllowedReportImageName(file.name)) {
      return 'Please choose a JPG, PNG, or WebP photo.';
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > kReportEvidenceMaxBytes) {
      return 'Each photo must be 5 MB or smaller.';
    }
    _evidence.add(
      ReportEvidenceDraft(
        bytes: bytes,
        name: file.name,
        contentType: reportImageContentType(file.name),
      ),
    );
    return null;
  }

  void removeEvidence(int index) {
    if (index < 0 || index >= _evidence.length) return;
    _evidence.removeAt(index);
    _evidenceError = null;
    notifyListeners();
  }

  Future<String?> submit() async {
    if (_isSubmitting) return null;
    if (!hasResolvedTarget) return 'Choose who you are reporting.';
    if (_reportedUserId == _auth.user?.id) {
      return 'You cannot report yourself.';
    }
    if (_selectedCategory == null) return 'Select a reason for your report.';
    final detailsError = communityReportDetailsError(_details, _selectedCategory);
    if (detailsError != null) return detailsError;
    if (_evidence.length < kReportEvidenceMinCount) {
      _evidenceError = 'Add at least one photo as evidence.';
      notifyListeners();
      return _evidenceError;
    }

    _isSubmitting = true;
    notifyListeners();
    String? reportId;
    try {
      final rpcRes = await _supabase.client.rpc(
        'submit_report',
        params: {
          'p_reported_user_id': _reportedUserId,
          'p_category': _selectedCategory,
          'p_details': _details.trim(),
          'p_order_id': null,
        },
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'We couldn\'t submit your report. Please try again.',
        );
      }

      final map = supabaseRpcMap(rpcRes);
      reportId = map?['report_id']?.toString();
      if (reportId == null || reportId.isEmpty) {
        return 'We couldn\'t submit your report. Please try again.';
      }

      final uid = _auth.user?.id;
      if (uid == null) return 'Please sign in.';
      final attachError = await uploadReportEvidence(
        supabase: _supabase,
        uid: uid,
        reportId: reportId,
        evidence: _evidence,
      );
      if (attachError != null) {
        await confirmCommunityReportSubmission(_supabase, reportId);
        return 'We couldn\'t upload your evidence. Please try again.';
      }

      final confirmError = await confirmCommunityReportSubmission(
        _supabase,
        reportId,
      );
      if (confirmError != null) {
        return confirmError;
      }
      _submitLocked = true;
      return null;
    } catch (e) {
      debugPrint('ReportUserController.submit error: $e');
      if (reportId != null) {
        await confirmCommunityReportSubmission(_supabase, reportId);
      }
      return 'We couldn\'t submit your report. Please try again.';
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void _applyCandidate(ReportSellerCandidate candidate) {
    _reportedUserId = candidate.sellerId;
    _reportedUsername = candidate.username;
    _reportedDisplayName = candidate.displayName;
    _reportedAvatarUrl = candidate.avatarUrl;
    _reportedShopName = candidate.shopName;
  }

  Future<String?> _resolveTarget({String? username, String? userId}) async {
    Map<String, dynamic>? row;
    if (userId != null && userId.isNotEmpty) {
      row = await _supabase.client
          .from('user_public_profiles')
          .select('user_id, username, full_name, avatar, role')
          .eq('user_id', userId)
          .maybeSingle();
    }
    if (row == null && username != null && username.isNotEmpty) {
      row = await _supabase.client
          .from('user_public_profiles')
          .select('user_id, username, full_name, avatar, role')
          .eq('username', username.replaceFirst(RegExp(r'^@'), ''))
          .maybeSingle();
    }

    final resolvedId = row?['user_id'] as String?;
    if (resolvedId == null) {
      _clearTargetFields();
      return 'That seller was not found.';
    }
    if (resolvedId == _auth.user?.id) {
      _clearTargetFields();
      return 'You cannot report yourself.';
    }

    final approved = await _isApprovedSeller(resolvedId);
    if (!approved) {
      _clearTargetFields();
      return 'That account is not an eligible seller to report.';
    }

    _reportedUserId = resolvedId;
    _reportedUsername = row?['username'] as String?;
    _reportedDisplayName = row?['full_name'] as String? ?? _reportedUsername;
    _reportedAvatarUrl = row?['avatar'] as String?;

    _reportedShopName = null;
    try {
      final shop = await _supabase.client
          .from('seller_profiles')
          .select('shop_name')
          .eq('seller_id', resolvedId)
          .eq('is_approved', true)
          .maybeSingle();
      final name = shop?['shop_name'] as String?;
      if (name != null && name.trim().isNotEmpty) {
        _reportedShopName = name.trim();
      }
    } catch (e) {
      debugPrint('ReportUserController shop lookup: $e');
    }
    return null;
  }

  Future<bool> _isApprovedSeller(String sellerId) async {
    try {
      final row = await _supabase.client
          .from('seller_profiles')
          .select('seller_id')
          .eq('seller_id', sellerId)
          .eq('is_approved', true)
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('ReportUserController._isApprovedSeller error: $e');
      return false;
    }
  }

  void _clearTargetFields() {
    _reportedUserId = null;
    _reportedUsername = null;
    _reportedDisplayName = null;
    _reportedAvatarUrl = null;
    _reportedShopName = null;
  }
}
