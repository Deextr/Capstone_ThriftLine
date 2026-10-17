const int productDescriptionMinLength = 20;
const int productDescriptionMaxLength = 2000;

const String productDescriptionRequiredMessage = 'Description is required.';

const String productDescriptionTooShortMessage =
    'Description must be at least 20 characters';

const String productDescriptionTooLongMessage =
    'Description cannot exceed 2,000 characters';

/// Validates seller listing description (trimmed length 20–2000).
String? productDescriptionError(String? value) {
  final trimmed = (value ?? '').trim();
  if (trimmed.isEmpty) return productDescriptionRequiredMessage;
  if (trimmed.length < productDescriptionMinLength) {
    return productDescriptionTooShortMessage;
  }
  if (trimmed.length > productDescriptionMaxLength) {
    return productDescriptionTooLongMessage;
  }
  return null;
}
