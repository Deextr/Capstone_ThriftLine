import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/utils/formatters.dart';
import 'package:thriftline/core/utils/supabase_rpc.dart';

void main() {
  group('formatCountdown', () {
    test('returns Ended for zero or negative remaining time', () {
      expect(formatCountdown(Duration.zero), 'Ended');
      expect(formatCountdown(const Duration(seconds: -12)), 'Ended');
    });

    test('formats hours and minutes for a live auction', () {
      expect(formatCountdown(const Duration(hours: 2, minutes: 5)), '02:05');
    });
  });

  group('formatReadableCountdown', () {
    test('uses labeled hours and minutes', () {
      expect(
        formatReadableCountdown(const Duration(hours: 21, minutes: 22)),
        '21h 22m',
      );
    });

    test('uses minutes only under one hour', () {
      expect(formatReadableCountdown(const Duration(minutes: 22)), '22m');
    });
  });

  group('supabaseRpcMap', () {
    test('reads success and error from a JSONB RPC result', () {
      expect(supabaseRpcSuccess({'success': true, 'bid_id': '1'}), isTrue);
      expect(
        supabaseRpcError({'success': false, 'error': 'Auction not found.'}),
        'Auction not found.',
      );
      expect(supabaseRpcSuccess('nope'), isFalse);
    });
  });
}
