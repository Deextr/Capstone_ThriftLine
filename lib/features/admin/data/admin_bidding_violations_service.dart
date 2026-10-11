import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/auction_bidding_violations.dart';

class BiddingViolationsOverviewStats {
  const BiddingViolationsOverviewStats({
    required this.buyersWithViolations,
    required this.totalViolationEvents,
    required this.repeatViolators,
    required this.restrictedBuyers,
  });

  final int buyersWithViolations;
  final int totalViolationEvents;
  final int repeatViolators;
  final int restrictedBuyers;

  static const empty = BiddingViolationsOverviewStats(
    buyersWithViolations: 0,
    totalViolationEvents: 0,
    repeatViolators: 0,
    restrictedBuyers: 0,
  );
}

class BiddingViolatorSummary {
  const BiddingViolatorSummary({
    required this.userId,
    required this.displayName,
    required this.email,
    required this.username,
    required this.accountStatus,
    required this.violationCount,
    required this.latestViolationAt,
    required this.restrictedUntil,
    required this.permanentlyDisabledAt,
    required this.disableReason,
    required this.enforcementStatus,
  });

  final String userId;
  final String displayName;
  final String email;
  final String username;
  final String accountStatus;
  final int violationCount;
  final DateTime? latestViolationAt;
  final DateTime? restrictedUntil;
  final DateTime? permanentlyDisabledAt;
  final String? disableReason;
  final BiddingEnforcementStatus enforcementStatus;

  String get violationStage => violationStageLabel(violationCount);

  /// Re-evaluated at read time so expired 3-day restrictions show as Active.
  BiddingEnforcementStatus enforcementStatusAt([DateTime? now]) {
    return resolveBiddingEnforcementStatus(
      permanentlyDisabledAt: permanentlyDisabledAt,
      restrictedUntil: restrictedUntil,
      accountStatus: accountStatus,
      now: now,
    );
  }
}

class BiddingViolationHistoryEntry {
  const BiddingViolationHistoryEntry({
    required this.violationId,
    required this.violationNumber,
    required this.consequence,
    required this.createdAt,
    required this.paymentDueAt,
    required this.expiredAt,
    required this.auctionId,
    required this.orderId,
    required this.bidRound,
    required this.productName,
  });

  final String violationId;
  final int violationNumber;
  final String consequence;
  final DateTime createdAt;
  final DateTime paymentDueAt;
  final DateTime expiredAt;
  final String auctionId;
  final String orderId;
  final int bidRound;
  final String productName;

  String get violationType => kAuctionNonPaymentViolationType;
}

class AdminBiddingViolationsService {
  AdminBiddingViolationsService({required SupabaseService supabase})
    : _client = supabase.client;

  final SupabaseClient _client;

