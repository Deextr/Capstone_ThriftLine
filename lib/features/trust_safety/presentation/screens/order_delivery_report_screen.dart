import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../controllers/order_delivery_report_controller.dart';
import '../../data/report_reasons.dart';
import '../widgets/report_evidence_section.dart';

class OrderDeliveryReportScreen extends StatefulWidget {
  const OrderDeliveryReportScreen({super.key});

  @override
  State<OrderDeliveryReportScreen> createState() =>
      _OrderDeliveryReportScreenState();
}

class _OrderDeliveryReportScreenState extends State<OrderDeliveryReportScreen> {
  late final TextEditingController _details;

  @override
  void initState() {
    super.initState();
    _details = TextEditingController();
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<OrderDeliveryReportController>();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('Report a problem'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: controller.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : controller.errorMessage != null && controller.order == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      controller.errorMessage!,
                      textAlign: TextAlign.center,
                      style: AppTypography.body,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        children: [
                          Text(
                            'Tell us what went wrong',
                            style: AppTypography.heading.copyWith(fontSize: 22),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Order #${controller.order?.orderNumber ?? '—'} · '
                            '${controller.order?.productTitle ?? ''}',
                            style: AppTypography.body.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your report is private. Escrow stays protected while we review.',
                            style: AppTypography.caption,
                          ),
                          const SizedBox(height: 20),
                          Text('Reason', style: AppTypography.subheading),
                          const SizedBox(height: 10),
                          ...DeliveryDisputeReason.values.map(
                            (reason) => _ReasonTile(
                              label: reason.label,
                              selected: controller.reason == reason,
                              onTap: () => context
                                  .read<OrderDeliveryReportController>()
                                  .selectReason(reason),
                            ),
                          ),
                          const SizedBox(height: 20),
                          ThriftTextField(
                            label: 'Description',
                            hint: 'Describe the issue with your order…',
                            controller: _details,
                            maxLines: 5,
                            maxLength: kReportDetailsMaxLength,
                            onChanged: context
                                .read<OrderDeliveryReportController>()
                                .setDetails,
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${controller.details.length}/$kReportDetailsMaxLength',
                              style: AppTypography.caption,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ReportEvidenceSection(
                            evidence: controller.evidence,
                            evidenceError: controller.evidenceError,
                            required: true,
                            onAddGallery: () => context
                                .read<OrderDeliveryReportController>()
                                .addEvidenceFromGallery(),
                            onAddCamera: () => context
                                .read<OrderDeliveryReportController>()
                                .addEvidenceFromCamera(),
                            onRemove: (i) => context
                                .read<OrderDeliveryReportController>()
                                .removeEvidence(i),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomInset),
                      child: ThriftButton(
                        label: 'Submit report',
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
    final result = await context.read<OrderDeliveryReportController>().submit();
    if (!context.mounted) return;
    if (result.error != null) {
      showThriftSnackBar(context, result.error!, isError: true);
      if (result.reportId != null) {
        context.pushReplacement(RouteNames.reportDetailFor(result.reportId!));
      }
      return;
    }
    showThriftSnackBar(
      context,
      'Report submitted. Our team will review it under My Reports.',
    );
    context.pushReplacement(RouteNames.myReports);
  }
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
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
      child: Material(
        color: selected ? AppColors.primaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
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
