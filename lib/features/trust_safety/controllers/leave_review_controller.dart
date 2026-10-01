import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/order_model.dart';
import '../../../models/review_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/order_query.dart';
import '../data/report_reasons.dart';
import '../data/review_photo_upload.dart';
import '../data/review_query.dart';
import '../data/review_rules.dart';
import 'report_user_controller.dart';

class LeaveReviewController extends ChangeNotifier {
  LeaveReviewController({
    required this.orderId,
    required SupabaseService supabase,
    required AuthProvider auth,
    ImagePicker? picker,
  }) : _supabase = supabase,
       _auth = auth,
       _picker = picker ?? ImagePicker() {
    load();
  }

  final String orderId;
  final SupabaseService _supabase;
  final AuthProvider _auth;
  final ImagePicker _picker;

  OrderModel? _order;
  ReviewModel? _existing;
  List<ReviewPhoto> _existingPhotos = [];
  final List<ReportEvidenceDraft> _photoDrafts = [];
  final List<ReviewPhoto> _removedPhotos = [];
  int _rating = 0;
  String _comment = '';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _readOnly = false;
  String? _errorMessage;

  OrderModel? get order => _order;
  ReviewModel? get existing => _existing;
  List<ReviewPhoto> get existingPhotos => List.unmodifiable(
    _existingPhotos.where(
      (p) => !_removedPhotos.any((removed) => removed.id == p.id),
    ),
  );
  List<ReportEvidenceDraft> get photoDrafts => List.unmodifiable(_photoDrafts);
  int get rating => _rating;
  String get comment => _comment;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get readOnly => _readOnly;
  String? get errorMessage => _errorMessage;

  String get myId => _auth.user?.id ?? '';

  bool get isSellerReviewingBuyer =>
      _order != null && myId.isNotEmpty && _order!.sellerId == myId;

  bool get canSubmit {
    if (_isSaving || _readOnly || _order == null) return false;
    return reviewRatingError(_rating) == null &&
        reviewCommentError(_comment) == null;
  }

  String get counterpartName {
    if (_order == null) return 'this member';
    return isSellerReviewingBuyer ? _order!.buyerName : _order!.sellerName;
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uid = myId;
      OrderModel? found;
      if (uid.isNotEmpty) {
        found = await fetchOrderById(_supabase, orderId, buyerId: uid);
        found ??= await fetchOrderById(_supabase, orderId, sellerId: uid);
      }

      if (found == null) {
        _errorMessage = 'Order not found.';
        _order = null;
        return;
      }
      if (!found.isCompleted) {
        _errorMessage = 'You can review only after this order is completed.';
        _order = found;
        return;
      }

      _order = found;
      final mine = await fetchMyReviewsForOrders(_supabase, uid, [found.id]);
      _existing = mine[found.id];
      _photoDrafts.clear();
      _removedPhotos.clear();
      if (_existing != null) {
        _rating = _existing!.rating;
        _comment = _existing!.comment;
        _readOnly = !canEditReview(_existing!.createdAt);
        _existingPhotos = _existing!.photos
            .map(
              (p) => p.copyWith(
                publicUrl:
                    p.publicUrl ?? reviewPhotoPublicUrl(_supabase, p.filePath),
              ),
            )
            .toList();
      } else {
        _existingPhotos = [];
      }
    } catch (e) {
      debugPrint('LeaveReviewController.load error: $e');
      _errorMessage = 'Unable to load this review.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setRating(int value) {
    if (_readOnly || _isSaving) return;
    _rating = value;
    notifyListeners();
  }

  void setComment(String value) {
    if (_readOnly || _isSaving) return;
    _comment = value;
    notifyListeners();
  }

  Future<String?> addPhotoFromGallery() async {
    if (_readOnly || isSellerReviewingBuyer) return null;
    try {
      final files = await _picker.pickMultiImage(imageQuality: 80);
      if (files.isEmpty) return null;
      for (final file in files) {
        if (existingPhotos.length + _photoDrafts.length >=
            kReviewPhotoMaxCount) {
          break;
        }
        final err = await _appendPhotoFile(file);
        if (err != null) return err;
      }
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('LeaveReviewController.addPhotoFromGallery error: $e');
      return 'Could not add that photo.';
    }
  }

