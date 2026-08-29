import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../core/routes/route_names.dart';
import '../providers/auth_provider.dart';
import 'thrift_widgets.dart';

class ThriftDrawer extends StatelessWidget {
  const ThriftDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    final name = (user != null && user.name.isNotEmpty) ? user.name : 'Maya Lin';
    final userUsername = user?.username;
    final username = (userUsername != null && userUsername.isNotEmpty) ? userUsername : 'maya_thrift';
    final userEmail = user?.email;
    final email = (userEmail != null && userEmail.isNotEmpty) ? userEmail : 'maya@thriftline.app';
    final avatarUrl = user?.avatarUrl ?? '';
    final isSeller = auth.isSeller;
    final rating = user?.rating ?? 4.9;

    return Drawer(
      backgroundColor: AppColors.background,
      elevation: 16,
      child: Column(
        children: [
          // ─────────────────────────────────────────────────────────────────
          // Mini Profile Snippet Header
          // ─────────────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryDark,
                  AppColors.primary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // User Avatar
                      ThriftAvatar(
                        imageUrl: avatarUrl,
                        name: name,
                        size: 56,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: AppTypography.heading.copyWith(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '@$username • $email',
                              style: AppTypography.caption.copyWith(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            // Role Badge & Rating
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isSeller ? 'Verified Seller' : 'Verified Buyer',
                                    style: AppTypography.caption.copyWith(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.star_rounded,
                                    size: 13, color: Color(0xFFFFD166)),
                                const SizedBox(width: 2),
                                Text(
                                  rating.toStringAsFixed(1),
                                  style: AppTypography.caption.copyWith(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Quick link to edit/view profile
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      context.push(RouteNames.editProfile);
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_outline_rounded,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'View Full Profile',
                            style: AppTypography.label.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.chevron_right_rounded,
                              color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ─────────────────────────────────────────────────────────────────
          // Drawer Navigation Items
          // ─────────────────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              children: [
                // 1. Home
                _DrawerItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.go(auth.homeRoute);
                  },
                ),

                // 2. My Activity
                _DrawerItem(
                  icon: Icons.history_rounded,
                  label: 'My Activity',
                  badgeText: 'Orders & Bids',
                  onTap: () {
                    Navigator.of(context).pop();
                    context.push(RouteNames.purchaseHistory);
                  },
                ),

                if (auth.isAdmin)
                  _DrawerItem(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Seller reviews',
                    badgeText: 'Admin',
                    onTap: () {
                      Navigator.of(context).pop();
                      context.go(RouteNames.adminHome);
                    },
                  ),

                // 3. Seller Dashboard
                _DrawerItem(
                  icon: Icons.storefront_rounded,
                  label: 'Seller Dashboard',
                  badgeColor: isSeller ? AppColors.primary : AppColors.secondary,
                  badgeText: isSeller ? 'Active' : 'Start Selling',
                  onTap: () {
                    Navigator.of(context).pop();
                    if (isSeller) {
                      context.go(RouteNames.sellerHome);
                    } else {
                      context.push(RouteNames.becomeSeller);
                    }
                  },
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(color: AppColors.border, height: 1),
                ),

                // 4. Help / Support / FAQ
                _DrawerItem(
                  icon: Icons.help_outline_rounded,
                  label: 'Help / Support / FAQ',
                  onTap: () {
                    Navigator.of(context).pop();
                    _showHelpSupportModal(context);
                  },
                ),

                // 5. Terms & Privacy
                _DrawerItem(
                  icon: Icons.gavel_rounded,
                  label: 'Terms & Privacy',
                  onTap: () {
                    Navigator.of(context).pop();
                    _showTermsPrivacyModal(context);
                  },
                ),

                // 6. About ThriftLine
                _DrawerItem(
                  icon: Icons.info_outline_rounded,
                  label: 'About ThriftLine',
                  onTap: () {
                    Navigator.of(context).pop();
                    _showAboutThriftLineModal(context);
                  },
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Divider(color: AppColors.border, height: 1),
                ),

                // 7. Log Out
                _DrawerItem(
                  icon: Icons.logout_rounded,
                  label: 'Log Out',
                  isDestructive: true,
                  onTap: () => _confirmLogout(context, auth),
                ),
              ],
            ),
          ),

          // Drawer Footer Version Tag
          Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            child: Text(
              'ThriftLine v1.0.0 • Peer-to-Peer Thrift Marketplace',
              style: AppTypography.caption.copyWith(
                fontSize: 11,
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Logout Confirmation Dialog
  // ───────────────────────────────────────────────────────────────────────────
  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: AppColors.error),
            const SizedBox(width: 10),
            Text('Log Out', style: AppTypography.heading),
          ],
        ),
        content: Text(
          'Are you sure you want to log out of your ThriftLine account?',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(
              'Cancel',
              style: AppTypography.label.copyWith(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              Navigator.of(context).pop(); // Close drawer if open
              await auth.logout();
              if (context.mounted) {
                context.go(RouteNames.login);
              }
            },
            child: Text(
              'Log Out',
              style: AppTypography.label.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Help / Support / FAQ Bottom Sheet
  // ───────────────────────────────────────────────────────────────────────────
  void _showHelpSupportModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _HelpSupportSheet(),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Terms & Privacy Bottom Sheet
  // ───────────────────────────────────────────────────────────────────────────
  void _showTermsPrivacyModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TermsPrivacySheet(),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // About ThriftLine Bottom Sheet
  // ───────────────────────────────────────────────────────────────────────────
  void _showAboutThriftLineModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AboutThriftLineSheet(),
    );
  }
}

// =============================================================================
// Helper Drawer Item Tile
// =============================================================================

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeText,
    this.badgeColor,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badgeText;
  final Color? badgeColor;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.body.copyWith(
                      color: color,
                      fontWeight: isDestructive ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 14.5,
                    ),
                  ),
                ),
                if (badgeText != null) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? AppColors.primary).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badgeText!,
                      style: AppTypography.caption.copyWith(
                        color: badgeColor ?? AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDestructive
                      ? AppColors.error.withValues(alpha: 0.6)
                      : AppColors.textHint,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Help / Support / FAQ Sheet
// =============================================================================

class _HelpSupportSheet extends StatefulWidget {
  const _HelpSupportSheet();

  @override
  State<_HelpSupportSheet> createState() => _HelpSupportSheetState();
}

class _HelpSupportSheetState extends State<_HelpSupportSheet> {
  final List<Map<String, String>> _faqs = [
    {
      'q': 'How does bidding & buying work on ThriftLine?',
      'a': 'You can buy items directly via "Buy Now" or place real-time bids on auction listings. Winning bidders receive payment instructions directly from verified sellers.'
    },
    {
      'q': 'Is my payment protected?',
      'a': 'Yes! ThriftLine holds funds safely until buyer confirmation or trackable delivery validation. Trust & Safety measures protect all genuine transactions.'
    },
    {
      'q': 'How do I become a verified seller?',
      'a': 'Head to the Seller Dashboard in the side drawer, upload your valid ID proof & GCash payout details, and submit for instant verification.'
    },
    {
      'q': 'What should I do if an item is fake or not as described?',
      'a': 'Go to My Activity -> Select Order -> Tap "Report Item". Our Trust & Safety team will review and resolve issues within 24 hours.'
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle & title header
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.help_outline_rounded, color: AppColors.primary, size: 26),
                const SizedBox(width: 10),
                Text('Help, Support & FAQ', style: AppTypography.heading),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Quick contact options banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.support_agent_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Need Immediate Assistance?',
                              style: AppTypography.subheading.copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Our 24/7 support team is here to assist with orders and payments.',
                              style: AppTypography.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Frequently Asked Questions', style: AppTypography.subheading),
                const SizedBox(height: 12),
                ..._faqs.map(
                  (faq) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ExpansionTile(
                      shape: const RoundedRectangleBorder(),
                      tilePadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      title: Text(
                        faq['q']!,
                        style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600, fontSize: 13.5),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          child: Text(
                            faq['a']!,
                            style: AppTypography.caption.copyWith(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ThriftButton(
                    label: 'Contact Live Support (24/7)',
                    icon: Icons.chat_outlined,
                    onPressed: () {
                      Navigator.of(context).pop();
                      showThriftSnackBar(context, 'Connecting to Live Support agent...');
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Terms & Privacy Sheet
// =============================================================================

class _TermsPrivacySheet extends StatelessWidget {
  const _TermsPrivacySheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.gavel_rounded, color: AppColors.primary, size: 24),
                const SizedBox(width: 10),
                Text('Terms & Privacy Policy', style: AppTypography.heading),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1. Terms of Service', style: AppTypography.subheading),
                  const SizedBox(height: 8),
                  Text(
                    'Welcome to ThriftLine. By accessing or using our peer-to-peer thrifting platform, you agree to comply with our community guidelines, authentic listing rules, and buyer protection policies.',
                    style: AppTypography.body.copyWith(color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Text('2. Seller Obligations', style: AppTypography.subheading),
                  const SizedBox(height: 8),
                  Text(
                    'Sellers must provide accurate descriptions, high-resolution original photos, and process orders promptly. Counterfeit or mislabeled items will lead to account suspension.',
                    style: AppTypography.body.copyWith(color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Text('3. Privacy & Security', style: AppTypography.subheading),
                  const SizedBox(height: 8),
                  Text(
                    'We safeguard your personal details, shipping addresses, and GCash proof uploads with end-to-end encryption. Your contact details are never shared with third parties.',
                    style: AppTypography.body.copyWith(color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Last updated: August 2026',
                      style: AppTypography.caption.copyWith(color: AppColors.textHint),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// About ThriftLine Sheet
// =============================================================================

class _AboutThriftLineSheet extends StatelessWidget {
  const _AboutThriftLineSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 24),
                const SizedBox(width: 10),
                Text('About ThriftLine', style: AppTypography.heading),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  // App Icon / Logo
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryDark],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.checkroom_rounded,
                        color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 14),
                  Text('ThriftLine',
                      style: AppTypography.heading.copyWith(fontSize: 22)),
                  const SizedBox(height: 4),
                  Text(
                    'Sustainable Peer-to-Peer Thrift Marketplace',
                    style: AppTypography.caption.copyWith(fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'ThriftLine connects eco-conscious thrifters, vintage enthusiasts, and local sellers in a secure, verified community marketplace. Features real-time bidding, item request boards, and direct payment tracking.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment:  MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem(label: 'Verified Sellers', value: '1,200+'),
                        _StatItem(label: 'Items Saved', value: '15,000+'),
                        _StatItem(label: 'User Rating', value: '4.9 ★'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '© 2026 ThriftLine Capstone Project. All rights reserved.',
                    style: AppTypography.caption.copyWith(color: AppColors.textHint),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.heading.copyWith(
            color: AppColors.primary,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTypography.caption.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}
