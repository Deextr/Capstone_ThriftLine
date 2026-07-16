import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../features/auth/domain/auth_user.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class BecomeSellerScreen extends StatefulWidget {
  const BecomeSellerScreen({super.key});

  @override
  State<BecomeSellerScreen> createState() => _BecomeSellerScreenState();
}

class _BecomeSellerScreenState extends State<BecomeSellerScreen> {
  final _storeNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _selectedRegion = 'Select Barangay';
  bool _govIdUploaded = false;
  bool _selfieUploaded = false;
  int _currentStep = 0;

  final List<String> _davaoBarangays = [
    'Select Barangay',
    'Poblacion District',
    'Agdao',
    'Buhangin',
    'Bunawan',
    'Calinan',
    'Catalunan Grande',
    'Catalunan Pequeño',
    'Matina',
    'Talomo',
    'Toril',
    'Tugbok',
    'Mintal',
    'Tibungco',
    'Panacan',
    'Sasa',
  ];

  @override
  void dispose() {
    _storeNameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
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

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Become a Seller'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          elevation: 0,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Sleek segmented indicator
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
                    )
                  ]
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildSegment(0, 'Store Info'),
                        const SizedBox(width: 8),
                        _buildSegment(1, 'ID Upload'),
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
                          style: AppTypography.subheading.copyWith(color: AppColors.primary),
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
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  child: _buildStep(),
                ),
              ),
              // Bottom button
              Container(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -4),
                    )
                  ]
                ),
                child: _currentStep < 2
                    ? ThriftButton(
                        label: 'Continue',
                        onPressed: () {
                          if (_currentStep == 0) {
                            if (_storeNameCtrl.text.trim().isEmpty) {
                              showThriftSnackBar(context, 'Please enter a store name.');
                              return;
                            }
                            if (_selectedRegion == 'Select Barangay') {
                              showThriftSnackBar(context, 'Please select a barangay.');
                              return;
                            }
                            if (_addressCtrl.text.trim().isEmpty) {
                              showThriftSnackBar(context, 'Please enter a store address.');
                              return;
                            }
                          } else if (_currentStep == 1) {
                            if (!_govIdUploaded) {
                              showThriftSnackBar(context, 'Please upload a photo of your valid ID.');
                              return;
                            }
                          }
                          setState(() => _currentStep++);
                        },
                      )
                    : ThriftButton(
                        label: 'Submit Application',
                        onPressed: () async {
                          if (!_govIdUploaded) {
                            showThriftSnackBar(context, 'Please upload your government ID first.');
                            return;
                          }
                          if (!_selfieUploaded) {
                            showThriftSnackBar(context, 'Please upload your selfie first.');
                            return;
                          }
                          
                          await auth.submitSellerApplication(
                            storeName: _storeNameCtrl.text.isEmpty ? 'My Thrift Shop' : _storeNameCtrl.text,
                            address: _addressCtrl.text.isEmpty ? 'Davao City' : _addressCtrl.text,
                            region: _selectedRegion == 'Select Barangay' ? 'Poblacion District' : _selectedRegion,
                          );
                          
                          if (context.mounted) {
                            showThriftSnackBar(
                              context,
                              'Seller application submitted! We\'ll review it shortly.',
                            );
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0: return 'Store Details';
      case 1: return 'Government ID Verification';
      case 2: return 'Selfie Verification';
      default: return '';
    }
  }

  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return _storeInfoStep();
      case 1:
        return _idUploadStep();
      case 2:
        return _selfieStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─── Step 1: Store Information ───
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
              Text(
                'Region / Barangay',
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant.withValues(alpha: 0.3),
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRegion,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textHint,
                    ),
                    items: _davaoBarangays
                        .map(
                          (b) => DropdownMenuItem(value: b, child: Text(b, style: AppTypography.body)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedRegion = v!),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ThriftTextField(
                label: 'Store Address',
                hint: 'Complete street address',
                controller: _addressCtrl,
                icon: Icons.location_on_outlined,
                maxLines: 2,
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
                  const Icon(Icons.stars_outlined, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Why sell on Thriftline?', style: AppTypography.subheading.copyWith(color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 16),
              _benefitRow(Icons.trending_up_outlined, 'Reach thousands of thrift buyers'),
              _benefitRow(Icons.auto_awesome_outlined, 'AI-powered pricing suggestions'),
              _benefitRow(Icons.security_outlined, 'Secure payment processing'),
              _benefitRow(Icons.local_shipping_outlined, 'Integrated shipping options'),
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

  // ─── Step 2: Government ID Upload ───
  Widget _idUploadStep() {
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
              Text(
                'Upload a clear photo of your valid government ID. Ensure all details are readable.',
                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  setState(() => _govIdUploaded = true);
                  showThriftSnackBar(context, 'ID photo selected');
                },
                child: Container(
                  width: double.infinity,
                  height: 220,
                  decoration: BoxDecoration(
                    color: _govIdUploaded
                        ? AppColors.success.withValues(alpha: 0.05)
                        : AppColors.primaryLight.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    // Simulated dashed border using a light border
                    border: Border.all(
                      color: _govIdUploaded
                          ? AppColors.success
                          : AppColors.primary.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: _govIdUploaded
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 40),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'ID Photo Uploaded',
                              style: AppTypography.body.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => setState(() => _govIdUploaded = false),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Replace Photo'),
                            )
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.add_photo_alternate_outlined,
                                color: AppColors.primary,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tap to upload ID',
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'JPG, PNG (Max 5MB)',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Accepted IDs', style: AppTypography.subheading),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _idChip('Philippine National ID'),
            _idChip('Driver\'s License'),
            _idChip('Passport'),
            _idChip('PhilHealth ID'),
            _idChip('SSS ID'),
            _idChip('Voter\'s ID'),
          ],
        )
      ],
    );
  }

  Widget _idChip(String text) {
    return Chip(
      label: Text(text, style: AppTypography.caption.copyWith(color: AppColors.textPrimary)),
      backgroundColor: AppColors.surfaceVariant.withValues(alpha: 0.5),
      side: const BorderSide(color: AppColors.border),
      avatar: const Icon(Icons.check, size: 16, color: AppColors.success),
    );
  }

  // ─── Step 3: Verification Selfie ───
  Widget _selfieStep() {
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
              Text(
                'Take a selfie while holding your ID next to your face to verify your identity.',
                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  setState(() => _selfieUploaded = true);
                  showThriftSnackBar(context, 'Selfie captured');
                },
                child: Container(
                  width: double.infinity,
                  height: 280,
                  decoration: BoxDecoration(
                    color: _selfieUploaded
                        ? AppColors.success.withValues(alpha: 0.05)
                        : AppColors.primaryLight.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _selfieUploaded
                          ? AppColors.success
                          : AppColors.primary.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: _selfieUploaded
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 40),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Selfie Captured',
                              style: AppTypography.body.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () => setState(() => _selfieUploaded = false),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Retake Selfie'),
                            )
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_front_outlined,
                                color: AppColors.primary,
                                size: 40,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tap to open camera',
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
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
            color: AppColors.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lightbulb_outline, color: AppColors.secondary, size: 20),
                  const SizedBox(width: 8),
                  Text('Selfie Tips', style: AppTypography.subheading.copyWith(color: AppColors.secondary)),
                ],
              ),
              const SizedBox(height: 12),
              _tipRow(Icons.light_mode_outlined, 'Ensure good lighting'),
              _tipRow(Icons.crop_portrait_outlined, 'Hold your ID beside your face'),
              _tipRow(Icons.visibility_outlined, 'Make sure your face and ID are clearly visible'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tipRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTypography.body)),
        ],
      ),
    );
  }

  // ─── Segmented Indicator ───
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
                  child: Icon(Icons.check_circle, size: 12, color: AppColors.primary),
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

  // ─── Pending Screen (Under Review) ───
  Widget _buildPendingScreen(BuildContext context, AuthUser? user) {
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pending Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.warning.withValues(alpha: 0.1), AppColors.warning.withValues(alpha: 0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3), width: 1.5),
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
                      style: AppTypography.heading.copyWith(fontSize: 20, color: AppColors.warning),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your seller verification request is currently being reviewed by our trust and safety team. We\'ll notify you once it\'s processed.',
                      style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Timeline Steps
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
                subtitle: 'Simulated review processing (under 5 mins for demo)',
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

              // Summary Details
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
                    Text('Submitted Details', style: AppTypography.body.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _detailRow('Shop Name', user?.shopName ?? 'Vintage PH'),
                    _detailRow('Location', user?.location ?? 'Davao City'),
                    _detailRow('Government ID', 'Philippine National ID (Verified File)'),
                    _detailRow('Verification Selfie', 'Face Match Photo (Selfie + ID)'),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Admin Review Simulation Panel
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.construction_outlined, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Review Control Panel (Simulator)',
                          style: AppTypography.subheading.copyWith(color: AppColors.primaryDark),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use these buttons to simulate how the admin review will affect your profile in real-time.',
                      style: AppTypography.caption,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Reject ID'),
                            onPressed: () => _showRejectionDialog(context, auth),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Approve ID'),
                            onPressed: () async {
                              await auth.simulateApproveApplication();
                              if (context.mounted) {
                                showThriftSnackBar(context, '🎉 Congratulations! You are now a Verified Seller!');
                                context.pop();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Rejected Screen ───
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
              // Rejection Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.error.withValues(alpha: 0.1), AppColors.error.withValues(alpha: 0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3), width: 1.5),
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
                      style: AppTypography.heading.copyWith(fontSize: 20, color: AppColors.error),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Unfortunately, your seller verification application has been rejected.',
                      style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Rejection Reason Card
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
                        const Icon(Icons.info_outline, color: AppColors.error, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Reason for Rejection',
                          style: AppTypography.body.copyWith(fontWeight: FontWeight.bold, color: AppColors.error),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user?.verificationRejectionReason ??
                          'The ID submission details could not be verified. Please make sure the name on your store matches the name on your ID.',
                      style: AppTypography.body.copyWith(color: AppColors.textPrimary),
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
    Color lineCol = isDone ? AppColors.success : AppColors.border;
    
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
                    : (isPending ? AppColors.warning.withValues(alpha: 0.15) : AppColors.surfaceVariant),
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
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.warning),
                          ),
                        )
                      : null),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: lineCol,
              ),
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
                  color: isDone ? AppColors.textPrimary : (isPending ? AppColors.warning : AppColors.textHint),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppTypography.caption,
              ),
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
          Text(value, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showRejectionDialog(BuildContext context, AuthProvider auth) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Simulate Application Rejection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Specify a reason for rejecting this ID verification submission to simulate the feedback loop.',
              style: AppTypography.body,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. Selfie photo is too dark. Please retake the selfie under better lighting.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final reason = reasonCtrl.text.trim().isEmpty
                  ? 'The submitted selfie holding your ID is too blurry to match the face on the ID.'
                  : reasonCtrl.text.trim();
              await auth.simulateRejectApplication(reason);
              if (dialogCtx.mounted) {
                Navigator.pop(dialogCtx);
                showThriftSnackBar(context, 'Application rejected (simulation)');
              }
            },
            child: const Text('Reject Submission'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReapply(AuthProvider auth) async {
    setState(() {
      _currentStep = 0;
      _govIdUploaded = false;
      _selfieUploaded = false;
      _storeNameCtrl.clear();
      _addressCtrl.clear();
      _selectedRegion = 'Select Barangay';
    });
    await auth.resetVerificationStatus();
  }
}
