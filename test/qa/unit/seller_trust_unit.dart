import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/seller_trust.dart';

import '../support/qa_reporter.dart';

void sellerTrustUnitTests() {
  qaGroup('Seller trust', () {
    qaUnitTest('resolveTrustLabel maps score boundaries (Table 17)', () {
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

    qaUnitTest('resolveTrustLabel prefers a valid stored level', () {
      expect(
        resolveTrustLabel(score: 10, storedLevel: 'Trusted Seller'),
        'Trusted Seller',
      );
      expect(
        resolveTrustLabel(score: 10, storedLevel: '  New Seller  '),
        'New Seller',
      );
    });

    qaUnitTest('resolveTrustLabel ignores unknown or blank levels', () {
      expect(
        resolveTrustLabel(score: 95, storedLevel: 'Gold'),
        'Highly Trusted Seller',
      );
      expect(resolveTrustLabel(score: 45, storedLevel: '  '), 'Under Review');
    });

    qaUnitTest('WSM weights add up to 1.0', () {
      final sum =
          SellerTrustWeights.identity +
          SellerTrustWeights.transactions +
          SellerTrustWeights.ratings +
          SellerTrustWeights.reports;
      expect(sum, closeTo(1.0, 1e-9));
    });

    qaUnitTest('mirrorTrustWeightedSum applies the weights', () {
      const breakdown = SellerTrustBreakdown(
        identity: 100,
        transactions: 80,
        ratings: 90,
        reports: 100,
      );
      // 40 + 24 + 18 + 10
      expect(mirrorTrustWeightedSum(breakdown), 92);
    });

    qaGroup('SellerTrustBreakdown.tryParse', () {
      final raw = {
        'iv': 100,
        'st': 60,
        'ur': 80.0,
        'cr': 100,
        'completed_thriftline': 7,
        'completed_orders': 9,
        'confirmed_reports': 1,
        'rating_count': 12,
        'weights': {'iv': 0.4, 'st': 0.3, 'ur': 0.2, 'cr': 0.1},
      };

      qaUnitTest('parses a map payload', () {
        final parsed = SellerTrustBreakdown.tryParse(raw)!;
        expect(parsed.identity, 100);
        expect(parsed.transactions, 60);
        expect(parsed.ratings, 80);
        expect(parsed.reports, 100);
        expect(parsed.ratingCount, 12);
        expect(parsed.weights!['iv'], 0.4);
      });

      qaUnitTest('parses a JSON string payload', () {
        final parsed = SellerTrustBreakdown.tryParse(jsonEncode(raw));
        expect(parsed, isNotNull);
        expect(parsed!.transactions, 60);
      });

      qaUnitTest('eligible transactions fall back to completed_orders', () {
        final parsed = SellerTrustBreakdown.tryParse(raw)!;
        expect(parsed.eligibleTransactions, 9);
        expect(parsed.transactionCountForRubric, 9);
      });

      qaUnitTest('returns null for missing scores or bad input', () {
        expect(SellerTrustBreakdown.tryParse({'iv': 1, 'st': 2}), isNull);
        expect(SellerTrustBreakdown.tryParse('not json'), isNull);
        expect(SellerTrustBreakdown.tryParse(42), isNull);
        expect(SellerTrustBreakdown.tryParse(null), isNull);
      });
    });

    qaUnitTest('count helpers fall back safely', () {
      const onlyThriftline = SellerTrustBreakdown(
        identity: 0,
        transactions: 0,
        ratings: 0,
        reports: 0,
        completedThriftline: 7,
      );
      const empty = SellerTrustBreakdown(
        identity: 0,
        transactions: 0,
        ratings: 0,
        reports: 0,
      );
      expect(sellerTrustTransactionCount(onlyThriftline), 7);
      expect(sellerTrustTransactionCount(empty), 0);
      expect(sellerTrustConfirmedReportCount(empty), 0);
    });
  });
}
