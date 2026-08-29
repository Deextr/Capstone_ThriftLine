import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../../seller/domain/seller_id_type.dart';
import '../../data/admin_verification_service.dart';

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

  @override
  void initState() {
    super.initState();
    _service = AdminVerificationService(context.read<SupabaseService>());
    _load();
  }

  Future<void> _load() async {
    try {
      final match = await _service.getById(widget.verificationId);
      if (match == null) {
        if (mounted) setState(() => _loading = false);
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
      if (mounted) setState(() => _loading = false);
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
          'Could not save that decision. Try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      showThriftSnackBar(context, 'A rejection reason is required.', isError: true);
      return;
    }
    await _review('rejected', reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final app = _application;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review application'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : app == null
                ? const Center(child: Text('This application is no longer pending.'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(app.shopName, style: AppTypography.heading),
                      const SizedBox(height: 4),
                      Text(
                        app.applicantName ?? 'Applicant',
                        style: AppTypography.body,
                      ),
                      Text(
                        '${app.shopAddress}, ${app.barangay}, ${app.city}',
                        style: AppTypography.caption,
                      ),
                      const SizedBox(height: 16),
                      _LivenessChips(result: app.livenessResult),
                      const SizedBox(height: 20),
                      Text(
                        () {
                          final label = SellerIdType.tryParse(app.idType)?.label;
                          return label == null
                              ? 'Government ID'
                              : 'Government ID ($label)';
                        }(),
                        style: AppTypography.subheading,
                      ),
                      const SizedBox(height: 8),
                      Text('Front', style: AppTypography.caption),
                      const SizedBox(height: 6),
                      _DocImage(url: _idUrl),
                      const SizedBox(height: 12),
                      Text('Back', style: AppTypography.caption),
                      const SizedBox(height: 6),
                      _DocImage(url: _idBackUrl),
                      const SizedBox(height: 20),
                      Text('Liveness face photo', style: AppTypography.subheading),
                      const SizedBox(height: 8),
                      _DocImage(url: _selfieUrl),
                      const SizedBox(height: 24),
                      ThriftButton(
                        label: 'Approve seller',
                        isLoading: _busy,
                        onPressed: _busy ? null : () => _review('approved'),
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
            (entry) => Chip(
              label: Text(entry.key),
              avatar: Icon(
                entry.value ? Icons.check_circle : Icons.cancel,
                size: 16,
                color: entry.value ? AppColors.success : AppColors.error,
              ),
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
        child: const Text('No image uploaded'),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url!,
        height: 220,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }
}
