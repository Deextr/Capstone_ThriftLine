import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../seller/domain/seller_id_type.dart';
import '../../../seller/domain/external_selling.dart';
import '../../data/admin_review_rules.dart';
import '../../data/admin_verification_service.dart';
import '../../data/external_history_service.dart';
import '../widgets/admin_review_widgets.dart';
import '../widgets/admin_ui_components.dart';
import '../widgets/external_selling_history_section.dart';
import '../widgets/seller_application_reject_dialog.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key, required this.verificationId});

  final String verificationId;

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  late final AdminVerificationService _service;
  late final ExternalHistoryService _historyService;
  SellerApplication? _application;
  List<ExternalHistoryItem> _history = const [];
  String? _idUrl;
  String? _idBackUrl;
  String? _selfieUrl;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final supabase = context.read<SupabaseService>();
    _service = AdminVerificationService(supabase);
    _historyService = ExternalHistoryService(supabase);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final match = await _service.getById(widget.verificationId);
      if (match == null) {
        if (mounted) {
          setState(() {
            _application = null;
            _loading = false;
          });
        }
        return;
      }
      final idUrl = await _service.signedUrl(match.idPath);
      final idBackUrl = await _service.signedUrl(match.idBackPath);
      final selfieUrl = await _service.signedUrl(match.selfiePath);
      List<ExternalHistoryItem> history = const [];
      try {
        history = await _historyService.load(match.id);
      } catch (_) {
        history = const [];
      }
      if (!mounted) return;
      setState(() {
        _application = match;
        _history = history;
        _idUrl = idUrl;
        _idBackUrl = idBackUrl;
        _selfieUrl = selfieUrl;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to load this seller application.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _review(String decision, {String? reason}) async {
    setState(() => _busy = true);
    try {
      await _service.review(
        verificationId: widget.verificationId,
        decision: decision,
        reason: reason,
      );
      if (!mounted) return;
      showThriftSnackBar(
        context,
        decision == 'approved'
            ? 'Seller approved. Their storefront is now active.'
            : 'Application rejected.',
      );
      context.pop();
    } catch (e) {
      if (mounted) {
        showThriftSnackBar(
          context,
          adminFriendlyError(e, 'Could not save that decision. Try again.'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewExternal(
    ExternalHistoryItem item,
    ExternalReviewStatus decision,
  ) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(decision.label),
        content: TextField(
          controller: noteCtrl,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'Visible only to fellow administrators',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _historyService.review(
        transactionId: item.id,
        decision: decision,
        note: note.isEmpty ? null : note,
      );
      final history = await _historyService.load(widget.verificationId);
      if (!mounted) return;
      setState(() => _history = history);
      showThriftSnackBar(context, 'External transaction review updated.');
    } catch (e) {
      if (mounted) {
        showThriftSnackBar(
          context,
          adminFriendlyError(
            e,
            'Could not save that review. Two different photos are required to verify.',
          ),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Approve this seller?'),
        content: const Text(
          'Approving this application will grant seller privileges. The user will be able to publish listings on ThriftLine.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Keep pending'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Approve Seller'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _review('approved');
  }

  Future<void> _reject() async {
    final reason = await showSellerApplicationRejectDialog(context);
    if (reason == null || !mounted) return;
    await _review('rejected', reason: reason);
  }

  void _showImageLightbox(String title, String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          constraints: BoxConstraints(maxWidth: 800, maxHeight: 680),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: AppTypography.heading.copyWith(fontSize: 16),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: Container(
                  color: const Color(0xFF0F172A),
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: InteractiveViewer(
                      maxScale: 4.0,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, _) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (_, _, _) => const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image,
                              size: 48,
                              color: Colors.white54,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Unable to display document image',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = _application;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 1024;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const AdminDetailSkeleton()
            : _error != null
            ? AdminErrorState(message: _error!, onRetry: _load)
            : app == null
            ? const AdminEmptyState(
                title: 'Application not found',
                message: 'This application is no longer available.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
                children: [
                  // Breadcrumbs & Top Bar
                  _buildBreadcrumbs(app),
                  const SizedBox(height: 16),

                  // Header banner
                  _buildHeaderBanner(app),
                  const SizedBox(height: 24),

                  // Responsive 2-column or 1-column layout
                  if (isDesktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Column: Applicant, Store, Identity, Liveness
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildApplicantCard(app),
                              const SizedBox(height: 20),
                              _buildStoreCard(app),
                              const SizedBox(height: 20),
                              _buildIdentityDocumentsCard(app),
                              const SizedBox(height: 20),
                              _buildLivenessCard(app),
                              const SizedBox(height: 20),
                              ExternalSellingHistorySection(
                                claimedRange: app.claimedSellingRange,
                                items: _history,
                                busy: _busy,
                                onReview: _reviewExternal,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Right Column: Decision card & Actions
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [_buildDecisionCard(app)],
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDecisionCard(app),
                        const SizedBox(height: 20),
                        _buildApplicantCard(app),
                        const SizedBox(height: 20),
                        _buildStoreCard(app),
                        const SizedBox(height: 20),
                        _buildIdentityDocumentsCard(app),
                        const SizedBox(height: 20),
                        _buildLivenessCard(app),
                        const SizedBox(height: 20),
                        ExternalSellingHistorySection(
                          claimedRange: app.claimedSellingRange,
                          items: _history,
                          busy: _busy,
                          onReview: _reviewExternal,
                        ),
                      ],
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildBreadcrumbs(SellerApplication app) {
    return Row(
      children: [
        InkWell(
          onTap: () => context.go(RouteNames.adminVerifications),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_back, size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'Seller Verifications',
                style: AppTypography.label.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('/', style: TextStyle(color: AppColors.textHint)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            app.shopName,
            style: AppTypography.label.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBanner(SellerApplication app) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThriftAvatar(
            imageUrl: '',
            name: app.applicantName ?? app.shopName,
            size: 48,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        app.shopName,
                        style: AppTypography.pageTitle.copyWith(fontSize: 20),
                      ),
                    ),
                    AdminStatusBadge(status: app.status),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  'Submitted by ${app.applicantName ?? 'Applicant'} on ${formatFullDate(app.submittedAt)} at ${formatTimeOfDay(app.submittedAt)}',
                  style: AppTypography.body.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicantCard(SellerApplication app) {
    return _SectionCard(
      title: 'Applicant Information',
      icon: Icons.person_outline_rounded,
      children: [
        _InfoGrid(
          items: [
            _InfoGridItem(
              label: 'Full Name',
              value: app.applicantName ?? 'Not specified',
            ),
            _InfoGridItem(
              label: 'Username',
              value: (app.applicantUsername?.trim().isNotEmpty ?? false)
                  ? '@${app.applicantUsername!.trim()}'
                  : '—',
            ),
            _InfoGridItem(
              label: 'Email',
              value: (app.applicantEmail?.trim().isNotEmpty ?? false)
                  ? app.applicantEmail!.trim()
                  : '—',
            ),
            _InfoGridItem(label: 'User ID', value: app.userId, copyable: true),
          ],
        ),
      ],
    );
  }

  Widget _buildStoreCard(SellerApplication app) {
    return _SectionCard(
      title: 'Seller & Store Information',
      icon: Icons.storefront_outlined,
      children: [
        _InfoGrid(
          items: [
            _InfoGridItem(label: 'Store Name', value: app.shopName),
            _InfoGridItem(
              label: 'Barangay & City',
              value: '${app.barangay}, ${app.city}',
            ),
            _InfoGridItem(
              label: 'Complete Address',
              value: app.shopAddress.isNotEmpty ? app.shopAddress : '—',
            ),
            if (app.claimedSellingRange != null &&
                app.claimedSellingRange!.isNotEmpty)
              _InfoGridItem(
                label: 'Claimed Selling Experience',
                value: app.claimedSellingRange!,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdentityDocumentsCard(SellerApplication app) {
    final parsedId = SellerIdType.tryParse(app.idType);

    return _SectionCard(
      title: 'Identity Verification Documents',
      icon: Icons.badge_outlined,
      trailing: parsedId != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                parsedId.label,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      children: [
        Text(
          'Click any document to inspect the image in high resolution.',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _DocumentPreviewCard(
              label: 'Government ID (Front)',
              url: _idUrl,
              onTap: () => _showImageLightbox('Government ID (Front)', _idUrl),
            ),
            if (_showIdBack(app))
              _DocumentPreviewCard(
                label: 'Government ID (Back)',
                url: _idBackUrl,
                onTap: () =>
                    _showImageLightbox('Government ID (Back)', _idBackUrl),
              ),
            _DocumentPreviewCard(
              label: 'Applicant Selfie',
              url: _selfieUrl,
              onTap: () => _showImageLightbox('Applicant Selfie', _selfieUrl),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLivenessCard(SellerApplication app) {
    final checks = {
      'Face Detected': app.livenessResult['face'] == true,
      'Looked Right': app.livenessResult['lookRight'] == true,
      'Looked Left': app.livenessResult['lookLeft'] == true,
      'Blinked Eyes': app.livenessResult['blink'] == true,
    };

    return _SectionCard(
      title: 'Face / Liveness Verification',
      icon: Icons.face_retouching_natural_rounded,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: app.livenessPassed
              ? AppColors.success.withValues(alpha: 0.12)
              : AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              app.livenessPassed ? Icons.check_circle : Icons.cancel,
              size: 14,
              color: app.livenessPassed ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 4),
            Text(
              app.livenessPassed ? 'Liveness Passed' : 'Liveness Failed',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: app.livenessPassed ? AppColors.success : AppColors.error,
              ),
            ),
          ],
        ),
      ),
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: checks.entries.map((entry) {
            final passed = entry.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: passed
                    ? AppColors.success.withValues(alpha: 0.08)
                    : AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                border: Border.all(
                  color: passed
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    passed ? Icons.check : Icons.close,
                    size: 14,
                    color: passed ? AppColors.success : AppColors.error,
                  ),
                  SizedBox(width: 6),
                  Text(
                    entry.key,
                    style: AppTypography.caption.copyWith(
                      color: passed ? AppColors.textPrimary : AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDecisionCard(SellerApplication app) {
    final isPending = app.status == 'pending';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(
          color: isPending
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.border,
          width: isPending ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.gavel_rounded,
                size: 20,
                color: isPending ? AppColors.primary : AppColors.textSecondary,
              ),
              SizedBox(width: 8),
              Text('Verification Decision', style: AppTypography.sectionTitle),
            ],
          ),
          const SizedBox(height: 12),
          if (isPending) ...[
            Text(
              'Review the applicant credentials, government ID, and face verification above before taking action.',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _approve,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Approve Seller Application'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: AppTypography.button,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : _reject,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Reject Application'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: AppTypography.button.copyWith(
                  color: AppColors.error,
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: app.status == 'approved'
                    ? AppColors.success.withValues(alpha: 0.08)
                    : AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                border: Border.all(
                  color: app.status == 'approved'
                      ? AppColors.success.withValues(alpha: 0.25)
                      : AppColors.error.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        app.status == 'approved'
                            ? Icons.check_circle
                            : Icons.cancel,
                        color: app.status == 'approved'
                            ? AppColors.success
                            : AppColors.error,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        app.status == 'approved'
                            ? 'This seller was approved'
                            : 'This application was rejected',
                        style: AppTypography.cardTitle.copyWith(
                          color: app.status == 'approved'
                              ? AppColors.success
                              : AppColors.error,
                        ),
                      ),
                    ],
                  ),
                  if (app.status == 'rejected' &&
                      (app.rejectionReason?.trim().isNotEmpty ?? false)) ...[
                    SizedBox(height: 8),
                    Text(
                      'Rejection Reason:',
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.rejectionReason!.trim(),
                      style: AppTypography.body.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _showIdBack(SellerApplication app) {
    if (_idBackUrl?.trim().isNotEmpty == true) return true;
    final type = SellerIdType.tryParse(app.idType);
    return type == null || type.requiresBackCapture;
  }
}

// ============================================================================
// HELPER SUBWIDGETS
// ============================================================================

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: AppTypography.sectionTitle)),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items});

  final List<_InfoGridItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 480;
        return Wrap(
          spacing: 16,
          runSpacing: 14,
          children: items.map((item) {
            final width = isWide
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.value,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (item.copyable) ...[
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: item.value));
                            showThriftSnackBar(context, 'Copied to clipboard');
                          },
                          child: const Icon(
                            Icons.copy,
                            size: 14,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _InfoGridItem {
  const _InfoGridItem({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;
}

class _DocumentPreviewCard extends StatelessWidget {
  const _DocumentPreviewCard({
    required this.label,
    required this.url,
    required this.onTap,
  });

  final String label;
  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.isNotEmpty;

    return InkWell(
      onTap: hasUrl ? onTap : null,
      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 120,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppConstants.radiusSm - 1),
                ),
              ),
              child: hasUrl
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: url!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          errorWidget: (_, _, _) => Icon(
                            Icons.broken_image,
                            size: 32,
                            color: AppColors.textHint,
                          ),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.zoom_in,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Icon(
                        Icons.image_not_supported,
                        size: 32,
                        color: AppColors.textHint,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
