import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/order_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/order_query.dart';
import '../data/report_evidence_upload.dart';
import '../data/report_reasons.dart';

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

class ReportableOrder {
  const ReportableOrder({
    required this.id,
    required this.orderNumber,
    required this.title,
  });

  final String id;
  final String orderNumber;
  final String title;
}

class ReportUserController extends ChangeNotifier {
  ReportUserController({
    required SupabaseService supabase,
    required AuthProvider auth,
    String? username,
    String? userId,
    String? orderId,
    ImagePicker? picker,
  }) : _supabase = supabase,
       _auth = auth,
       _initialUsername = username?.trim(),
       _initialUserId = userId?.trim(),
       _initialOrderId = orderId?.trim(),
       _picker = picker ?? ImagePicker() {
    load();
  }

  final SupabaseService _supabase;
  final AuthProvider _auth;
  final String? _initialUsername;
  final String? _initialUserId;
  final String? _initialOrderId;
  final ImagePicker _picker;

  String? _reportedUserId;
  String? _reportedUsername;
  String? _reportedDisplayName;
  String? _selectedCategory;
  String _details = '';
  String? _linkedOrderId;
  List<ReportableOrder> _orders = [];
  final List<ReportEvidenceDraft> _evidence = [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _evidenceError;
  String? _usernameQuery;

  String? get reportedUserId => _reportedUserId;
  String? get reportedUsername => _reportedUsername;
  String? get reportedDisplayName => _reportedDisplayName;
  String? get selectedCategory => _selectedCategory;
  String get details => _details;
  String? get linkedOrderId => _linkedOrderId;
  List<ReportableOrder> get orders => _orders;
  List<ReportEvidenceDraft> get evidence => List.unmodifiable(_evidence);
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  String? get evidenceError => _evidenceError;
  String? get usernameQuery => _usernameQuery;
  bool get hasResolvedTarget =>
      _reportedUserId != null && _reportedUserId!.isNotEmpty;

  bool get canSubmit {
    if (_isSubmitting || !hasResolvedTarget) return false;
    if (_selectedCategory == null) return false;
    if (reportDetailsError(_details) != null) return false;
    return _evidence.length >= kReportEvidenceMinCount;
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _resolveTarget(username: _initialUsername, userId: _initialUserId);
      if (_reportedUserId != null) {
        await _loadOrders(_reportedUserId!);
        if (_initialOrderId != null &&
            _orders.any((order) => order.id == _initialOrderId)) {
          _linkedOrderId = _initialOrderId;
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

  void setUsernameQuery(String value) {
    _usernameQuery = value.trim();
    notifyListeners();
  }

  Future<String?> resolveUsername() async {
    final query = (_usernameQuery ?? '').trim();
    if (query.isEmpty) return 'Enter a username to report.';
    _errorMessage = null;
    notifyListeners();
    try {
      await _resolveTarget(username: query.replaceFirst(RegExp(r'^@'), ''));
      if (!hasResolvedTarget) {
        return 'That user was not found.';
      }
      if (_reportedUserId == _auth.user?.id) {
        _reportedUserId = null;
        _reportedUsername = null;
        _reportedDisplayName = null;
        return 'You cannot report yourself.';
      }
      await _loadOrders(_reportedUserId!);
      return null;
    } catch (e) {
      debugPrint('ReportUserController.resolveUsername error: $e');
      return 'Unable to find that user.';
    } finally {
      notifyListeners();
    }
  }

  void selectCategory(String slug) {
    _selectedCategory = slug;
    notifyListeners();
  }

  void setDetails(String value) {
    _details = value;
    notifyListeners();
  }

  void setLinkedOrder(String? orderId) {
    _linkedOrderId = orderId;
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
      return 'You can attach up to $kReportEvidenceMaxCount photos.';
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
    if (_selectedCategory == null) return 'Please choose a reason.';
    final detailsError = reportDetailsError(_details);
    if (detailsError != null) return detailsError;
    if (_evidence.length < kReportEvidenceMinCount) {
      _evidenceError = 'Please attach at least one photo as evidence.';
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
          'p_order_id': _linkedOrderId,
        },
      );
      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not submit this report.',
        );
      }

      final map = supabaseRpcMap(rpcRes);
      reportId = map?['report_id']?.toString();
      if (reportId == null || reportId.isEmpty) {
        return 'Could not submit this report.';
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
        await abandonOpenReport(_supabase, reportId);
        return attachError;
      }
      return null;
    } catch (e) {
      debugPrint('ReportUserController.submit error: $e');
      if (reportId != null) {
        await abandonOpenReport(_supabase, reportId);
      }
      return 'Could not submit this report.';
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> _resolveTarget({String? username, String? userId}) async {
    Map<String, dynamic>? row;
    if (userId != null && userId.isNotEmpty) {
      row = await _supabase.client
          .from('user_public_profiles')
          .select('user_id, username, full_name')
          .eq('user_id', userId)
          .maybeSingle();
    }
    if (row == null && username != null && username.isNotEmpty) {
      row = await _supabase.client
          .from('user_public_profiles')
          .select('user_id, username, full_name')
          .eq('username', username)
          .maybeSingle();
    }
    _reportedUserId = row?['user_id'] as String?;
    _reportedUsername = row?['username'] as String?;
    _reportedDisplayName = row?['full_name'] as String? ?? _reportedUsername;
  }

  Future<void> _loadOrders(String reportedUserId) async {
    final myId = _auth.user?.id;
    if (myId == null) {
      _orders = [];
      return;
    }
    try {
      final buyerOrders = await fetchOrdersForBuyer(_supabase, myId);
      final sellerOrders = await fetchOrdersForSeller(_supabase, myId);
      final merged = <String, OrderModel>{};
      for (final order in [...buyerOrders, ...sellerOrders]) {
        final counterpart = order.buyerId == myId
            ? order.sellerId
            : order.buyerId;
        if (counterpart == reportedUserId) {
          merged[order.id] = order;
        }
      }
      _orders = merged.values
          .map(
            (order) => ReportableOrder(
              id: order.id,
              orderNumber: order.orderNumber,
              title: order.productTitle,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('ReportUserController._loadOrders error: $e');
      _orders = [];
    }
  }
}
