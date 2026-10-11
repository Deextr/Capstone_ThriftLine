import 'dart:convert';

import 'package:fetch_client/fetch_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Flutter asset written by `scripts/sync_admin_web_config.ps1`.
const adminWebConfigAsset = 'assets/config/admin_config.json';

/// Site-root copy served by Cloudflare Pages.
const adminWebConfigFileName = 'admin_config.json';

/// Absolute URL for the admin web config file at the site root.
@visibleForTesting
Uri adminConfigUri([Uri? pageUri]) {
  final base = pageUri ?? Uri.base;
  final origin = base.origin;
  if (origin.isEmpty || origin == 'null') {
    return Uri.parse('/$adminWebConfigFileName');
  }
  return Uri.parse('$origin/$adminWebConfigFileName');
}

/// Loads admin portal public config.
///
/// On web, never load `.env` from the asset bundle. Cloudflare Pages rewrites
/// missing `/assets/.env` to `index.html`, which leaves SUPABASE_URL empty.
Future<void> loadAdminDotEnv() async {
  if (kIsWeb) {
    await _loadFromSiteRoot();
    _ensureReady();
    return;
  }

  if (await _tryLoadFromAssetBundle()) {
    _ensureReady();
    return;
  }

  await dotenv.load(fileName: '.env');
  _ensureReady();
}

Future<void> _loadFromSiteRoot() async {
  final uri = adminConfigUri();
  final client = FetchClient(mode: RequestMode.cors);
  try {
    final response = await client.get(uri).timeout(const Duration(seconds: 10));
    final raw = response.body.trimLeft();
    if (response.statusCode != 200 || !raw.startsWith('{')) {
      throw StateError(
        'Could not load $adminWebConfigFileName from ${uri.toString()} '
        '(HTTP ${response.statusCode}).',
      );
    }
    _applyJson(raw);
  } finally {
    client.close();
  }
}

Future<bool> _tryLoadFromAssetBundle() async {
  try {
    final raw = await rootBundle.loadString(adminWebConfigAsset);
    if (!raw.trimLeft().startsWith('{')) return false;
    _applyJson(raw);
    return true;
  } on Object {
    return false;
  }
}

void _applyJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw StateError('$adminWebConfigFileName must be a JSON object.');
  }
  final values = <String, String>{
    for (final entry in decoded.entries)
      entry.key.toString(): entry.value?.toString() ?? '',
  };
  if ((values['SUPABASE_URL'] ?? '').isEmpty ||
      (values['SUPABASE_ANON_KEY'] ?? '').isEmpty) {
    throw StateError(
      '$adminWebConfigFileName is missing SUPABASE_URL or SUPABASE_ANON_KEY.',
    );
  }

  // Single-quoted values skip flutter_dotenv `$` interpolation.
  final buffer = StringBuffer();
  for (final entry in values.entries) {
    final escaped = entry.value.replaceAll("'", r"\'");
    buffer.writeln("${entry.key}='$escaped'");
  }
  dotenv.testLoad(fileInput: buffer.toString());
}

void _ensureReady() {
  if (!dotenv.isInitialized ||
      (dotenv.env['SUPABASE_URL'] ?? '').isEmpty ||
      (dotenv.env['SUPABASE_ANON_KEY'] ?? '').isEmpty) {
    throw StateError(
      'Admin config loaded without SUPABASE_URL / SUPABASE_ANON_KEY.',
    );
  }
}
