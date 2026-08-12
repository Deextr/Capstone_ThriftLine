import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/services/supabase_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/thrift_widgets.dart';
import '../controllers/profile_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late ProfileController _controller;

  @override
  void initState() {
    super.initState();
    final supabaseService = context.read<SupabaseService>();
    final authProvider = context.read<AuthProvider>();

    _controller = ProfileController(
      supabaseService: supabaseService,
      authProvider: authProvider,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.loadProfile();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final authUser = auth.user;

    return ChangeNotifierProvider<ProfileController>.value(
      value: _controller,
      child: Consumer<ProfileController>(
        builder: (context, controller, child) {
          final user = controller.currentUser;
          final name = user?.name.isNotEmpty == true ? user!.name : (authUser?.name ?? '');
          final username = user?.username?.isNotEmpty == true ? user!.username! : (authUser?.username ?? '');
          final email = user?.email.isNotEmpty == true ? user!.email : (authUser?.email ?? '');
          final phone = user?.phone?.isNotEmpty == true ? user!.phone! : (authUser?.phone ?? '');
          final avatarUrl = user?.avatarUrl ?? authUser?.avatarUrl ?? '';

          return Scaffold(
            appBar: AppBar(
              title: const Text('Profile'),
              elevation: 0,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppConstants.spacingMd),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    ThriftAvatar(imageUrl: avatarUrl, name: name, size: 90),
                    const SizedBox(height: 16),
                    Text(
                      name.isNotEmpty ? name : 'No Name Provided',
                      style: AppTypography.heading.copyWith(fontSize: 22),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      username.isNotEmpty ? '@$username' : '@username',
                      style: AppTypography.caption.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _infoTile(
                            icon: Icons.person_outline,
                            label: 'Full Name',
                            value: name.isNotEmpty ? name : 'Not set',
                          ),
                          const Divider(height: 24),
                          _infoTile(
                            icon: Icons.alternate_email,
                            label: 'Username',
                            value: username.isNotEmpty ? username : 'Not set',
                          ),
                          const Divider(height: 24),
                          _infoTile(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: email.isNotEmpty ? email : 'Not set',
                            badge: const ThriftBadge(
                              label: 'Unverified',
                              variant: BadgeVariant.warning,
                            ),
                          ),
                          const Divider(height: 24),
                          _infoTile(
                            icon: Icons.phone_outlined,
                            label: 'Phone Number',
                            value: phone.isNotEmpty ? phone : 'Not set',
                            badge: const ThriftBadge(
                              label: 'Unverified',
                              variant: BadgeVariant.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    ThriftButton(
                      label: 'Edit Profile',
                      icon: Icons.edit_outlined,
                      onPressed: () async {
                        await context.push(RouteNames.editProfile);
                        if (context.mounted) {
                          _controller.loadProfile();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    Widget? badge,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.textPrimary, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    badge,
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
