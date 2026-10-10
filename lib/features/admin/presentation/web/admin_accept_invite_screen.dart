import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../data/admin_account_service.dart';
import '../../../../widgets/thrift_widgets.dart';

class AdminAcceptInviteScreen extends StatefulWidget {
  const AdminAcceptInviteScreen({super.key});

  @override
  State<AdminAcceptInviteScreen> createState() =>
      _AdminAcceptInviteScreenState();
}

class _AdminAcceptInviteScreenState extends State<AdminAcceptInviteScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _ready = false;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareSession());
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _prepareSession() async {
    final uri = GoRouterState.of(context).uri;
    final tokenHash = uri.queryParameters['token_hash'];
    final type = uri.queryParameters['type'];
    final client = context.read<SupabaseService>().client;
    _authSub ??= client.auth.onAuthStateChange.listen((event) {
      if (!mounted || event.session == null) return;
      setState(() {
        _ready = true;
        _error = null;
      });
    });
    try {
      if (tokenHash != null && tokenHash.isNotEmpty) {
        await client.auth.verifyOTP(
          tokenHash: tokenHash,
          type: type == 'recovery' ? OtpType.recovery : OtpType.invite,
        );
      }
    } catch (e) {
      debugPrint('AdminAcceptInviteScreen verify failed: $e');
      if (mounted) {
        setState(() {
          _error = 'This invitation link is invalid or has expired.';
          _ready = false;
        });
      }
      return;
    }
    final session = client.auth.currentSession;
    if (!mounted) return;
    setState(() {
      _ready = session != null;
      _error = session == null
          ? 'This invitation link is invalid or has expired.'
          : null;
    });
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final supabase = context.read<SupabaseService>();
    final auth = context.read<AuthProvider>();
    try {
      await supabase.client.auth.updateUser(UserAttributes(password: password));
      final setupError = await AdminAccountService(
        supabase,
      ).completeInvitation();
      if (setupError != null) {
        if (mounted) setState(() => _error = setupError);
        return;
      }
      await auth.reloadUser();
      if (!mounted) return;
      if (!auth.canUseAdminPortal) {
        setState(() {
          _error = 'This administrator account cannot access the portal yet.';
        });
        return;
      }
      context.go(RouteNames.adminDashboard);
    } catch (e) {
      debugPrint('AdminAcceptInviteScreen submit failed: $e');
      if (mounted) {
        setState(() {
          _error =
              'Could not finish account setup. Try the invitation link again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Set up your admin account',
                      style: AppTypography.heading.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Choose a password for the ThriftLine Admin portal.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_error != null) ...[
                      Text(
                        _error!,
                        style: AppTypography.body.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_ready) ...[
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                        ),
                        onSubmitted: (_) => _busy ? null : _submit(),
                      ),
                      const SizedBox(height: 20),
                      ThriftButton(
                        label: _busy ? 'Saving…' : 'Continue',
                        onPressed: _busy ? null : _submit,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