  Future<String?> addPhotoFromCamera() => _addSinglePhoto(ImageSource.camera);

  Future<String?> _addSinglePhoto(ImageSource source) async {
    if (_readOnly || isSellerReviewingBuyer) return null;
    if (existingPhotos.length + _photoDrafts.length >= kReviewPhotoMaxCount) {
      return 'You can attach up to $kReviewPhotoMaxCount photos.';
    }
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 80);
      if (file == null) return null;
      final err = await _appendPhotoFile(file);
      if (err != null) return err;
      notifyListeners();
      return null;
    } catch (e) {
      debugPrint('LeaveReviewController.addPhoto error: $e');
      return 'Could not add that photo.';
    }
  }

  Future<String?> _appendPhotoFile(XFile file) async {
    if (!isAllowedReportImageName(file.name)) {
      return 'Please choose a JPG, PNG, or WebP photo.';
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > kReportEvidenceMaxBytes) {
      return 'Each photo must be 5 MB or smaller.';
    }
    _photoDrafts.add(
      ReportEvidenceDraft(
        bytes: bytes,
        name: file.name,
        contentType: reportImageContentType(file.name),
      ),
    );
    return null;
  }

  void removePhotoDraft(int index) {
    if (_readOnly || index < 0 || index >= _photoDrafts.length) return;
    _photoDrafts.removeAt(index);
    notifyListeners();
  }

  void markExistingPhotoRemoved(ReviewPhoto photo) {
    if (_readOnly) return;
    if (!_removedPhotos.contains(photo)) {
      _removedPhotos.add(photo);
      notifyListeners();
    }
  }

  Future<String?> submit() async {
    if (_order == null) return 'Order not found.';
    final ratingError = reviewRatingError(_rating);
    if (ratingError != null) return ratingError;
    final commentError = reviewCommentError(_comment);
    if (commentError != null) return commentError;
    if (_readOnly) return 'This review can no longer be edited.';
    if (_isSaving) return null;

    _isSaving = true;
    notifyListeners();
    final isNew = _existing == null;
    String? reviewId;
    try {
      final rpcRes = isNew
          ? await _supabase.client.rpc(
              'submit_review',
              params: {
                'p_order_id': orderId,
                'p_rating': _rating,
                'p_review_text': _comment.trim(),
              },
            )
          : await _supabase.client.rpc(
              'update_review',
              params: {
                'p_review_id': _existing!.id,
                'p_rating': _rating,
                'p_review_text': _comment.trim(),
              },
            );

      if (!supabaseRpcSuccess(rpcRes)) {
        return supabaseRpcError(
          rpcRes,
          fallback: 'Could not save this review.',
        );
      }

      if (isNew) {
        reviewId = supabaseRpcMap(rpcRes)?['review_id']?.toString();
      } else {
        reviewId = _existing!.id;
      }
      if (reviewId == null || reviewId.isEmpty) {
        return 'Could not save this review.';
      }

      final uid = myId;
      if (uid.isEmpty) return 'Please sign in.';

      for (final removed in _removedPhotos) {
        if (removed.id.isNotEmpty) {
          await removeReviewPhoto(_supabase, removed.id);
        }
      }

      if (_photoDrafts.isNotEmpty && !isSellerReviewingBuyer) {
        final uploadError = await uploadReviewPhotos(
          supabase: _supabase,
          uid: uid,
          reviewId: reviewId,
          photos: _photoDrafts,
        );
        if (uploadError != null) {
          if (isNew) {
            await rollbackReviewWithoutPhotos(_supabase, reviewId);
          }
          return uploadError;
        }
      }

      await load();
      return null;
    } catch (e) {
      debugPrint('LeaveReviewController.submit error: $e');
      if (isNew && reviewId != null) {
        await rollbackReviewWithoutPhotos(_supabase, reviewId);
      }
      return 'Could not save this review.';
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
