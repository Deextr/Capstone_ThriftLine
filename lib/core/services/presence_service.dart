import 'package:flutter/foundation.dart';

import '../services/supabase_service.dart';

/// Best-effort presence ping. Supabase Auth has no live "who is online" API.
///
/// Each signed-in client calls [touch] on session start, resume, and a slow
/// timer. The SQL function writes `users.last_active_at` at most once a minute.
/// The Admin Dashboard counts users whose stamp is within 15 minutes.
class PresenceService {
  PresenceService(this._supabase);

  final SupabaseService _supabase;
  DateTime? _lastAttempt;

  Future<void> touch() async {
    if (_supabase.currentUser == null) return;
    final now = DateTime.now();
    final last = _lastAttempt;
    if (last != null && now.difference(last) < const Duration(seconds: 45)) {
      return;
    }
    _lastAttempt = now;
    try {
      await _supabase.client.rpc('touch_last_active');
    } catch (e) {
      debugPrint('PresenceService.touch error: $e');
    }
  }
}
