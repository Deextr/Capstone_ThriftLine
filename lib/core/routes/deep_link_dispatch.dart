import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../../features/auth/data/password_recovery_link.dart';
import '../../features/buyer/data/paymongo_return_link.dart';
import 'password_recovery_coordinator.dart';
import 'paymongo_return_coordinator.dart';

/// True when Supabase Flutter should exchange this URI for a session (OAuth,
/// etc.). Recovery and PayMongo returns are handled by dedicated coordinators.
bool isSupabaseAuthDeepLink(Uri uri) {
  if (PasswordRecoveryLink.isRecoveryUri(uri)) return false;
  if (PaymongoReturnLink.tryParse(uri) != null) return false;

  final fragmentParameters = Uri.splitQueryString(uri.fragment);
  bool hasParameter(String key) =>
      uri.queryParameters.containsKey(key) ||
      fragmentParameters.containsKey(key);

  return hasParameter('access_token') ||
      hasParameter('code') ||
      hasParameter('error') ||
      hasParameter('error_code') ||
      hasParameter('error_description');
}

/// Routes cold-start and warm deep links. [AppLinks.getInitialLink] must run
/// only once per process; PayMongo and recovery previously raced and dropped
/// password-reset links on cold start.
Future<void> attachAppDeepLinks({
  required PaymongoReturnCoordinator paymongoReturn,
  required PasswordRecoveryCoordinator passwordRecovery,
}) async {
  final appLinks = AppLinks();

  Future<void> dispatch(Uri? uri) async {
    if (uri == null) return;
    debugPrint(
      'App deep link received: scheme=${uri.scheme} host=${uri.host} '
      'recovery=${PasswordRecoveryLink.isRecoveryUri(uri)} '
      'token_hash=${uri.queryParameters.containsKey('token_hash')} '
      'paymongo=${PaymongoReturnLink.tryParse(uri) != null}',
    );
    if (PaymongoReturnLink.tryParse(uri) != null) {
      paymongoReturn.accept(uri);
      return;
    }
    if (PasswordRecoveryLink.isRecoveryUri(uri) ||
        PasswordRecoveryLink.hasRecoveryCallbackParams(uri)) {
      await passwordRecovery.accept(uri);
    }
  }

  try {
    await dispatch(await appLinks.getInitialLink());
  } catch (e) {
    debugPrint('App deep link initial URI error: $e');
  }

  appLinks.uriLinkStream.listen(
    (uri) => unawaited(dispatch(uri)),
    onError: (Object e) {
      debugPrint('App deep link stream error: $e');
    },
  );
}