  Future<
    ({
      List<BiddingViolatorSummary> summaries,
      BiddingViolationsOverviewStats stats,
    })
  >
  loadViolators() async {
    final sanctionRows = await _client
        .from('auction_bidding_sanctions')
        .select('''
          user_id,
          violation_count,
          restricted_until,
          permanently_disabled_at,
          disable_reason,
          updated_at,
          users!inner(
            user_id,
            full_name,
            email,
            username,
            account_status
          )
        ''')
        .gt('violation_count', 0)
        .order('updated_at', ascending: false);

    final violationRows = await _client
        .from('auction_bidding_violations')
        .select('user_id, created_at')
        .order('created_at', ascending: false);

    final latestByUser = <String, DateTime>{};
    var totalEvents = 0;
    for (final raw in violationRows as List) {
      if (raw is! Map) continue;
      totalEvents++;
      final userId = raw['user_id'] as String? ?? '';
      if (userId.isEmpty) continue;
      latestByUser.putIfAbsent(
        userId,
        () =>
            DateTime.tryParse(raw['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    }

    final now = DateTime.now();
    final summaries = <BiddingViolatorSummary>[];
    var repeatViolators = 0;
    var restrictedBuyers = 0;

    for (final raw in sanctionRows as List) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final userRaw = map['users'];
      if (userRaw is! Map) continue;
      final user = Map<String, dynamic>.from(userRaw);

      final userId =
          map['user_id'] as String? ?? user['user_id'] as String? ?? '';
      final violationCount = (map['violation_count'] as num?)?.toInt() ?? 0;
      if (violationCount <= 0) continue;

      final restrictedUntil = _parseDate(map['restricted_until']);
      final permanentlyDisabledAt = _parseDate(map['permanently_disabled_at']);
      final accountStatus = user['account_status'] as String? ?? 'active';
      final enforcement = resolveBiddingEnforcementStatus(
        permanentlyDisabledAt: permanentlyDisabledAt,
        restrictedUntil: restrictedUntil,
        accountStatus: accountStatus,
        now: now,
      );

      if (violationCount > 1) repeatViolators++;
      if (enforcement == BiddingEnforcementStatus.restricted) {
        restrictedBuyers++;
      }

      final fullName = (user['full_name'] as String?)?.trim() ?? '';
      summaries.add(
        BiddingViolatorSummary(
          userId: userId,
          displayName: fullName.isNotEmpty ? fullName : 'Buyer',
          email: (user['email'] as String?)?.trim() ?? '',
          username: (user['username'] as String?)?.trim() ?? '',
          accountStatus: accountStatus,
          violationCount: violationCount,
          latestViolationAt: latestByUser[userId],
          restrictedUntil: restrictedUntil,
          permanentlyDisabledAt: permanentlyDisabledAt,
          disableReason: map['disable_reason'] as String?,
          enforcementStatus: enforcement,
        ),
      );
    }

    summaries.sort((a, b) {
      final aDate =
          a.latestViolationAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.latestViolationAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final stats = BiddingViolationsOverviewStats(
      buyersWithViolations: summaries.length,
      totalViolationEvents: totalEvents,
      repeatViolators: repeatViolators,
      restrictedBuyers: restrictedBuyers,
    );

    return (summaries: summaries, stats: stats);
  }

  Future<List<BiddingViolationHistoryEntry>> loadViolationHistory(
    String userId,
  ) async {
    if (userId.trim().isEmpty) return const [];

    final rows = await _client
        .from('auction_bidding_violations')
        .select('''
          violation_id,
          violation_number,
          consequence,
          payment_due_at,
          expired_at,
          created_at,
          auction_id,
          order_id,
          bid_round,
          auctions (
            products ( name )
          )
        ''')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (rows as List)
        .whereType<Map>()
        .map((raw) => _historyFromRow(Map<String, dynamic>.from(raw)))
        .toList();
  }

  BiddingViolationHistoryEntry _historyFromRow(Map<String, dynamic> row) {
    var productName = '';
    final auctionRaw = row['auctions'];
    if (auctionRaw is Map) {
      final productRaw = auctionRaw['products'];
      if (productRaw is Map) {
        productName = (productRaw['name'] as String?)?.trim() ?? '';
      } else if (productRaw is List && productRaw.isNotEmpty) {
        final first = productRaw.first;
        if (first is Map) {
          productName = (first['name'] as String?)?.trim() ?? '';
        }
      }
    }

    return BiddingViolationHistoryEntry(
      violationId: row['violation_id'] as String? ?? '',
      violationNumber: (row['violation_number'] as num?)?.toInt() ?? 0,
      consequence: row['consequence'] as String? ?? '',
      createdAt:
          _parseDate(row['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      paymentDueAt:
          _parseDate(row['payment_due_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      expiredAt:
          _parseDate(row['expired_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      auctionId: row['auction_id'] as String? ?? '',
      orderId: row['order_id'] as String? ?? '',
      bidRound: (row['bid_round'] as num?)?.toInt() ?? 1,
      productName: productName.isNotEmpty ? productName : 'Auction listing',
    );
  }

  DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
