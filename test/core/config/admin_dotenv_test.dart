import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/config/admin_dotenv.dart';

void main() {
  test('admin config URL is always at the site root', () {
    expect(
      adminConfigUri(Uri.parse('https://thriftline-admin.pages.dev/admin/login')),
      Uri.parse('https://thriftline-admin.pages.dev/admin_config.json'),
    );
    expect(
      adminConfigUri(Uri.parse('https://thriftline-admin.pages.dev/')),
      Uri.parse('https://thriftline-admin.pages.dev/admin_config.json'),
    );
  });
}
