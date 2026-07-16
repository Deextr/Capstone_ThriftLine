import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class ReportSellerScreen extends StatefulWidget {
  const ReportSellerScreen({super.key, this.sellerUsername});

  final String? sellerUsername;

  @override
  State<ReportSellerScreen> createState() => _ReportSellerScreenState();
}

class _ReportSellerScreenState extends State<ReportSellerScreen> {
  int _currentStep = 0; // 0 = category, 1 = evidence, 2 = review
  String? _selectedCategory;
  final _detailsCtrl = TextEditingController();
  final _orderId = TextEditingController();
  bool _isSubmitting = false;

  // Evidence attachment tracking
  final Set<String> _attachedEvidence = {};
  static const _evidenceTypes = [
    {'key': 'screenshots', 'label': 'Screenshots', 'icon': Icons.screenshot_outlined, 'desc': 'Screen captures of suspicious activity'},
    {'key': 'chat', 'label': 'Chat Conversations', 'icon': Icons.chat_bubble_outline, 'desc': 'Message history with the seller'},
    {'key': 'photos', 'label': 'Product Photos', 'icon': Icons.photo_camera_outlined, 'desc': 'Photos of item received vs listed'},
    {'key': 'receipts', 'label': 'Payment Receipts', 'icon': Icons.receipt_long_outlined, 'desc': 'Transaction or payment proof'},
    {'key': 'delivery', 'label': 'Delivery Proof', 'icon': Icons.local_shipping_outlined, 'desc': 'Shipping or non-delivery evidence'},
  ];

  static const _categories = [
    {'label': 'Scam or Fraud', 'icon': Icons.warning_amber_rounded, 'desc': 'Seller is running a scam or fraudulent scheme', 'color': 0xFFEF4444},
    {'label': 'Fake Product', 'icon': Icons.cancel_outlined, 'desc': 'Product is fake or not genuine', 'color': 0xFFF97316},
    {'label': 'Counterfeit Item', 'icon': Icons.content_copy_outlined, 'desc': 'Product is a counterfeit of a known brand', 'color': 0xFFF59E0B},
    {'label': 'Harassment', 'icon': Icons.mood_bad_outlined, 'desc': 'Seller is harassing or threatening you', 'color': 0xFFEF4444},
    {'label': 'Inappropriate Messages', 'icon': Icons.chat_bubble_outline, 'desc': 'Seller sent inappropriate or offensive content', 'color': 0xFF8B5CF6},
    {'label': 'Failure to Ship', 'icon': Icons.local_shipping_outlined, 'desc': 'Seller failed to ship the purchased item', 'color': 0xFF3B82F6},
    {'label': 'Item Not as Described', 'icon': Icons.difference_outlined, 'desc': 'Item received is different from the listing', 'color': 0xFF06B6D4},
    {'label': 'Fake Identity', 'icon': Icons.person_off_outlined, 'desc': 'Seller is using a fake identity or stolen photos', 'color': 0xFFEC4899},
    {'label': 'Other', 'icon': Icons.more_horiz_outlined, 'desc': 'Other violation not listed above', 'color': 0xFF64748B},
  ];

