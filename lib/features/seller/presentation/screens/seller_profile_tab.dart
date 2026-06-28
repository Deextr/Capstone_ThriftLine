import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/routes/route_names.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../providers/data_provider.dart';
import '../../../../widgets/product_card.dart';
import '../../../../widgets/thrift_widgets.dart';

class SellerProfileTab extends StatelessWidget {
  const SellerProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final data = context.watch<DataProvider>();
    final user = AuthService().getUserByUsername(auth.username ?? '');
    final products = data.productsForSeller(auth.username ?? '').take(6).toList();

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        children: [
          Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark]),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -40),
            child: Column(
              children: [
                ThriftAvatar(imageUrl: user?.avatarUrl ?? '', size: 80),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(user?.shopName ?? '', style: AppTypography.heading),
                    if (user?.isVerified == true) const Icon(Icons.verified, color: AppColors.primary),
                  ],
                ),
                Text('⭐ ${user?.rating ?? 4.8} • ${user?.sales ?? 0} sales', style: AppTypography.caption),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _stat('128', 'Followers'),
                    const SizedBox(width: 24),
                    _stat('45', 'Following'),
                    const SizedBox(width: 24),
                    _stat('${user?.sales ?? 0}', 'Sales'),
                  ],
                ),
                const SizedBox(height: 12),
                ThriftButton(label: 'Edit Shop', variant: ThriftButtonVariant.outline, expand: false, onPressed: () {}),
              ],
            ),
          ),
          Text('Curated vintage and Y2K fashion finds.', style: AppTypography.body, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: ['Vintage', 'Y2K', 'Tops', 'Denim'].map((t) => ThriftBadge(label: t)).toList(),
          ),
          const SizedBox(height: 24),
          Text('Active Listings', style: AppTypography.subheading),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.52),
            itemCount: products.length,
            itemBuilder: (_, i) => ProductCard(product: products[i], onTap: () => context.push('/product/${products[i].id}')),
          ),
          const SizedBox(height: 24),
          _menu(context, 'Shop Details', () {}),
          _menu(context, 'Payment Details', () {}),
          _menu(context, 'Shipping Preferences', () {}),
          SwitchListTile(title: const Text('Vacation Mode'), value: false, onChanged: (_) {}),
          _menu(context, 'Seller Guidelines', () {}),
          _menu(context, 'Help Center', () {}),
          const SizedBox(height: 16),
          ThriftButton(
            label: 'Logout',
            variant: ThriftButtonVariant.ghost,
            color: AppColors.error,
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go(RouteNames.login);
            },
          ),
        ],
      ),
    );
  }

  Widget _stat(String v, String l) => Column(children: [Text(v, style: AppTypography.subheading), Text(l, style: AppTypography.caption)]);
  Widget _menu(BuildContext context, String title, VoidCallback onTap) => ListTile(title: Text(title), trailing: const Icon(Icons.chevron_right), onTap: onTap);
}
