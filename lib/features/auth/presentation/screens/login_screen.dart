import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/validators.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../domain/legal_documents.dart';
import '../widgets/auth_branding.dart';
import '../widgets/legal_consent_notice.dart';
import '../widgets/login_video_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final error = await auth.loginWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      consent: LegalConsent.now(),
    );
    if (!mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    context.go(auth.homeRoute);
  }

  Future<void> _loginWithGoogle() async {
    final auth = context.read<AuthProvider>();
    final error = await auth.loginWithGoogle(consent: LegalConsent.now());
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
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compact = screenHeight < 700;
    const fieldLabelColor = Colors.white;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.primaryDark,
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const LoginVideoBackground(),
            const AuthVideoScrim(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      AppConstants.spacingLg,
                      compact ? AppConstants.spacingMd : AppConstants.spacingXl,
                      AppConstants.spacingLg,
                      AppConstants.spacingLg,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight -
                            (compact
                                ? AppConstants.spacingMd
                                : AppConstants.spacingXl) -
                            AppConstants.spacingLg,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Center(
                              child: AuthBrandLogo(size: compact ? 84 : 100),
                            ),
                            SizedBox(height: compact ? 16 : 24),
                            Text(
                              'ThriftLine',
                              style: AppTypography.display.copyWith(
                                color: Colors.white,
                                letterSpacing: -0.4,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x66000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Welcome back',
                              style: AppTypography.heading.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Buy and sell pre-loved fashion',
                              style: AppTypography.body.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: compact ? 28 : 40),
                            ThriftTextField(
                              label: 'Email',
                              hint: 'your@email.com',
                              controller: _emailController,
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: Validators.email,
                              labelColor: fieldLabelColor,
                            ),
                            const SizedBox(height: 16),
                            ThriftTextField(
                              label: 'Password',
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              icon: Icons.lock_outline,
                              validator: Validators.password,
                              labelColor: fieldLabelColor,
                              suffix: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 20 : 24),
                            ThriftButton(
                              label: 'Login',
                              onPressed:
                                  auth.isLoading ? null : _loginWithEmail,
                              isLoading: auth.isLoading,
                            ),
                            SizedBox(height: compact ? 16 : 24),
                            const _OrDivider(),
                            SizedBox(height: compact ? 16 : 24),
                            _GoogleSignInButton(
                              onPressed:
                                  auth.isLoading ? null : _loginWithGoogle,
                              isLoading: auth.isLoading,
                            ),
                            SizedBox(height: compact ? 20 : 24),
                            const LegalConsentNotice(),
                            const SizedBox(height: 20),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account? ",
                                  style: AppTypography.body.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => context.go(RouteNames.signup),
                                  child: Text(
                                    'Sign up',
                                    style: AppTypography.body.copyWith(
                                      color: AppColors.primaryLight,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final line = Colors.white.withValues(alpha: 0.28);
    return Row(
      children: [
        Expanded(child: Divider(color: line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'or',
            style: AppTypography.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ),
        Expanded(child: Divider(color: line)),
      ],
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({this.onPressed, this.isLoading = false});

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.42)),
          backgroundColor: Colors.white.withValues(alpha: 0.10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SvgPicture.asset(
                      'assets/images/google_g.svg',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Continue with Google',
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
