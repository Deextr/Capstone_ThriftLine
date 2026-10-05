import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/utils/ph_phone.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../widgets/account_phone_verification_section.dart';

/// Full-screen phone verification (e.g. before placing a bid).
/// Uses the same section as Edit Profile for validation, errors, and OTP UX.
class VerifyPhoneScreen extends StatefulWidget {
  const VerifyPhoneScreen({super.key});

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  late final TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    final raw = context.read<AuthProvider>().user?.phone;
    final normalized = normalizePhMobile(raw) ?? '';
    _phoneCtrl = TextEditingController(text: normalized);
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _onVerified() {
    if (!mounted) return;
    showThriftSnackBar(context, 'Phone number verified.');
    final returnProduct = GoRouterState.of(
      context,
    ).uri.queryParameters['returnBidProduct'];
    if (returnProduct != null && returnProduct.isNotEmpty) {
      context.go(RouteNames.productFor(returnProduct));
      return;
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Phone number'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingMd,
              AppConstants.spacingSm,
              AppConstants.spacingMd,
              AppConstants.spacingLg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.smartphone_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingMd),
                Text('Verify your phone number', style: AppTypography.heading),
                const SizedBox(height: 6),
                Text(
                  'Verify your mobile number to place bids. '
                  'This uses the same SMS verification as Edit Profile.',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingLg),
                AccountPhoneVerificationSection(
                  phoneController: _phoneCtrl,
                  onVerified: _onVerified,
                  sendOtpButtonLabel: 'Verify',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
