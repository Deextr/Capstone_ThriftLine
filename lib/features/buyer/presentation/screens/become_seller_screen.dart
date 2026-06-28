import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
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
                          setState(() => _currentStep++);
                        },
                      )
                    : ThriftButton(
                        label: 'Submit Application',
                        onPressed: () {
                          showThriftSnackBar(
                            context,
                            'Seller application submitted! We\'ll review it shortly.',
                          );
                          context.pop();
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
}
