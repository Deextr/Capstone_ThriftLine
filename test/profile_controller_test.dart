import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/features/profile/controllers/profile_controller.dart';
import 'package:thriftline/core/services/supabase_service.dart';

void main() {
  test('ProfileController username format validation works correctly', () {
    final controller = ProfileController(supabaseService: SupabaseService());

    // Valid usernames (Letters and numbers only, no spaces or special characters)
    expect(controller.isValidUsernameFormat('john123'), true);
    expect(controller.isValidUsernameFormat('JohnSmith'), true);
    expect(controller.isValidUsernameFormat('razel2026'), true);

    // Invalid usernames
    expect(controller.isValidUsernameFormat('john smith'), false);
    expect(controller.isValidUsernameFormat('john_smith'), false);
    expect(controller.isValidUsernameFormat('john-smith'), false);
    expect(controller.isValidUsernameFormat('john@123'), false);
    expect(controller.isValidUsernameFormat(''), false);
  });
}
