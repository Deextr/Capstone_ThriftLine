/// Which client surface initiated email/password sign-in.
enum LoginPortal {
  /// Buyer/seller mobile app.
  app,

  /// Administrator web portal (`main_admin.dart`).
  admin,
}

extension LoginPortalApiValue on LoginPortal {
  String get apiValue => switch (this) {
    LoginPortal.app => 'app',
    LoginPortal.admin => 'admin',
  };
}
