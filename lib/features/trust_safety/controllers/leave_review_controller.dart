import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/utils/supabase_rpc.dart';
import '../../../models/order_model.dart';
import '../../../models/review_model.dart';
import '../../../providers/auth_provider.dart';
import '../../buyer/data/order_query.dart';
import '../data/review_query.dart';
import '../data/review_rules.dart';

class LeaveReviewController extends ChangeNotifier {
  LeaveReviewController({
    required this.orderId,
    required SupabaseService supabase,
    required AuthProvider auth,
  }) : _supabase = supabase,
       _auth = auth {
    load();
  }

  final String orderId;
  final SupabaseService _supabase;
  final AuthProvider _auth;

  OrderModel? _order;
  ReviewModel? _existing;
  int _rating = 0;
  String _comment = '';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _readOnly = false;
  String? _errorMessage;

  OrderModel? get order => _order;
  ReviewModel? get existing => _existing;
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
      if (_existing != null) {
        _rating = _existing!.rating;
        _comment = _existing!.comment;
        _readOnly = !canEditReview(_existing!.createdAt);
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
    try {
      final rpcRes = _existing == null
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
      await load();
      return null;
    } catch (e) {
      debugPrint('LeaveReviewController.submit error: $e');
      return 'Could not save this review.';
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
