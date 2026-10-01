import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/seller/data/seller_payout_method.dart';
import 'package:thriftline/features/seller/data/seller_payout_method_service.dart';

void main() {
  group('GCash payout method', () {
    test('requires an account name', () {
      expect(gcashAccountNameError(''), isNotNull);
      expect(gcashAccountNameError('A'), isNotNull);
      expect(gcashAccountNameError('Maria Santos'), isNull);
    });

    test('requires 09XXXXXXXXX', () {
      expect(gcashMobileError(''), isNotNull);
      expect(gcashMobileError('0917'), isNotNull);
      expect(gcashMobileError('09171234567'), isNull);
      expect(gcashMobileError('+639171234567'), isNull);
    });

    test('treats a dropped connection as offline', () {
      expect(
        isLikelyOfflineError(Exception('SocketException: Failed host lookup')),
        isTrue,
      );
      expect(isLikelyOfflineError(Exception('permission denied')), isFalse);
    });

    test('parses a saved method', () {
      final method = SellerPayoutMethod.fromMap({
        'account_name': ' Maria Santos ',
        'mobile_number': '09171234567',
        'method': 'gcash',
      });
      expect(method.isComplete, isTrue);
      expect(method.accountName, 'Maria Santos');
    });
  });
}
