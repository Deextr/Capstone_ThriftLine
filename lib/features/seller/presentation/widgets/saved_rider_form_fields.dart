import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../../../../models/enums.dart';
import '../../../../widgets/thrift_widgets.dart';

class SavedRiderFormFields extends StatelessWidget {
  const SavedRiderFormFields({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.plateController,
    required this.notesController,
    required this.vehicle,
    required this.onVehicleChanged,
    this.nameError,
    this.phoneError,
    this.plateError,
    this.readOnly = false,
    this.showDefaultNotes = true,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController plateController;
  final TextEditingController notesController;
  final DeliveryVehicleType vehicle;
  final ValueChanged<DeliveryVehicleType> onVehicleChanged;
  final String? nameError;
  final String? phoneError;
  final String? plateError;
  final bool readOnly;
  final bool showDefaultNotes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThriftTextField(
          label: 'Rider name',
          hint: 'Juan Dela Cruz',
          controller: nameController,
          error: nameError,
          readOnly: readOnly,
          inputFormatters: [
            FilteringTextInputFormatter.allow(
              Validators.fullNameInputCharacters,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'Phone number',
          hint: '09171234567',
          controller: phoneController,
          keyboardType: TextInputType.phone,
          error: phoneError,
          readOnly: readOnly,
        ),
        const SizedBox(height: 12),
        Text('Vehicle type', style: AppTypography.label),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in DeliveryVehicleType.values)
              ChoiceChip(
                label: Text(v.label),
                selected: vehicle == v,
                selectedColor: AppColors.primaryLight,
                onSelected: readOnly ? null : (_) => onVehicleChanged(v),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ThriftTextField(
          label: 'Plate number',
          hint: 'ABC 1234',
          controller: plateController,
          error: plateError,
          readOnly: readOnly,
        ),
        if (showDefaultNotes) ...[
          const SizedBox(height: 12),
          ThriftTextField(
            label: 'Default delivery notes (optional)',
            hint: 'Meet at the gate, call on arrival…',
            controller: notesController,
            maxLines: 3,
            readOnly: readOnly,
          ),
        ],
      ],
    );
  }
}
