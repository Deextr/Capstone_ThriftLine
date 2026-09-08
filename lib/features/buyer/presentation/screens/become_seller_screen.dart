import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../features/auth/domain/auth_user.dart';
import '../../../../features/seller/data/davao_barangay_service.dart';
import '../../../../features/seller/data/seller_verification_service.dart';
import '../../../../features/seller/domain/davao_barangay.dart';
import '../../../../features/seller/domain/id_image_quality.dart';
import '../../../../features/seller/domain/seller_address_draft.dart';
import '../../../../features/seller/domain/seller_id_type.dart';
import '../../../../features/seller/presentation/screens/id_capture_screen.dart';
import '../../../../features/seller/presentation/screens/liveness_capture_screen.dart';
import '../../../../features/seller/presentation/widgets/davao_barangay_field.dart';
import '../../../../features/seller/presentation/widgets/id_side_review_card.dart';
import '../../../../features/seller/presentation/widgets/terms_acceptance_note.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class BecomeSellerScreen extends StatefulWidget {
  const BecomeSellerScreen({super.key});

  @override
  State<BecomeSellerScreen> createState() => _BecomeSellerScreenState();
}

class _BecomeSellerScreenState extends State<BecomeSellerScreen> {
  final _storeNameCtrl = TextEditingController();
  final _addressLine1Ctrl = TextEditingController();
  final _addressLine2Ctrl = TextEditingController();
  final _barangayService = DavaoBarangayService();

  List<DavaoBarangay> _barangays = const [];
  DavaoBarangay? _selectedBarangay;
  bool _barangaysLoading = true;
  String? _barangayError;

  Uint8List? _idFrontBytes;
  Uint8List? _idBackBytes;
  IdQualityResult? _frontQuality;
  IdQualityResult? _backQuality;

  bool _selfieUploaded = false;
  bool _submitting = false;
  int _currentStep = 0;
  LivenessResult? _liveness;

  bool get _idGateOpen =>
      _idFrontBytes != null &&
      _idBackBytes != null &&
      IdCapturePair(front: _frontQuality, back: _backQuality).canProceed;

