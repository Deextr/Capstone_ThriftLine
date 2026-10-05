import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/ph_smart_tnt_prefixes.dart';

void main() {
  group('Smart/TNT prefix pre-check', () {
    test('blocks known Smart/TNT prefixes after valid format', () {
      expect(
        smartTntPrefixOtpBlockMessage('09081234567'),
        kSmartTntPrefixUnavailableMessage,
      );
      expect(
        smartTntPrefixOtpBlockMessage('09981234567'),
        kSmartTntPrefixUnavailableMessage,
      );
    });

    test('allows non-Smart/TNT prefixes', () {
      expect(smartTntPrefixOtpBlockMessage('09171234567'), isNull);
      expect(smartTntPrefixOtpBlockMessage('09221234567'), isNull);
    });

    test('does not block invalid format (format validator handles first)', () {
      expect(smartTntPrefixOtpBlockMessage('12093129032193'), isNull);
      expect(smartTntPrefixOtpBlockMessage('0917123456'), isNull);
    });
  });
}
