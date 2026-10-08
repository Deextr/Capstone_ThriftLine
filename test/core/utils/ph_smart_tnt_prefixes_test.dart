import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/ph_smart_tnt_prefixes.dart';

void main() {
  group('Smart/TNT prefix pre-check', () {
    test('does not block TM numbers that share a Smart/TNT prefix', () {
      expect(isKnownSmartOrTntPrefix('09081234567'), isTrue);
      expect(smartTntPrefixOtpBlockMessage('09081234567'), isNull);
      expect(smartTntPrefixOtpBlockMessage('09151234567'), isNull);
      expect(smartTntPrefixOtpBlockMessage('09981234567'), isNull);
    });

    test('does not block Globe or other valid mobiles by prefix', () {
      expect(smartTntPrefixOtpBlockMessage('09171234567'), isNull);
      expect(smartTntPrefixOtpBlockMessage('09221234567'), isNull);
    });

    test('keeps carrier notice copy for provider responses', () {
      expect(kSmartTntPrefixUnavailableMessage, contains('Smart'));
    });

    test('does not block invalid format (format validator handles first)', () {
      expect(smartTntPrefixOtpBlockMessage('12093129032193'), isNull);
      expect(smartTntPrefixOtpBlockMessage('0917123456'), isNull);
    });
  });
}
