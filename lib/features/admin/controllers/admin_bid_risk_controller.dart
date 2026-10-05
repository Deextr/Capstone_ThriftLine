import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';

class AdminBidRiskEvent {
  const AdminBidRiskEvent({
    required this.id,
    required this.userId,
    required this.auctionId,
    required this.attemptedAmount,
    required this.riskLevel,
    required this.actionTaken,
    required this.reasons,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String auctionId;
  final double attemptedAmount;
  final String riskLevel;
  final String actionTaken;
  final List<String> reasons;
  final DateTime createdAt;

  factory AdminBidRiskEvent.fromRow(Map<String, dynamic> row) {
    final reasonsRaw = row['reasons'];
    final reasons = <String>[];
    if (reasonsRaw is List) {
      for (final item in reasonsRaw) {
        if (item != null) reasons.add(item.toString());
      }
    }
    return AdminBidRiskEvent(
      id: row['event_id'] as String? ?? '',
      userId: row['user_id'] as String? ?? '',
      auctionId: row['auction_id'] as String? ?? '',
      attemptedAmount: (row['attempted_amount'] as num?)?.toDouble() ?? 0,
      riskLevel: row['risk_level'] as String? ?? 'low',
      actionTaken: row['action_taken'] as String? ?? 'allowed',
      reasons: reasons,
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class AdminBidRiskController extends ChangeNotifier {
  AdminBidRiskController({required SupabaseService supabase})
    : _supabase = supabase;

  final SupabaseService _supabase;

  bool _loading = false;
  String? _error;
  List<AdminBidRiskEvent> _events = const [];

  bool get isLoading => _loading;
  String? get error => _error;
  List<AdminBidRiskEvent> get events => _events;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final rows = await _supabase.client
          .from('auction_bid_risk_events')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      _events = (rows as List)
          .map(
            (e) =>
                AdminBidRiskEvent.fromRow(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('AdminBidRiskController.load: $e');
      _error = 'Unable to load bid risk events.';
      _events = const [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
