import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/davao_barangay.dart';

typedef BarangayFetcher = Future<String> Function(Uri uri);

/// Loads official Davao City barangays from the public PSGC API.
///
/// The request is scoped to City of Davao (`112402000`). Results are filtered
/// again so barangays from other cities cannot appear even if the payload
/// is mixed. No API key is required.
class DavaoBarangayService {
  DavaoBarangayService({
    BarangayFetcher? fetch,
    Duration timeout = const Duration(seconds: 12),
  })  : timeout = timeout,
        _fetch = fetch ?? ((uri) => _defaultFetch(uri, timeout));

  static final Uri endpoint = Uri.parse(
    'https://psgc.gitlab.io/api/cities/112402000/barangays.json',
  );

  final BarangayFetcher _fetch;
  final Duration timeout;

  List<DavaoBarangay>? _cache;

  Future<List<DavaoBarangay>> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null && _cache!.isNotEmpty) {
      return _cache!;
    }

    late final String body;
    try {
      body = await _fetch(endpoint).timeout(timeout);
    } on TimeoutException {
      throw const DavaoBarangayException(DavaoBarangayErrorKind.timeout);
    } on DavaoBarangayException {
      rethrow;
    } on SocketException {
      throw const DavaoBarangayException(DavaoBarangayErrorKind.network);
    } on HttpException {
      throw const DavaoBarangayException(DavaoBarangayErrorKind.network);
    } catch (_) {
      throw const DavaoBarangayException(DavaoBarangayErrorKind.network);
    }

    late final Object decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const DavaoBarangayException(DavaoBarangayErrorKind.invalid);
    }

    late final List<DavaoBarangay> barangays;
    try {
      barangays = DavaoBarangay.fromApiList(decoded);
    } on FormatException {
      throw const DavaoBarangayException(DavaoBarangayErrorKind.invalid);
    }

    if (barangays.isEmpty) {
      throw const DavaoBarangayException(DavaoBarangayErrorKind.empty);
    }

    _cache = barangays;
    return barangays;
  }

  static Future<String> _defaultFetch(Uri uri, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const DavaoBarangayException(DavaoBarangayErrorKind.network);
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}
