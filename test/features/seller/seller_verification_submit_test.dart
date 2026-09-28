import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:thriftline/features/seller/data/seller_verification_service.dart';

void main() {
  test('null government_id_number is not reported as a connection error', () {
    const error = PostgrestException(
      message: 'null value in column "government_id_number" violates not-null constraint',
      code: '23502',
    );
    expect(
      sellerSubmitUserMessage(error),
      'The application is missing a required field. Please try again.',
    );
  });

  test('row-level security is not reported as a connection error', () {
    const error = PostgrestException(
      message: 'new row violates row-level security policy for table "notifications"',
      code: '42501',
    );
    expect(
      sellerSubmitUserMessage(error),
      'Could not save the application. Please sign in again and retry.',
    );
  });

  test('unwraps SellerSubmitException', () {
    final error = SellerSubmitException(
      sellerSubmitUserMessage(
        const PostgrestException(message: 'duplicate key', code: '23505'),
      ),
    );
    expect(sellerSubmitUserMessage(error), 'You already have an application under review.');
  });
}
