import 'package:flutter/foundation.dart';

import '../../../core/services/supabase_service.dart';
import '../data/looking_for_moderation.dart';

class AdminDisabledAccountsController extends ChangeNotifier {
  AdminDisabledAccountsController({required SupabaseService supabase})
    : _service = LookingForModerationService(supabase) {
    load();
  }

  final LookingForModerationService _service;

  List<DisabledAccountRecord> _accounts = const [];
  final Map<String, List<LookingForViolationRecord>> _history = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _openUserId;

  List<DisabledAccountRecord> get accounts => _accounts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get openUserId => _openUserId;

  List<LookingForViolationRecord> historyFor(String userId) =>
      _history[userId] ?? const [];

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _accounts = await _service.listDisabledAccounts();
      _history.clear();
    } catch (e) {
      debugPrint('AdminDisabledAccountsController.load error: $e');
      _accounts = const [];
      _errorMessage = 'Unable to load disabled accounts.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> toggle(String userId) async {
    if (_openUserId == userId) {
      _openUserId = null;
      notifyListeners();
      return;
    }
    _openUserId = userId;
    notifyListeners();
    if (_history.containsKey(userId)) return;
    try {
      _history[userId] = await _service.violationsFor(userId);
    } catch (e) {
      debugPrint('AdminDisabledAccountsController.history error: $e');
      _history[userId] = const [];
    }
    notifyListeners();
  }
}
