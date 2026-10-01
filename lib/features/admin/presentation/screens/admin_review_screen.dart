import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../seller/domain/seller_id_type.dart';
import '../../../seller/domain/external_selling.dart';
import '../../data/admin_review_rules.dart';
import '../../data/admin_verification_service.dart';
import '../../data/external_history_service.dart';
import '../widgets/admin_review_widgets.dart';
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
          _error = 'Unable to load this application.';
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
            ? 'Seller approved. They can start listing.'
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
            hintText: 'Only other admins see this',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
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
      showThriftSnackBar(context, 'External transaction updated.');
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
          'They will be able to list items. This does not change payments or trust score.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Keep pending'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Approve seller'),
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

  @override
  Widget build(BuildContext context) {
    final app = _application;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Seller application'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const AdminDetailSkeleton()
            : _error != null
            ? AdminErrorState(message: _error!, onRetry: _load)
            : app == null
            ? const AdminEmptyState(
                title: 'This application is no longer available.',
                message: 'It may already have been removed.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  AdminStatusChip(
                    status: app.status,
                    label: verificationStatusLabel(app.status),
                  ),
                  const SizedBox(height: 12),
                  Text(app.shopName, style: AppTypography.heading),
                  const SizedBox(height: 4),
                  Text(
                    app.applicantName ?? 'Applicant',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      app.shopAddress,
                      app.barangay,
                      app.city,
                    ].where((part) => part.trim().isNotEmpty).join(', '),
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: 28),
                  AdminDetailBlock(
                    label: 'Identity',
                    children: [
                      if (SellerIdType.tryParse(app.idType) case final idType?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(idType.label, style: AppTypography.body),
                        ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          AdminPhotoThumb(label: 'ID front', url: _idUrl),
                          if (_showIdBack(app))
                            AdminPhotoThumb(label: 'ID back', url: _idBackUrl),
                          AdminPhotoThumb(label: 'Selfie', url: _selfieUrl),
                        ],
                      ),
                    ],
                  ),
                  AdminDetailBlock(
                    label: 'Liveness checks',
                    children: [_LivenessChips(result: app.livenessResult)],
                  ),
                  ExternalSellingHistorySection(
                    claimedRange: app.claimedSellingRange,
                    items: _history,
                    busy: _busy,
                    onReview: _reviewExternal,
                  ),
                  if (app.status == 'pending')
                    AdminDecisionSection(
                      title: 'Decision',
                      children: [
                        ThriftButton(
                          label: 'Approve seller',
                          isLoading: _busy,
                          onPressed: _busy ? null : _approve,
                        ),
                        const SizedBox(height: 4),
                        ThriftButton(
                          label: 'Reject application',
                          variant: ThriftButtonVariant.ghost,
                          color: AppColors.error,
                          onPressed: _busy ? null : _reject,
                        ),
                      ],
                    )
                  else
                    AdminDetailBlock(
                      label: 'Decision',
                      children: [
                        Text(
                          app.status == 'rejected'
                              ? (app.rejectionReason?.trim().isNotEmpty == true
                                    ? app.rejectionReason!.trim()
                                    : 'This application was rejected.')
                              : 'This application was approved.',
                          style: AppTypography.body,
                        ),
                      ],
                    ),
                ],
              ),
      ),
    );
  }

  bool _showIdBack(SellerApplication app) {
    if (_idBackUrl?.trim().isNotEmpty == true) return true;
    final type = SellerIdType.tryParse(app.idType);
    return type == null || type.requiresBackCapture;
  }
}

class _LivenessChips extends StatelessWidget {
  const _LivenessChips({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final items = {
      'Face': result['face'] == true,
      'Look right': result['lookRight'] == true,
      'Look left': result['lookLeft'] == true,
      'Blink': result['blink'] == true,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.entries
          .map(
            (entry) => ThriftBadge(
              label: entry.value
                  ? '${entry.key} passed'
                  : '${entry.key} not passed',
              variant: entry.value ? BadgeVariant.success : BadgeVariant.error,
            ),
          )
          .toList(),
    );
  }
}
