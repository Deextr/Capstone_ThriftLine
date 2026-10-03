import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/auth/domain/account_mode.dart';
import 'package:thriftline/providers/settings_provider.dart';

void main() {
  test('UserSettings maps buyer and seller columns separately', () {
    final settings = UserSettings.fromJson({
      'buyer_push_notifications_enabled': false,
      'seller_push_notifications_enabled': true,
      'buyer_email_notifications_enabled': true,
      'seller_email_notifications_enabled': false,
    });
    expect(settings.pushFor(AccountMode.buyer), isFalse);
    expect(settings.pushFor(AccountMode.seller), isTrue);
    expect(settings.emailFor(AccountMode.buyer), isTrue);
    expect(settings.emailFor(AccountMode.seller), isFalse);
  });
}
