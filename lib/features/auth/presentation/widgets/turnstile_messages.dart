import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';

import '../../config/turnstile_config.dart';

/// Maps Cloudflare client errors to user-facing copy (not generic "check wifi").
String turnstileUserFacingMessage(
  TurnstileException error, {
  bool includeHostnameHint = true,
}) {
  switch (error.errorType) {
    case TurnstileError.UNKNOWN_DOMAIN:
      final host = TurnstileConfig.pageHostname;
      if (includeHostnameHint && host.isNotEmpty) {
        return 'This site ($host) is not allowed for Turnstile. '
            'Add it under Hostname management in your Cloudflare Turnstile widget.';
      }
      return 'This website is not allowed for Turnstile. '
          'Check hostname settings in the Cloudflare dashboard.';
    case TurnstileError.INVALID_SITEKEY:
      return 'Turnstile site key is invalid or inactive. '
          'Check TURNSTILE_SITE_KEY in your environment.';
    case TurnstileError.INVALID_ACTION:
      return 'Turnstile action mismatch. Contact support if this continues.';
    case TurnstileError.INITIALIZATION_PROBLEM:
      return 'Turnstile could not start on this page. Try again or reload.';
    case TurnstileError.INCORRECT_CONFIGURATION:
      return 'Turnstile is misconfigured. Verify site key and allowed hostnames.';
    case TurnstileError.UNSUPPORTED_BROWSER:
      return 'This browser is not supported for verification. Try Chrome or Edge.';
    case TurnstileError.TIME_PROBLEM:
      return 'Your device clock may be incorrect. Fix the date and time, then retry.';
    case TurnstileError.CHALLANGE_TIMED_OUT:
    case TurnstileError.CHALLANGE_TIMED_OUT_VISIBLE:
      return 'Verification timed out. Try again.';
    default:
      if (error.message.trim().isNotEmpty &&
          error.message.toLowerCase() != 'unknown error') {
        return error.message;
      }
      return 'Verification could not complete. Try again.';
  }
}

String turnstileLoadTimeoutMessage() {
  return 'Verification is taking longer than expected. '
      'Check that challenges.cloudflare.com is reachable, then try again.';
}
