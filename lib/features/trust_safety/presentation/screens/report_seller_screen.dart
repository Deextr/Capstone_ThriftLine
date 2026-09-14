import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/report_user_controller.dart';
import '../../data/report_reasons.dart';

class ReportSellerScreen extends StatefulWidget {
  const ReportSellerScreen({super.key});

  @override
  State<ReportSellerScreen> createState() => _ReportSellerScreenState();
}

class _ReportSellerScreenState extends State<ReportSellerScreen> {
  late final TextEditingController _username;
  late final TextEditingController _details;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController();
    _details = TextEditingController();
  }

  @override
  void dispose() {
    _username.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportUserController>();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Report a member'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: controller.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        children: [
                          Text(
                            'Tell us what happened',
                            style: AppTypography.heading.copyWith(fontSize: 22),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Reports stay private. The other person will not see this.',
                            style: AppTypography.body.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (controller.hasResolvedTarget)
                            _TargetRow(controller: controller)
                          else ...[
                            ThriftTextField(
                              label: 'Username',
                              hint: '@username',
                              controller: _username,
                              icon: Icons.alternate_email,
                              onChanged: controller.setUsernameQuery,
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () async {
                                  final error = await context
                                      .read<ReportUserController>()
                                      .resolveUsername();
                                  if (!context.mounted || error == null) {
                                    return;
                                  }
                                  showThriftSnackBar(
                                    context,
                                    error,
                                    isError: true,
                                  );
                                },
                                child: const Text('Find member'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Text('Reason', style: AppTypography.subheading),
                          const SizedBox(height: 10),
                          ...kReportReasons.map(
                            (reason) => _ReasonTile(
                              reason: reason,
                              selected:
                                  controller.selectedCategory == reason.slug,
                              onTap: () => context
                                  .read<ReportUserController>()
                                  .selectCategory(reason.slug),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ThriftTextField(
                            label: 'Details',
                            hint: 'Describe what happened...',
                            controller: _details,
                            maxLines: 5,
                            onChanged: controller.setDetails,
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${controller.details.trim().length}/$kReportDetailsMaxLength',
                              style: AppTypography.caption,
                            ),
                          ),
                          if (controller.orders.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Text(
                              'Related order (optional)',
                              style: AppTypography.subheading,
                            ),
                            const SizedBox(height: 10),
                            _OrderPicker(controller: controller),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            'Photo evidence (optional)',
                            style: AppTypography.subheading,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Up to 4 photos. JPG, PNG, or WebP. 5 MB each.',
                            style: AppTypography.caption,
                          ),
                          const SizedBox(height: 12),
                          _EvidenceRow(controller: controller),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: ThriftButton(
                        label: 'Submit Report',
                        color: AppColors.error,
                        isLoading: controller.isSubmitting,
                        onPressed: controller.canSubmit
                            ? () => _submit(context)
                            : null,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final error = await context.read<ReportUserController>().submit();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(context, 'Report submitted');
    context.pushReplacement(RouteNames.myReports);
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.controller});

  final ReportUserController controller;

  @override
  Widget build(BuildContext context) {
    final username = controller.reportedUsername;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.reportedDisplayName ?? 'Member',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (username != null && username.isNotEmpty)
                  Text('@$username', style: AppTypography.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final ReportReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.primaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  reason.icon,
                  size: 20,
                  color: selected
                      ? AppColors.primaryDark
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reason.label,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(reason.description, style: AppTypography.caption),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.textHint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderPicker extends StatelessWidget {
  const _OrderPicker({required this.controller});

  final ReportUserController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OrderOption(
          label: 'No related order',
          selected: controller.linkedOrderId == null,
          onTap: () =>
              context.read<ReportUserController>().setLinkedOrder(null),
        ),
        for (final order in controller.orders)
          _OrderOption(
            label: '#${order.orderNumber} · ${order.title}',
            selected: controller.linkedOrderId == order.id,
            onTap: () =>
                context.read<ReportUserController>().setLinkedOrder(order.id),
          ),
      ],
    );
  }
}

class _OrderOption extends StatelessWidget {
  const _OrderOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.controller});

  final ReportUserController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < controller.evidence.length; i++)
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  controller.evidence[i].bytes,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: IconButton.filled(
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.textPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(24, 24),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  iconSize: 14,
                  onPressed: () =>
                      context.read<ReportUserController>().removeEvidence(i),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        if (controller.evidence.length < kReportEvidenceMaxCount)
          InkWell(
            onTap: () async {
              final error = await context
                  .read<ReportUserController>()
                  .addEvidence();
              if (!context.mounted || error == null) return;
              showThriftSnackBar(context, error, isError: true);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.add_a_photo_outlined, size: 22),
            ),
          ),
      ],
    );
  }
}
