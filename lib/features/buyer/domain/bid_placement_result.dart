import '../../../core/utils/supabase_errors.dart';

class BidPlacementResult {
  const BidPlacementResult._({this.error, this.code});

  final String? error;
  final String? code;

  bool get isSuccess => error == null;

  static const success = BidPlacementResult._();

  static BidPlacementResult failure(String message, {String? code}) {
    return BidPlacementResult._(error: message, code: code);
  }

  /// Maps RPC JSON failures and transport/database exceptions to user-safe copy.
  static BidPlacementResult fromFailure(
    Object error, {
    dynamic rpcRes,
    String fallback = 'Failed to place bid. Please try again.',
  }) {
    if (rpcRes != null) {
      return fromRpc(rpcRes, fallback: fallback);
    }
    if (isLikelyNetworkError(error)) {
      return failure(
        'Unable to place bid. Check your connection and try again.',
      );
    }
    return failure(fallback);
  }

  static BidPlacementResult fromRpc(
    dynamic rpcRes, {
    String fallback = 'Failed to place bid.',
  }) {
    if (rpcRes is Map && rpcRes['success'] == true) {
      return success;
    }
    final map = rpcRes is Map ? Map<String, dynamic>.from(rpcRes) : null;
    final error = map?['error']?.toString().trim();
    final code = map?['code']?.toString().trim();
    return failure(
      error != null && error.isNotEmpty ? error : fallback,
      code: code,
    );
  }
}
