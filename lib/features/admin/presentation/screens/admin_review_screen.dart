import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/admin_review_rules.dart';
import '../../data/admin_verification_service.dart';
import '../widgets/admin_review_widgets.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({super.key, required this.verificationId});

  final String verificationId;

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  late final AdminVerificationService _service;
  SellerApplication? _application;
  String? _idUrl;
  String? _idBackUrl;
  String? _selfieUrl;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = AdminVerificationService(context.read<SupabaseService>());
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
      if (!mounted) return;
      setState(() {
        _application = match;
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
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _review('approved');
  }

  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Reject application'),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Tell the applicant what to fix.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      reasonCtrl.dispose();
      return;
    }
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (reason.isEmpty) {
      showThriftSnackBar(
        context,
        'A rejection reason is required.',
        isError: true,
      );
      return;
    }
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
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? AdminErrorState(message: _error!, onRetry: _load)
            : app == null
            ? const AdminEmptyState(
                title: 'This application is no longer pending.',
                message: 'It may already have been approved or rejected.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
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
                    style: AppTypography.body,
                  ),
                  Text(
                    [
                      app.shopAddress,
                      app.barangay,
                      app.city,
                    ].where((part) => part.trim().isNotEmpty).join(', '),
                    style: AppTypography.caption,
                  ),
                  const SizedBox(height: 24),
                  AdminDetailBlock(
                    label: 'Liveness checks',
                    children: [_LivenessChips(result: app.livenessResult)],
                  ),
                  AdminDetailBlock(
                    label: 'Government ID',
                    children: [
                      Text('Front', style: AppTypography.caption),
                      const SizedBox(height: 6),
                      _DocImage(url: _idUrl),
                      const SizedBox(height: 12),
                      Text('Back', style: AppTypography.caption),
                      const SizedBox(height: 6),
                      _DocImage(url: _idBackUrl),
                    ],
                  ),
                  AdminDetailBlock(
                    label: 'Liveness face photo',
                    children: [_DocImage(url: _selfieUrl)],
                  ),
                  ThriftButton(
                    label: 'Approve seller',
                    isLoading: _busy,
                    onPressed: _busy ? null : _approve,
                  ),
                  const SizedBox(height: 12),
                  ThriftButton(
                    label: 'Reject',
                    variant: ThriftButtonVariant.outline,
                    color: AppColors.error,
                    onPressed: _busy ? null : _reject,
                  ),
                ],
              ),
      ),
    );
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
              label: entry.key,
              variant: entry.value ? BadgeVariant.success : BadgeVariant.error,
            ),
          )
          .toList(),
    );
  }
}

class _DocImage extends StatelessWidget {
  const _DocImage({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('No image uploaded', style: AppTypography.caption),
      );
    }
    return Semantics(
      button: true,
      label: 'Open identity document',
      child: GestureDetector(
        onTap: () => showAdminImagePreview(context, url!),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            url!,
            height: 220,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
