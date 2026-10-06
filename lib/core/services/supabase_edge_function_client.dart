import 'dart:convert';

import 'package:fetch_client/fetch_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Browser-safe Edge Function POSTs for Flutter Web.
///
/// Uses [FetchClient] (CORS `fetch`) and the anon key only so sign-in is not
/// blocked by a stale user JWT on [AuthHttpClient].
abstract final class SupabaseEdgeFunctionClient {
  static FetchClient? _client;

  static Future<({int status, dynamic data})> postJson(
    String functionName, {
    required Map<String, dynamic> body,
  }) async {
    if (!kIsWeb) {
      throw StateError('SupabaseEdgeFunctionClient is only for Flutter Web.');
    }

    final base = dotenv.env['SUPABASE_URL']?.trim().replaceAll(RegExp(r'/$'), '');
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']?.trim();
    if (base == null ||
        base.isEmpty ||
        anonKey == null ||
        anonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be set in .env for web.',
      );
    }

    final uri = Uri.parse('$base/functions/v1/$functionName');
    _client ??= FetchClient(mode: RequestMode.cors);

    final response = await _client!.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
      body: jsonEncode(body),
    );

    final raw = response.body;
    if (raw.isEmpty) {
      return (status: response.statusCode, data: null);
    }

    try {
      return (status: response.statusCode, data: jsonDecode(raw));
    } catch (_) {
      return (status: response.statusCode, data: raw);
    }
  }
}