  @override
  void dispose() {
    _detailsCtrl.dispose();
    _orderId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Report Seller'),
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
              _buildStepIndicator(),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildCurrentStep(),
                  ),
                ),
              ),
              // Bottom navigation
              _buildBottomNav(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Step Indicator ───
  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd, vertical: 16),
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
              _stepSegment(0, 'Category'),
              const SizedBox(width: 8),
              _stepSegment(1, 'Evidence'),
              const SizedBox(width: 8),
              _stepSegment(2, 'Review'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _stepTitle(),
                style: AppTypography.subheading.copyWith(color: AppColors.error),
              ),
              Text(
                'Step ${_currentStep + 1} of 3',
                style: AppTypography.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepSegment(int index, String label) {
    final isActive = _currentStep >= index;
    final isPast = _currentStep > index;
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? AppColors.error : AppColors.surfaceVariant,
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
                  child: Icon(Icons.check_circle, size: 12, color: AppColors.error),
                ),
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: isActive ? AppColors.textPrimary : AppColors.textHint,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _stepTitle() {
    switch (_currentStep) {
      case 0: return 'Select Report Category';
      case 1: return 'Attach Evidence';
      case 2: return 'Review & Submit';
      default: return '';
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0: return _buildCategoryStep(key: const ValueKey('cat'));
      case 1: return _buildEvidenceStep(key: const ValueKey('evi'));
      case 2: return _buildReviewStep(key: const ValueKey('rev'));
      default: return const SizedBox.shrink();
    }
  }

  // ─── Step 1: Category Selection ───
  Widget _buildCategoryStep({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Trust & safety header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.error.withValues(alpha: 0.08), AppColors.error.withValues(alpha: 0.02)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_outlined, color: AppColors.error, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trust & Safety', style: AppTypography.subheading.copyWith(color: AppColors.error)),
                    const SizedBox(height: 4),
                    Text(
                      'Your report helps keep our community safe. All reports are reviewed within 24-48 hours.',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.sellerUsername != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_outlined, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text('Reporting: ', style: AppTypography.caption),
                Text(
                  '@${widget.sellerUsername}',
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Text('What would you like to report?', style: AppTypography.subheading),
        const SizedBox(height: 12),
        ..._categories.map((cat) => _buildCategoryTile(cat)),
      ],
    );
  }

  Widget _buildCategoryTile(Map<String, dynamic> cat) {
    final isSelected = _selectedCategory == cat['label'];
    final color = Color(cat['color'] as int);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _selectedCategory = cat['label'] as String),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.08) : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color.withValues(alpha: 0.5) : AppColors.border.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.2) : AppColors.surfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cat['icon'] as IconData, size: 20, color: isSelected ? color : AppColors.textSecondary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cat['label'] as String,
                      style: AppTypography.body.copyWith(
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? color : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(cat['desc'] as String, style: AppTypography.caption.copyWith(fontSize: 11)),
                  ],
                ),
              ),
              AnimatedScale(
                scale: isSelected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Step 2: Evidence Attachment ───
  Widget _buildEvidenceStep({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 20, color: AppColors.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Attach supporting evidence to help our team investigate your report faster. At least one piece of evidence is recommended.',
                  style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Evidence attachment cards
        Text('Attach Evidence', style: AppTypography.subheading),
        const SizedBox(height: 4),
        Text('Tap to simulate attaching each type of evidence', style: AppTypography.caption),
        const SizedBox(height: 16),
        ..._evidenceTypes.map((ev) => _buildEvidenceCard(ev)),

        const SizedBox(height: 24),

        // Additional comments
        Text('Additional Comments', style: AppTypography.subheading),
        const SizedBox(height: 4),
        Text('Provide any extra details that might help our investigation', style: AppTypography.caption),
        const SizedBox(height: 12),
        ThriftTextField(
          hint: 'Describe what happened in detail...',
          controller: _detailsCtrl,
          maxLines: 5,
          icon: Icons.edit_note_outlined,
        ),

        const SizedBox(height: 20),

        // Order ID (optional)
        ThriftTextField(
          label: 'Related Order ID (optional)',
          hint: 'e.g. TL-82901738',
          controller: _orderId,
          icon: Icons.receipt_outlined,
        ),
      ],
    );
  }

  Widget _buildEvidenceCard(Map<String, dynamic> ev) {
    final key = ev['key'] as String;
    final isAttached = _attachedEvidence.contains(key);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () {
          setState(() {
            if (isAttached) {
              _attachedEvidence.remove(key);
            } else {
              _attachedEvidence.add(key);
            }
          });
          if (!isAttached) {
            showThriftSnackBar(context, '${ev['label']} attached successfully');
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isAttached ? AppColors.success.withValues(alpha: 0.06) : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isAttached ? AppColors.success.withValues(alpha: 0.4) : AppColors.border.withValues(alpha: 0.5),
              width: isAttached ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isAttached
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.surfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  ev['icon'] as IconData,
                  size: 22,
                  color: isAttached ? AppColors.success : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ev['label'] as String,
                      style: AppTypography.body.copyWith(
                        fontWeight: isAttached ? FontWeight.w700 : FontWeight.w500,
                        color: isAttached ? AppColors.success : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ev['desc'] as String,
                      style: AppTypography.caption.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (isAttached)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        'Attached',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add, size: 18, color: AppColors.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Step 3: Review & Submit ───
  Widget _buildReviewStep({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report Summary', style: AppTypography.heading.copyWith(fontSize: 18)),
              const SizedBox(height: 20),

              // Category
              _reviewRow('Category', _selectedCategory ?? 'N/A', Icons.category_outlined),
              const Divider(height: 24),

              // Seller
              if (widget.sellerUsername != null) ...[
                _reviewRow('Reported Seller', '@${widget.sellerUsername}', Icons.person_outlined),
                const Divider(height: 24),
              ],

              // Evidence count
              _reviewRow(
                'Evidence Attached',
                _attachedEvidence.isEmpty
                    ? 'None'
                    : '${_attachedEvidence.length} item${_attachedEvidence.length > 1 ? 's' : ''}',
                Icons.attach_file_outlined,
              ),

              if (_attachedEvidence.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _attachedEvidence.map((key) {
                    final ev = _evidenceTypes.firstWhere((e) => e['key'] == key);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(ev['icon'] as IconData, size: 14, color: AppColors.success),
                          const SizedBox(width: 6),
                          Text(
                            ev['label'] as String,
                            style: AppTypography.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],

              if (_detailsCtrl.text.trim().isNotEmpty) ...[
                const Divider(height: 24),
                _reviewRow('Comments', '', Icons.comment_outlined),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _detailsCtrl.text.trim(),
                    style: AppTypography.body.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],

              if (_orderId.text.trim().isNotEmpty) ...[
                const Divider(height: 24),
                _reviewRow('Order ID', _orderId.text.trim(), Icons.receipt_outlined),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Policy notice
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.policy_outlined, size: 20, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('False Report Policy', style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, color: AppColors.warning)),
                    const SizedBox(height: 4),
                    Text(
                      'Filing false or malicious reports may result in restrictions on your account. All reports are reviewed by our Trust & Safety team.',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Expected timeline
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryLight.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule_outlined, size: 20, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reports are typically reviewed within 24–48 hours. You\'ll receive a notification when a decision is made.',
                  style: AppTypography.caption.copyWith(color: AppColors.primaryDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Text('$label: ', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500)),
        if (value.isNotEmpty) Text(value, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ─── Bottom Navigation ───
  Widget _buildBottomNav() {
    return Container(
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
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: ThriftButton(
                label: 'Back',
                variant: ThriftButtonVariant.outline,
                color: AppColors.textSecondary,
                onPressed: () => setState(() => _currentStep--),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: _currentStep > 0 ? 2 : 1,
            child: _currentStep < 2
                ? ThriftButton(
                    label: 'Continue',
                    color: AppColors.error,
                    onPressed: _handleNext,
                  )
                : ThriftButton(
                    label: 'Submit Report',
                    color: AppColors.error,
                    icon: Icons.send_outlined,
                    isLoading: _isSubmitting,
                    onPressed: _handleSubmit,
                  ),
          ),
        ],
      ),
    );
  }

  void _handleNext() {
    if (_currentStep == 0 && _selectedCategory == null) {
      showThriftSnackBar(context, 'Please select a report category', isError: true);
      return;
    }
    setState(() => _currentStep++);
  }

  Future<void> _handleSubmit() async {
    if (_selectedCategory == null) return;

    setState(() => _isSubmitting = true);

    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    // Add report to data provider
    final data = context.read<DataProvider>();
    data.addReport(
      category: _selectedCategory!,
      sellerUsername: widget.sellerUsername ?? 'unknown',
      details: _detailsCtrl.text.trim(),
      evidenceCount: _attachedEvidence.length,
      orderId: _orderId.text.trim(),
    );

    setState(() => _isSubmitting = false);

    if (!mounted) return;

    // Show success dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 48),
            ),
            const SizedBox(height: 16),
            Text('Report Submitted', style: AppTypography.heading),
            const SizedBox(height: 8),
            Text(
              'Thank you for helping keep our community safe. We\'ll review your report and notify you of the outcome.',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Report ID: RPT-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
                style: AppTypography.caption.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ThriftButton(
              label: 'View My Reports',
              onPressed: () {
                Navigator.pop(ctx);
                context.pop();
                context.push('/my-reports');
              },
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.pop();
              },
              child: Text('Done', style: AppTypography.body.copyWith(color: AppColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}
