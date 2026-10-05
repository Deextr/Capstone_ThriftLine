import 'package:flutter_test/flutter_test.dart';

/// Mirrors v1 SQL policy: block extreme jumps for new/low-history buyers only.
bool shouldBlockNewAccountBid({
  required double jumpRatio,
  required int paidOrders,
  required Duration accountAge,
  required int bidsLastHour,
  required int bannedDeviceLinks,
}) {
  final established = paidOrders > 0;
  if (jumpRatio > 20 && !established && accountAge.inDays < 7) {
    return true;
  }
  if (jumpRatio > 10 && accountAge.inDays < 1 && !established) {
    return true;
  }
  if (bidsLastHour >= 15 && accountAge.inDays < 1) {
    return true;
  }
  if (bannedDeviceLinks > 0 && !established && jumpRatio > 15) {
    return true;
  }
  return false;
}

void main() {
  group('auction bid risk policy (new accounts)', () {
    test('blocks extreme jump for new buyer with no paid orders', () {
      expect(
        shouldBlockNewAccountBid(
          jumpRatio: 25,
          paidOrders: 0,
          accountAge: const Duration(days: 2),
          bidsLastHour: 1,
          bannedDeviceLinks: 0,
        ),
        isTrue,
      );
    });

    test('allows extreme jump for established buyer', () {
      expect(
        shouldBlockNewAccountBid(
          jumpRatio: 25,
          paidOrders: 2,
          accountAge: const Duration(days: 2),
          bidsLastHour: 1,
          bannedDeviceLinks: 0,
        ),
        isFalse,
      );
    });

    test('blocks high velocity on day-one account', () {
      expect(
        shouldBlockNewAccountBid(
          jumpRatio: 2,
          paidOrders: 0,
          accountAge: const Duration(hours: 12),
          bidsLastHour: 15,
          bannedDeviceLinks: 0,
        ),
        isTrue,
      );
    });
  });
}
