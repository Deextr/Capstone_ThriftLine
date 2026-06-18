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
              // Step indicator
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingMd,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _stepCircle(0, 'Store Info'),
                    _stepLine(0),
                    _stepCircle(1, 'ID Upload'),
                    _stepLine(1),
                    _stepCircle(2, 'Selfie'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  child: _buildStep(),
                ),
              ),
              // Bottom button
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
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
        ThriftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.storefront,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Store Details', style: AppTypography.subheading),
                        Text(
                          'Tell us about your thrift store',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ThriftTextField(
                label: 'Store Name',
                hint: 'e.g. Vintage Vibes PH',
                controller: _storeNameCtrl,
                icon: Icons.store,
              ),
              const SizedBox(height: 16),
              Text(
                'Region / Barangay',
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppConstants.spacingXs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
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
                          (b) => DropdownMenuItem(value: b, child: Text(b)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedRegion = v!),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
        const SizedBox(height: 16),
        ThriftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Why sell on Thriftline?', style: AppTypography.subheading),
              const SizedBox(height: 12),
              _benefitRow(Icons.trending_up, 'Reach thousands of thrift buyers'),
              _benefitRow(Icons.flash_on, 'AI-powered pricing suggestions'),
              _benefitRow(Icons.security, 'Secure payment processing'),
              _benefitRow(Icons.local_shipping, 'Integrated shipping options'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _benefitRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
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
        ThriftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.badge_outlined,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Government ID',
                          style: AppTypography.subheading,
                        ),
                        Text(
                          'Upload a clear photo of your valid government ID',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  setState(() => _govIdUploaded = true);
                  showThriftSnackBar(context, 'ID photo selected');
                },
                child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: _govIdUploaded
                        ? AppColors.primaryLight
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _govIdUploaded
                          ? AppColors.primary
                          : AppColors.border,
                      width: _govIdUploaded ? 2 : 1,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                  child: _govIdUploaded
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'ID Photo Uploaded',
                              style: AppTypography.body.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to replace',
                              style: AppTypography.caption,
                            ),
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
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.camera_alt_outlined,
                                color: AppColors.primary,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Take Photo or Upload',
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to capture or choose from gallery',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ThriftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Accepted IDs', style: AppTypography.subheading),
              const SizedBox(height: 12),
              _idTypeRow('Philippine National ID'),
              _idTypeRow('Driver\'s License'),
              _idTypeRow('Passport'),
              _idTypeRow('PhilHealth ID'),
              _idTypeRow('SSS ID'),
              _idTypeRow('Voter\'s ID'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _idTypeRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check, size: 16, color: AppColors.success),
          const SizedBox(width: 8),
          Text(text, style: AppTypography.body),
        ],
      ),
    );
  }

  // ─── Step 3: Verification Selfie ───
  Widget _selfieStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ThriftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.face,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verification Selfie',
                          style: AppTypography.subheading,
                        ),
                        Text(
                          'Take a selfie while holding your ID',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  setState(() => _selfieUploaded = true);
                  showThriftSnackBar(context, 'Selfie captured');
                },
                child: Container(
                  width: double.infinity,
                  height: 240,
                  decoration: BoxDecoration(
                    color: _selfieUploaded
                        ? AppColors.primaryLight
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _selfieUploaded
                          ? AppColors.primary
                          : AppColors.border,
                      width: _selfieUploaded ? 2 : 1,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                  child: _selfieUploaded
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Selfie Captured',
                              style: AppTypography.body.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tap to retake',
                              style: AppTypography.caption,
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.person_outline,
                                color: AppColors.primary,
                                size: 48,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Take a Selfie',
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Hold your ID next to your face',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ThriftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tips for a good selfie', style: AppTypography.subheading),
              const SizedBox(height: 12),
              _tipRow(Icons.light_mode, 'Ensure good lighting'),
              _tipRow(Icons.crop_portrait, 'Hold your ID beside your face'),
              _tipRow(Icons.visibility, 'Make sure your face and ID are clearly visible'),
              _tipRow(Icons.no_photography, 'Don\'t use filters or edited photos'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tipRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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

  // ─── Step indicator widgets ───
  Widget _stepCircle(int step, String label) {
    final isActive = _currentStep >= step;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : AppColors.surfaceVariant,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? AppColors.primary : AppColors.border,
                width: 2,
              ),
            ),
            child: Center(
              child: isActive && _currentStep > step
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
                      '${step + 1}',
                      style: AppTypography.caption.copyWith(
                        color: isActive ? Colors.white : AppColors.textHint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: isActive ? AppColors.primary : AppColors.textHint,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _stepLine(int step) {
    final isActive = _currentStep > step;
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 18),
      color: isActive ? AppColors.primary : AppColors.border,
    );
  }
}
