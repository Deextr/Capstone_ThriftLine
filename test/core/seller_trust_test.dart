import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/seller_trust.dart';
import 'package:thriftline/core/utils/seller_trust_explanation.dart';
import 'package:thriftline/features/auth/domain/auth_user.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/widgets/thrift_widgets.dart';

AuthUser _user({required int trustScore, String? trustLevel}) {
  return AuthUser(
    id: 'user-1',
    username: 'shop',
    name: 'Shop',
    email: 'shop@example.com',
    role: UserRole.seller,
    avatarUrl: '',
    location: 'Davao City',
    trustScore: trustScore,
    trustLevel: trustLevel,
  );
}

void main() {
  group('trust labels', () {
    test('buyer visibility hides score but allows level from server', () {
      expect(
        sellerTrustLevelVisible(trustScore: null, trustLevel: 'New Seller'),
        isTrue,
      );
      expect(
        sellerTrustLevelVisible(trustScore: 62, trustLevel: null),
        isTrue,
      );
      expect(
        sellerTrustLevelVisible(trustScore: null, trustLevel: null),
        isFalse,
      );
      expect(
        resolveTrustLabel(
          score: sellerTrustScoreForLabel(trustScore: null),
          storedLevel: 'Trusted Seller',
        ),
        'Trusted Seller',
      );
    });

    test('score bands use the paper classes', () {
      expect(resolveTrustLabel(score: 100), 'Highly Trusted Seller');
      expect(resolveTrustLabel(score: 90), 'Highly Trusted Seller');
      expect(resolveTrustLabel(score: 89), 'Trusted Seller');
      expect(resolveTrustLabel(score: 75), 'Trusted Seller');
      expect(resolveTrustLabel(score: 74), 'New Seller');
      expect(resolveTrustLabel(score: 60), 'New Seller');
      expect(resolveTrustLabel(score: 59), 'Under Review');
      expect(resolveTrustLabel(score: 40), 'Under Review');
      expect(resolveTrustLabel(score: 39), 'Banned');
      expect(resolveTrustLabel(score: 0), 'Banned');
    });

    test('a stored class is shown even when the score would map elsewhere', () {
      expect(
        resolveTrustLabel(score: 10, storedLevel: 'New Seller'),
        'New Seller',
      );
      expect(
        _user(trustScore: 62, trustLevel: 'New Seller').trustClassification,
        'New Seller',
      );
    });

    test('an unknown stored class falls back to the score', () {
      expect(
        _user(
          trustScore: 62,
          trustLevel: 'Developing Seller',
        ).trustClassification,
        'New Seller',
      );
    });

    test('the badge list matches the paper and does not auto-suspend', () {
      expect(trustClassifications.map((item) => item.label), [
        'Highly Trusted Seller',
        'Trusted Seller',
        'New Seller',
        'Under Review',
        'Banned',
      ]);
      final banned = trustClassifications.last;
      expect(banned.minScore, 0);
      expect(banned.maxScore, 39);
      expect(banned.description.toLowerCase(), contains('does not suspend'));
      expect(banned.description.toLowerCase(), isNot(contains('suspended')));
    });

    test('breakdown reads the stored criterion scores', () {
      final parsed = SellerTrustBreakdown.tryParse({
        'iv': 100,
        'st': 20,
        'ur': 90,
        'cr': 80,
        'weights': {'iv': 0.4},
      });
      expect(parsed?.identity, 100);
      expect(parsed?.transactions, 20);
      expect(parsed?.ratings, 90);
      expect(parsed?.reports, 80);
      expect(SellerTrustBreakdown.tryParse({'iv': 100}), isNull);
      expect(
        SellerTrustBreakdown.tryParse(
          '{"iv":100,"st":0,"ur":60,"cr":100}',
        )?.ratings,
        60,
      );
    });

    test('newly verified seller with no history mirrors IMRAD sample TS 62', () {
      final parsed = SellerTrustBreakdown.tryParse({
        'iv': 100,
        'st': 0,
        'ur': 60,
        'cr': 100,
        'confirmed_reports': 0,
        'rating_count': 0,
      });
      expect(parsed, isNotNull);
      expect(mirrorTrustWeightedSum(parsed!), 62);
      expect(resolveTrustLabel(score: 62), 'New Seller');
    });

    test('partial IV without email/phone lands in Under Review band', () {
      final parsed = SellerTrustBreakdown.tryParse({
        'iv': 50,
        'st': 0,
        'ur': 60,
        'cr': 100,
      });
      expect(mirrorTrustWeightedSum(parsed!), 42);
      expect(resolveTrustLabel(score: 42), 'Under Review');
    });

    test('breakdown reads counts and mirrors WSM for transparency', () {
      final parsed = SellerTrustBreakdown.tryParse({
        'iv': 100,
        'st': 40,
        'ur': 80,
        'cr': 100,
        'completed_orders': 16,
        'confirmed_reports': 0,
        'rating_count': 5,
      });
      expect(sellerTrustTransactionCount(parsed!), 16);
      expect(parsed?.confirmedReports, 0);
      expect(mirrorTrustWeightedSum(parsed!), 78);
    });

    test('transaction copy uses server count tiers', () {
      const breakdown = SellerTrustBreakdown(
        identity: 100,
        transactions: 40,
        ratings: 80,
        reports: 100,
        eligibleTransactions: 16,
      );
      expect(
        SellerTrustExplanation.transactionRangeLabel(16),
        '11–20 transaction range',
      );
      expect(
        SellerTrustExplanation.transactionDetail(breakdown),
        contains('16 completed transaction'),
      );
    });
  });
}
