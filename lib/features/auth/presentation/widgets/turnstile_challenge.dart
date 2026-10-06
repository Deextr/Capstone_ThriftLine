import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../config/turnstile_config.dart';
import 'turnstile_messages.dart';

enum TurnstileChallengeAppearance { darkOverlay, lightSurface }

/// Cloudflare Turnstile challenge for auth flows (login, password reset).
class TurnstileChallenge extends StatefulWidget {
  const TurnstileChallenge({
    super.key,
    required this.action,
    required this.onToken,
    required this.onError,
    this.onExpired,
    this.appearance = TurnstileChallengeAppearance.darkOverlay,
    this.showSuccessMessage = true,
    this.showLoadingMessage = true,
  });

  final String action;
  final ValueChanged<String> onToken;
  final void Function(TurnstileException error) onError;
  final VoidCallback? onExpired;
  final TurnstileChallengeAppearance appearance;

  /// When false, rely on the Turnstile widget's built-in success state (e.g. admin web login).
  final bool showSuccessMessage;

  /// When false, rely on the Turnstile widget's built-in loading UI (e.g. admin web login).
  final bool showLoadingMessage;

  @override
  State<TurnstileChallenge> createState() => TurnstileChallengeState();
}

class TurnstileChallengeState extends State<TurnstileChallenge> {
  TurnstileController? _controller;
  String? _loadError;
  String? _loadErrorDetail;
  bool _loading = true;
  bool _solved = false;
  int _mountGeneration = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> reset() async {
    _controller?.token = null;
    if (_controller?.isWidgetReady == true) {
      await _controller?.refreshToken();
    }
    if (mounted) {
      setState(() {
        _solved = false;
        _loadError = null;
        _loadErrorDetail = null;
        _loading = true;
      });
    }
  }

  void _retry() {
    _controller?.dispose();
    setState(() {
      _mountGeneration++;
      _controller = TurnstileController();
      _loadError = null;
      _loadErrorDetail = null;
      _loading = true;
      _solved = false;
    });
  }

  void _handleError(TurnstileException error) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = turnstileUserFacingMessage(error);
      _loadErrorDetail = error.code > 0 ? 'Code ${error.code}' : null;
    });
    widget.onError(error);
  }

  void _handleToken(String token) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _solved = true;
      _loadError = null;
    });
    widget.onToken(token);
  }

  @override
  Widget build(BuildContext context) {
    if (!TurnstileConfig.isConfigured) {
      return _MessageBox(
        appearance: widget.appearance,
        icon: Icons.warning_amber_rounded,
        message:
            'Human verification is not configured. '
            'Add TURNSTILE_SITE_KEY to your environment.',
      );
    }

    if (_loadError != null) {
      return _MessageBox(
        appearance: widget.appearance,
        icon: Icons.verified_user_outlined,
        message: _loadError!,
        detail: _loadErrorDetail,
        actionLabel: 'Try again',
        onAction: _retry,
      );
    }

    _controller ??= TurnstileController();

    final isLight = widget.appearance == TurnstileChallengeAppearance.lightSurface;
    final captionColor = isLight
        ? AppColors.textSecondary
        : Colors.white.withValues(alpha: 0.72);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showLoadingMessage && _loading && !_solved)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isLight ? AppColors.primary : Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Loading verification…',
                  style: AppTypography.caption.copyWith(color: captionColor),
                ),
              ],
            ),
          ),
        if (widget.showSuccessMessage && _solved)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Text(
                  'Verification complete',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: Center(
            child: SizedBox(
              width: TurnstileSize.normal.width,
              height: TurnstileSize.normal.height,
              child: CloudflareTurnstile(
                key: ValueKey('turnstile_$_mountGeneration'),
                siteKey: TurnstileConfig.siteKey,
                baseUrl: TurnstileConfig.baseUrl,
                action: widget.action,
                controller: _controller,
                options: TurnstileOptions(
                  size: TurnstileSize.normal,
                  theme: TurnstileTheme.light,
                  retryAutomatically: true,
                ),
                onTokenReceived: _handleToken,
                onError: _handleError,
                onTokenExpired: () {
                  if (!mounted) return;
                  setState(() => _solved = false);
                  widget.onExpired?.call();
                },
                onTimeout: () {
                  if (!mounted) return;
                  setState(() {
                    _loading = false;
                    _loadError = turnstileLoadTimeoutMessage();
                  });
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Protected by Cloudflare',
          style: AppTypography.caption.copyWith(color: captionColor),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({
    required this.appearance,
    required this.icon,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final TurnstileChallengeAppearance appearance;
  final IconData icon;
  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isLight = appearance == TurnstileChallengeAppearance.lightSurface;
    final fg = isLight ? AppColors.textPrimary : Colors.white;
    final iconColor = isLight ? AppColors.error : Colors.white;
    final bg = isLight
        ? AppColors.error.withValues(alpha: 0.06)
        : AppColors.error.withValues(alpha: 0.12);
    final border = isLight
        ? AppColors.error.withValues(alpha: 0.25)
        : AppColors.error.withValues(alpha: 0.35);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: AppTypography.caption.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ),
          ],
        ],
      ),
    );
  }
}