  @override
  void initState() {
    super.initState();
    _loadBarangays();
  }

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _addressLine1Ctrl.dispose();
    _addressLine2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadBarangays({bool forceRefresh = false}) async {
    setState(() {
      _barangaysLoading = true;
      _barangayError = null;
    });
    try {
      final list = await _barangayService.load(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _barangays = list;
        _barangaysLoading = false;
        if (_selectedBarangay != null &&
            !DavaoBarangay.isAllowedSelection(_selectedBarangay, list)) {
          _selectedBarangay = null;
        }
      });
    } on DavaoBarangayException catch (e) {
      if (!mounted) return;
      setState(() {
        _barangays = const [];
        _barangaysLoading = false;
        _barangayError = e.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _barangays = const [];
        _barangaysLoading = false;
        _barangayError =
            'Could not load Davao City barangays. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final status = user?.verificationStatus ?? 'none';

    if (status == 'pending') {
      return _buildPendingScreen(context, user);
    } else if (status == 'rejected') {
      return _buildRejectedScreen(context, user);
    }

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentStep > 0) {
          setState(() => _currentStep--);
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Become a Seller'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (_currentStep > 0) {
                  setState(() => _currentStep--);
                } else {
                  context.pop();
                }
              },
            ),
            elevation: 0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          ),
          body: SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingMd,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _buildSegment(0, 'Seller Info'),
                          const SizedBox(width: 8),
                          _buildSegment(1, 'ID Capture'),
                          const SizedBox(width: 8),
                          _buildSegment(2, 'Selfie'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _getStepTitle(),
                            style: AppTypography.subheading.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                          Text(
                            'Step ${_currentStep + 1} of 3',
                            style: AppTypography.caption,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppConstants.spacingMd),
                    child: _buildStep(),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: _buildBottomActions(auth),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActions(AuthProvider auth) {
    if (_currentStep == 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TermsAcceptanceNote(),
          const SizedBox(height: 12),
          ThriftButton(label: 'Continue', onPressed: _continueFromAddress),
        ],
      );
    }
    if (_currentStep == 1) {
      return ThriftButton(
        label: 'Continue',
        onPressed: _idGateOpen ? _continueFromId : null,
      );
    }
    return ThriftButton(
      label: 'Submit Application',
      isLoading: _submitting,
      onPressed: _submitting ? null : () => _submit(auth),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Seller information & address';
      case 1:
        return 'Capture your ID';
      case 2:
        return 'Take a selfie';
      default:
        return '';
    }
  }

  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return _storeInfoStep();
      case 1:
        return _idCaptureStep();
      case 2:
        return _selfieStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _storeInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThriftTextField(
                label: 'Store Name',
                hint: 'e.g. Vintage Vibes PH',
                controller: _storeNameCtrl,
                icon: Icons.store_outlined,
              ),
              const SizedBox(height: 20),
              DavaoBarangayField(
                barangays: _barangays,
                selected: _selectedBarangay,
                loading: _barangaysLoading,
                error: _barangayError,
                onRetry: () => _loadBarangays(forceRefresh: true),
                onSelected: (barangay) {
                  if (!barangay.isDavaoCity) return;
                  setState(() => _selectedBarangay = barangay);
                },
              ),
              const SizedBox(height: 20),
              ThriftTextField(
                label: 'Address Line 1',
                hint: 'Street, building, or house number',
                controller: _addressLine1Ctrl,
                icon: Icons.location_on_outlined,
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              ThriftTextField(
                label: 'Address Line 2',
                hint: 'Unit / Floor / Building / Landmark',
                controller: _addressLine2Ctrl,
                icon: Icons.apartment_outlined,
                labelSuffix: Text(
                  'Optional',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.stars_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Why sell on Thriftline?',
                    style: AppTypography.subheading.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _benefitRow(
                Icons.trending_up_outlined,
                'Reach thousands of thrift buyers',
              ),
              _benefitRow(
                Icons.auto_awesome_outlined,
                'AI-powered pricing suggestions',
              ),
              _benefitRow(Icons.security_outlined, 'Secure payment processing'),
              _benefitRow(
                Icons.local_shipping_outlined,
                'Integrated shipping options',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _benefitRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }

  Widget _idCaptureStep() {
    final pair = IdCapturePair(front: _frontQuality, back: _backQuality);
    if (_idGateOpen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Both sides of your ID passed the ID check.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          IdSideReviewCard(
            title: 'Front ID',
            bytes: _idFrontBytes,
            quality: _frontQuality,
            checking: false,
          ),
          const SizedBox(height: 16),
          IdSideReviewCard(
            title: 'Back ID',
            bytes: _idBackBytes,
            quality: _backQuality,
            checking: false,
          ),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Retake ID photos',
            variant: ThriftButtonVariant.outline,
            onPressed: _startIdCaptureFlow,
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _idPairStatusMessage(pair),
              style: AppTypography.body.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Use one of the accepted IDs below. You will photograph the front, '
          'then the back.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Text('Accepted IDs', style: AppTypography.subheading),
        const SizedBox(height: 12),
        for (final type in SellerIdType.values) ...[
          _acceptedIdRow(type.label),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        ThriftButton(
          label: 'Proceed to capture',
          onPressed: _startIdCaptureFlow,
        ),
      ],
    );
  }

  Widget _acceptedIdRow(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selfieStep() {
    if (_selfieUploaded) {
      return Column(
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.success,
            size: 56,
          ),
          const SizedBox(height: 16),
          Text(
            'Face check passed',
            style: AppTypography.subheading.copyWith(color: AppColors.success),
          ),
          const SizedBox(height: 8),
          Text(
            'Look left, look right, and a blink were completed. The selfie was captured automatically.',
            style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _startLiveness,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retake face check'),
          ),
        ],
      );
    }

    return Column(
      children: [
        Text(
          'Look at the camera, then look right, look left, and blink. '
          'The selfie is taken automatically once your face is clear and still.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        Icon(
          Icons.account_circle_outlined,
          size: 96,
          color: AppColors.textHint.withValues(alpha: 0.8),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _bannedIcon(Icons.visibility_outlined),
            const SizedBox(width: 20),
            _bannedIcon(Icons.school_outlined),
            const SizedBox(width: 20),
            _bannedIcon(Icons.masks_outlined),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bullet('Look directly at the camera'),
              _bullet('Remove glasses, hats and masks'),
              _bullet('Make sure your face is well-lit'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ThriftButton(label: 'Next', onPressed: _startLiveness),
      ],
    );
  }

  Widget _bannedIcon(IconData icon) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon, size: 36, color: AppColors.textHint),
        Positioned(
          right: -6,
          bottom: -4,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close, size: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: AppTypography.body),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }

  Widget _buildSegment(int stepIndex, String label) {
    final isActive = _currentStep >= stepIndex;
    final isPast = _currentStep > stepIndex;

    return Expanded(
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isPast)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.check_circle,
                    size: 12,
                    color: AppColors.primary,
                  ),
                ),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: isActive ? AppColors.textPrimary : AppColors.textHint,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingScreen(BuildContext context, AuthUser? user) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Status'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.warning.withValues(alpha: 0.1),
                      AppColors.warning.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.hourglass_empty_rounded,
                        color: AppColors.warning,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Application Under Review',
                      style: AppTypography.heading.copyWith(
                        fontSize: 20,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your seller verification request is currently being reviewed by our trust and safety team. We\'ll notify you once it\'s processed.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Verification Progress', style: AppTypography.subheading),
              const SizedBox(height: 16),
              _buildTimelineStep(
                title: 'Application Submitted',
                subtitle: 'Store details and documents uploaded successfully',
                isDone: true,
                isPending: false,
              ),
              _buildTimelineStep(
                title: 'Document Review',
                subtitle:
                    'An admin will compare your ID and face photo in the app',
                isDone: false,
                isPending: true,
              ),
              _buildTimelineStep(
                title: 'Shop Activation',
                subtitle: 'Verified badge assigned and listing tools unlocked',
                isDone: false,
                isPending: false,
                isLast: true,
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Submitted Details',
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _detailRow('Shop Name', user?.shopName ?? 'Vintage PH'),
                    _detailRow('Location', user?.location ?? 'Davao City'),
                    _detailRow('Government ID', 'Uploaded for admin review'),
                    _detailRow('Face verification', 'Liveness check completed'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'You will get an in-app notification when an admin approves or rejects this application.',
                style: AppTypography.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRejectedScreen(BuildContext context, AuthUser? user) {
    final auth = context.read<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Status'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.error.withValues(alpha: 0.1),
                      AppColors.error.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cancel_outlined,
                        color: AppColors.error,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Application Rejected',
                      style: AppTypography.heading.copyWith(
                        fontSize: 20,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Unfortunately, your seller verification application has been rejected.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Reason for Rejection',
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user?.verificationRejectionReason ??
                          'The ID submission details could not be verified. Please make sure the name on your store matches the name on your ID.',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Want to try again? Please ensure your document and selfie match and are shot in bright lighting.',
                style: AppTypography.caption,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ThriftButton(
                label: 'Reapply & Edit Details',
                onPressed: () => _handleReapply(auth),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required String subtitle,
    required bool isDone,
    required bool isPending,
    bool isLast = false,
  }) {
    final lineCol = isDone ? AppColors.success : AppColors.border;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isDone
                    ? AppColors.success.withValues(alpha: 0.15)
                    : (isPending
                          ? AppColors.warning.withValues(alpha: 0.15)
                          : AppColors.surfaceVariant),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDone
                      ? AppColors.success
                      : (isPending ? AppColors.warning : AppColors.border),
                  width: 2,
                ),
              ),
              child: isDone
                  ? const Icon(Icons.check, size: 14, color: AppColors.success)
                  : (isPending
                        ? const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.warning,
                              ),
                            ),
                          )
                        : null),
            ),
            if (!isLast) Container(width: 2, height: 36, color: lineCol),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDone
                      ? AppColors.textPrimary
                      : (isPending ? AppColors.warning : AppColors.textHint),
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: AppTypography.caption),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.caption),
          Text(
            value,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _continueFromAddress() {
    final error = SellerAddressDraft.validate(
      storeName: _storeNameCtrl.text,
      barangay: _selectedBarangay,
      allowedBarangays: _barangays,
      addressLine1: _addressLine1Ctrl.text,
    );
    if (error != null) {
      showThriftSnackBar(context, error);
      return;
    }
    setState(() => _currentStep = 1);
  }

  String _idPairStatusMessage(IdCapturePair pair) {
    if (pair.canProceed) {
      return 'Both ID photos passed the quality check.';
    }
    if (_idFrontBytes == null || _idBackBytes == null) {
      return 'Both front and back photos are required.';
    }
    if (pair.front == null || pair.back == null) {
      return 'Checking ID photos…';
    }
    if (pair.blockingIssue == IdQualityIssue.notId) {
      return 'No ID detected on one of the photos. Place the ID in the frame and retake.';
    }
    return 'Retake the photo that did not pass before continuing.';
  }

  void _continueFromId() {
    final pair = IdCapturePair(front: _frontQuality, back: _backQuality);
    if (!pair.canProceed) {
      showThriftSnackBar(context, _idPairStatusMessage(pair));
      return;
    }
    setState(() => _currentStep = 2);
  }

  Future<void> _startIdCaptureFlow() async {
    final result = await Navigator.of(context).push<IdCaptureResult>(
      MaterialPageRoute(builder: (_) => const IdCaptureScreen()),
    );
    if (!mounted || result == null) return;

    setState(() {
      _idFrontBytes = result.frontBytes;
      _idBackBytes = result.backBytes;
      _frontQuality = result.frontQuality;
      _backQuality = result.backQuality;
    });
  }

  Future<void> _startLiveness() async {
    final result = await Navigator.of(context).push<LivenessResult>(
      MaterialPageRoute(builder: (_) => const LivenessCaptureScreen()),
    );
    if (!mounted || result == null) return;
    if (!result.livenessPassed) {
      showThriftSnackBar(
        context,
        'Complete look left, look right, and a blink before capturing.',
        isError: true,
      );
      return;
    }
    if (!result.imageQualityPassed || !result.passed) {
      showThriftSnackBar(
        context,
        'No face detected. Please position your face inside the frame.',
        isError: true,
      );
      return;
    }
    setState(() {
      _liveness = result;
      _selfieUploaded = true;
    });
  }

  Future<void> _submit(AuthProvider auth) async {
    final front = _idFrontBytes;
    final back = _idBackBytes;
    final liveness = _liveness;
    final pair = IdCapturePair(front: _frontQuality, back: _backQuality);
    if (front == null || back == null || !pair.canProceed) {
      showThriftSnackBar(
        context,
        'Please complete ID capture and pass the quality check first.',
      );
      setState(() => _currentStep = 1);
      return;
    }
    if (liveness == null || !liveness.passed) {
      showThriftSnackBar(context, 'Please complete the live face check first.');
      return;
    }

    final address = SellerAddressDraft(
      storeName: _storeNameCtrl.text,
      barangay: _selectedBarangay,
      addressLine1: _addressLine1Ctrl.text,
      addressLine2: _addressLine2Ctrl.text,
    );
    final addressError = SellerAddressDraft.validate(
      storeName: address.storeName,
      barangay: address.barangay,
      allowedBarangays: _barangays,
      addressLine1: address.addressLine1,
    );
    if (addressError != null) {
      showThriftSnackBar(context, addressError);
      setState(() => _currentStep = 0);
      return;
    }

    setState(() => _submitting = true);
    try {
      await SellerVerificationService(
        context.read<SupabaseService>(),
      ).submitApplication(
        address: address,
        idFrontBytes: front,
        idBackBytes: back,
        selfieBytes: liveness.imageBytes,
        selfieFileName: liveness.fileName,
        liveness: liveness.challenges,
      );
      await auth.reloadUser();
      if (mounted) {
        showThriftSnackBar(
          context,
          'Seller application submitted. An admin will review it.',
        );
      }
    } catch (error) {
      if (mounted) {
        showThriftSnackBar(
          context,
          sellerSubmitUserMessage(error),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _handleReapply(AuthProvider auth) {
    setState(() {
      _currentStep = 0;
      _idFrontBytes = null;
      _idBackBytes = null;
      _frontQuality = null;
      _backQuality = null;
      _selfieUploaded = false;
      _liveness = null;
      _storeNameCtrl.clear();
      _addressLine1Ctrl.clear();
      _addressLine2Ctrl.clear();
      _selectedBarangay = null;
    });
    auth.prepareVerificationReapply();
  }
}
