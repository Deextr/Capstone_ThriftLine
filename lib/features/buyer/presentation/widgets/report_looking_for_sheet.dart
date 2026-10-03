import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../widgets/thrift_widgets.dart';
import '../../domain/looking_for_lifecycle.dart';

class ReportLookingForSheet extends StatefulWidget {
  const ReportLookingForSheet({super.key});

  static Future<({String reason, String details})?> show(BuildContext context) {
    return showModalBottomSheet<({String reason, String details})>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const ReportLookingForSheet(),
    );
  }

  @override
  State<ReportLookingForSheet> createState() => _ReportLookingForSheetState();
}

class _ReportLookingForSheetState extends State<ReportLookingForSheet> {
  String _reason = lookingForReportReasons.first.value;
  final _details = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  void _submit() {
    final error = lookingForReportDetailsError(
      reason: _reason,
      details: _details.text,
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop((reason: _reason, details: _details.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Report request', style: AppTypography.heading),
            const SizedBox(height: 4),
            Text(
              'An admin reviews this. The request stays up until then.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            for (final reason in lookingForReportReasons)
              InkWell(
                onTap: () => setState(() {
                  _reason = reason.value;
                  _error = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _reason == reason.value
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                        color: _reason == reason.value
                            ? AppColors.primary
                            : AppColors.textHint,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(reason.label, style: AppTypography.body),
                      ),
                    ],
                  ),
                ),
              ),
            if (_reason == 'other') ...[
              const SizedBox(height: 4),
              TextField(
                controller: _details,
                minLines: 2,
                maxLines: 4,
                maxLength: lookingForReportDetailsMax,
                decoration: const InputDecoration(
                  labelText: 'What should we look at?',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTypography.caption.copyWith(color: AppColors.error),
              ),
            ],
            const SizedBox(height: 16),
            ThriftButton(label: 'Submit report', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}
