import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/report_user_controller.dart';
import '../../data/report_reasons.dart';
import '../widgets/report_evidence_section.dart';

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
        resizeToAvoidBottomInset: true,
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                            showThriftSnackBar(context, error, isError: true);
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
                        selected: controller.selectedCategory == reason.slug,
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
                      maxLength: kReportDetailsMaxLength,
                      onChanged: controller.setDetails,
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${controller.details.length}/$kReportDetailsMaxLength',
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
                    ReportEvidenceSection(
                      evidence: controller.evidence,
                      evidenceError: controller.evidenceError,
                      required: true,
                      onAddGallery: () => context
                          .read<ReportUserController>()
                          .addEvidenceFromGallery(),
                      onAddCamera: () => context
                          .read<ReportUserController>()
                          .addEvidenceFromCamera(),
                      onRemove: (i) => context
                          .read<ReportUserController>()
                          .removeEvidence(i),
                    ),
                    const SizedBox(height: 24),
                    ThriftButton(
                      label: 'Submit Report',
                      loadingLabel: 'Submitting Report...',
                      color: AppColors.error,
                      isLoading: controller.isSubmitting,
                      onPressed: controller.canSubmit
                          ? () => _submit(context)
                          : null,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    final reportController = context.read<ReportUserController>();
    if (reportController.isSubmitting) return;
    final error = await reportController.submit();
    if (!context.mounted) return;
    if (error != null) {
      showThriftSnackBar(context, error, isError: true);
      return;
    }
    showThriftSnackBar(
      context,
      'Report submitted. You can track it under My Reports.',
    );
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
                      Text(
                        reason.description,
                        style: AppTypography.caption,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
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
