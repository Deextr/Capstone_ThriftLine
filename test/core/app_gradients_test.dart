import 'package:flutter_test/flutter_test.dart';
import 'package:thriftline/core/constants/app_colors.dart';
import 'package:thriftline/core/theme/app_gradients.dart';

void main() {
  test('shared gradients stay on the ThriftLine teal', () {
    expect(AppGradients.primaryGradient.colors, contains(AppColors.primary));
    expect(AppGradients.buttonGradient.colors.first, AppColors.primaryDark);
    expect(AppGradients.heroGradient.colors, contains(AppColors.primary));
    expect(
      AppGradients.primaryGradientLight.colors.first,
      AppColors.primaryLight,
    );
  });
}
