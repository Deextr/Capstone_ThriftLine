import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../config/turnstile_config.dart';

/// Cloudflare Turnstile challenge for auth flows (login, password reset).
class TurnstileChallenge extends StatefulWidget {
  const TurnstileChallenge({
    super.key,
    required this.action,
    required this.onToken,
    required this.onError,
    this.onExpired,
  });

  final String action;
  final ValueChanged<String> onToken;
  final void Function(TurnstileException error) onError;
  final VoidCallback? onExpired;

  @override
  State<TurnstileChallenge> createState() => TurnstileChallengeState();
}

class TurnstileChallengeState extends State<TurnstileChallenge> {
  final TurnstileController _controller = TurnstileController();
  String? _loadError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> reset() async {
    _controller.token = null;
    if (_controller.isWidgetReady) {
      await _controller.refreshToken();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!TurnstileConfig.isConfigured) {
      return _MessageBox(
        icon: Icons.warning_amber_rounded,
        message:
            'Human verification is not configured. '
            'Add TURNSTILE_SITE_KEY to your environment.',
      );
    }

    if (_loadError != null) {
      return _MessageBox(
        icon: Icons.cloud_off_outlined,
        message: _loadError!,
        actionLabel: 'Retry',
        onAction: () => setState(() => _loadError = null),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: Center(
            child: SizedBox(
              width: TurnstileSize.normal.width,
              height: TurnstileSize.normal.height,
              child: CloudflareTurnstile(
              siteKey: TurnstileConfig.siteKey,
              baseUrl: TurnstileConfig.baseUrl,
              action: widget.action,
              controller: _controller,
              options: TurnstileOptions(
                size: TurnstileSize.normal,
                theme: TurnstileTheme.light,
                retryAutomatically: true,
              ),
              onTokenReceived: (token) {
                if (!mounted) return;
                widget.onToken(token);
              },
              onError: (error) {
                if (!mounted) return;
                setState(() {
                  _loadError =
                      'Verification could not load. Check your connection '
                      'and try again.';
                });
                widget.onError(error);
              },
              onTokenExpired: () {
                widget.onExpired?.call();
              },
            ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Protected by Cloudflare',
          style: AppTypography.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.72),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: AppTypography.caption.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
