import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../data/admin_verification_service.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  late final AdminVerificationService _service;
  List<SellerApplication> _pending = const [];
  bool _loading = true;
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
      final items = await _service.listPending();
      if (!mounted) return;
      setState(() {
        _pending = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load pending applications.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seller reviews'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              await auth.logout();
              if (context.mounted) {
                context.go(RouteNames.login);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Signed in as ${auth.user?.name ?? 'Admin'}',
                style: AppTypography.caption,
              ),
              const SizedBox(height: 8),
              Text(
                'Review government IDs and face checks before a buyer can sell.',
                style: AppTypography.body.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Column(
                    children: [
                      Text(_error!, style: AppTypography.body),
                      const SizedBox(height: 12),
                      ThriftButton(label: 'Try again', onPressed: _load),
                    ],
                  ),
                )
              else if (_pending.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(child: Text('No pending seller applications.')),
                )
              else
                ..._pending.map(
                  (app) => _PendingCard(
                    application: app,
                    onReviewed: _load,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.application,
    required this.onReviewed,
  });
  final SellerApplication application;
  final Future<void> Function() onReviewed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ThriftCard(
        onTap: () async {
          await context.push('/admin/review/${application.id}');
          if (context.mounted) await onReviewed();
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    application.shopName,
                    style: AppTypography.subheading,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    application.applicantName ?? 'Applicant',
                    style: AppTypography.body,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${application.barangay}, ${application.city}',
                    style: AppTypography.caption,
                  ),
                  Text(
                    'Submitted ${formatRelativeTime(application.submittedAt)}',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
