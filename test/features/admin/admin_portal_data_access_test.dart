import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thriftline/features/admin/data/admin_portal_data_access.dart';

void main() {
  group('adminPortalAccessUserMessage', () {
    test('surfaces PostgREST embed errors', () {
      final message = adminPortalAccessUserMessage(
        const PostgrestException(
          message:
              'Could not embed because more than one relationship was found for admin_order_sla_flags',
          code: 'PGRST201',
        ),
      );
      expect(message.toLowerCase(), contains('admin orders database view'));
    });

    test('maps access exceptions directly', () {
      expect(
        adminPortalAccessUserMessage(
          AdminPortalAccessException('Sign in to the admin portal.'),
        ),
        'Sign in to the admin portal.',
      );
    });
  });
}
