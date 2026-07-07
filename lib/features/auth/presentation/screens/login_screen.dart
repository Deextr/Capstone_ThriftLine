import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/validators.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final error = await auth.login(
      username: _usernameController.text,
      password: _passwordController.text,
    );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    context.go(auth.homeRoute);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  Center(
                    child: Image.asset(
                      'assets/images/thriftline-app-icon.png',
                      height: 100,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Thriftline',
                    style: AppTypography.display,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Buy and sell pre-loved fashion',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  ThriftTextField(
                    label: 'Username',
                    hint: 'e.g. maya_buys',
                    controller: _usernameController,
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                  ThriftTextField(
                    label: 'Password',
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    icon: Icons.lock_outline,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  if (_usernameController.text.isNotEmpty ||
                      _passwordController.text.isNotEmpty) ...[
                    if (Validators.username(_usernameController.text) != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          Validators.username(_usernameController.text)!,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 32),
                  ThriftButton(
                    label: 'Login',
                    onPressed: auth.isLoading ? null : _login,
                    isLoading: auth.isLoading,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: AppTypography.body,
                      ),
                      GestureDetector(
                        onTap: () => context.go(RouteNames.signup),
                        child: Text(
                          'Sign up',
                          style: AppTypography.body.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _DemoAccounts(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoAccounts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ThriftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Demo Accounts', style: AppTypography.subheading),
          const SizedBox(height: 8),
          _tile(context, 'maya_buys / buyer123', 'Buyer'),
          _tile(context, 'james_thrift / buyer456', 'Buyer'),
          _tile(context, 'vintagevibes_ph / seller123', 'Seller'),
          _tile(context, 'thrift_trendy / seller456', 'Seller'),
          _tile(context, 'preloved_gems / seller789', 'Seller'),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String creds, String role) {
    final parts = creds.split(' / ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(creds, style: AppTypography.caption),
      subtitle: Text(
        role,
        style: AppTypography.caption.copyWith(color: AppColors.primary),
      ),
      trailing: const Icon(Icons.login, size: 16),
      onTap: () {
        final state = context.findAncestorStateOfType<_LoginScreenState>();
        state?._usernameController.text = parts[0];
        state?._passwordController.text = parts[1];
      },
    );
  }
}
