import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/services/supabase_service.dart';
import 'package:thriftline/features/auth/domain/auth_user.dart';
import 'package:thriftline/features/trust_safety/controllers/report_user_controller.dart';
import 'package:thriftline/models/enums.dart';
import 'package:thriftline/providers/auth_provider.dart';
import 'package:thriftline/providers/following_shops_provider.dart';

class _FakeAuth extends Fake with ChangeNotifier implements AuthProvider {
  @override
  AuthUser? get user => const AuthUser(
    id: 'buyer-1',
    username: 'buyer',
    name: 'Buyer',
    email: 'buyer@test.com',
    phone: '',
    isPhoneVerified: false,
    role: UserRole.buyer,
    avatarUrl: '',
    location: '',
  );
}

class _ControllableFollowingShops extends FollowingShopsProvider {
  _ControllableFollowingShops() : super(SupabaseService());

  bool manualLoading = false;
  String? manualError;
  final _refreshGate = Completer<void>()..complete();

  @override
  bool get isLoading => manualLoading;

  @override
  String? get errorMessage => manualError;

  @override
  Future<void> refresh() async {
    manualLoading = true;
    manualError = null;
    notifyListeners();
    await _refreshGate.future;
    manualLoading = false;
    notifyListeners();
  }

  void completeRefresh() {
    if (!_refreshGate.isCompleted) {
      _refreshGate.complete();
    }
  }
}

void main() {
  group('ReportUserController followed shops', () {
    test('notifies when FollowingShopsProvider updates after load', () async {
      final following = _ControllableFollowingShops();
      final controller = ReportUserController(
        supabase: SupabaseService(),
        auth: _FakeAuth(),
        followingShops: following,
      );
      await Future<void>.delayed(Duration.zero);

      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      following.notifyListeners();
      expect(notifyCount, 1);
      expect(controller.isLoadingFollowedShops, isFalse);

      controller.dispose();
    });

    test('load completes and clears initial loading flag', () async {
      final following = _ControllableFollowingShops();
      final controller = ReportUserController(
        supabase: SupabaseService(),
        auth: _FakeAuth(),
        followingShops: following,
      );

      await Future<void>.delayed(Duration.zero);
      expect(controller.isLoading, isFalse);

      controller.dispose();
    });
  });
}
