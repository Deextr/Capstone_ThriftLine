import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/davao_barangay.dart';

typedef BarangayFetcher = Future<String> Function(Uri uri);

/// Loads official Davao City barangays from a local snapshot first, then
/// refreshes from the public PSGC API in the background.
///
/// City of Davao is `112402000`. Results are filtered so other cities cannot
/// appear even if the payload is mixed. No API key is required.
class DavaoBarangayService {
  DavaoBarangayService({
    BarangayFetcher? fetch,
    this.timeout = const Duration(seconds: 5),
  }) : _customFetch = fetch != null,
       _fetch = fetch ?? ((uri) => _defaultFetch(uri, timeout));

  static final Uri endpoint = Uri.parse(
    'https://psgc.gitlab.io/api/cities/112402000/barangays.json',
  );

  static const bundledAsset = 'assets/data/davao_barangays.json';
  static const _diskKey = 'davao_barangays_json_v1';
  static const _diskAtKey = 'davao_barangays_fetched_at_v1';
  static const _freshFor = Duration(days: 7);

  static List<DavaoBarangay>? _memory;
  static Future<List<DavaoBarangay>>? _inflight;
  static DateTime? _fetchedAt;

  final BarangayFetcher _fetch;
  final Duration timeout;
  final bool _customFetch;

  /// Warm the shared cache so the address form can open without waiting on
  /// psgc.gitlab.io (that host is often several seconds from the Philippines).
  static Future<void> prefetch() async {
    try {
      await DavaoBarangayService().load();
    } catch (_) {}
  }

  @visibleForTesting
  static void resetCacheForTest() {
    _memory = null;
    _inflight = null;
    _fetchedAt = null;
  }

  Future<List<DavaoBarangay>> load({bool forceRefresh = false}) async {
    if (!forceRefresh && _memory != null && _memory!.isNotEmpty) {
      if (!_customFetch) unawaited(_refreshIfStale());
      return _memory!;
    }

    if (!forceRefresh && !_customFetch) {
      final disk = await _readDisk();
      if (disk != null && disk.isNotEmpty) {
        _memory = disk;
        unawaited(_refreshIfStale());
        return disk;
      }
      final bundled = await _readBundled();
      if (bundled != null && bundled.isNotEmpty) {
        _memory = bundled;
        unawaited(_refreshIfStale(force: true));
        return bundled;
      }
    }

    if (forceRefresh) {
      try {
        return await _fetchShared();
      } on DavaoBarangayException {
        if (_memory != null && _memory!.isNotEmpty) return _memory!;
        rethrow;
      }
    }

    return _fetchShared();
  }

  Future<List<DavaoBarangay>> _fetchShared() {
    final existing = _inflight;
    if (existing != null) return existing;
    final future = _fetchAndStore();
    _inflight = future;
    return future.whenComplete(() {
      if (identical(_inflight, future)) _inflight = null;
    });
  }

  Future<void> _refreshIfStale({bool force = false}) async {
    final fetchedAt = _fetchedAt;
    if (!force &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _freshFor) {
      return;
    }
    try {
      await _fetchShared();
    } catch (_) {}
  }

  Future<List<DavaoBarangay>> _fetchAndStore() async {
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

    _memory = barangays;
    _fetchedAt = DateTime.now();
    if (!_customFetch) unawaited(_writeDisk(body));
    return barangays;
  }

  static Future<List<DavaoBarangay>?> _readDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_diskKey);
      if (raw == null || raw.isEmpty) return null;
      final atMs = prefs.getInt(_diskAtKey);
      if (atMs != null) {
        _fetchedAt = DateTime.fromMillisecondsSinceEpoch(atMs);
      }
      return DavaoBarangay.fromApiList(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeDisk(String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_diskKey, body);
      await prefs.setInt(_diskAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<DavaoBarangay>?> _readBundled() async {
    try {
      final raw = await rootBundle.loadString(bundledAsset);
      return DavaoBarangay.fromApiList(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<String> _defaultFetch(Uri uri, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const DavaoBarangayException(DavaoBarangayErrorKind.network);
      }
      return await response.transform(utf8.decoder).join().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}
