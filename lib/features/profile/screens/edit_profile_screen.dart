import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/services/supabase_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/thrift_widgets.dart';
import '../controllers/profile_controller.dart';
import '../widgets/edit_profile_form.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
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

    // Initial loading of user data from Supabase
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
          final currentUser = controller.currentUser;
          final initialName = currentUser?.name ?? authUser?.name ?? '';
          final initialUsername = currentUser?.username ?? authUser?.username ?? '';
          final initialEmail = currentUser?.email ?? authUser?.email ?? '';
          final initialPhone = currentUser?.phone ?? authUser?.phone ?? '';

          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Edit Profile'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                elevation: 0,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              ),
              body: SafeArea(
                child: controller.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacingMd,
                          vertical: 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Stack(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primaryLight,
                                        width: 3,
                                      ),
                                    ),
                                    child: ThriftAvatar(
                                      imageUrl: currentUser?.avatarUrl ?? authUser?.avatarUrl ?? '',
                                      name: initialName,
                                      size: 90,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text('Edit Profile', style: AppTypography.subheading),
                            const SizedBox(height: 16),
                            EditProfileForm(
                              initialName: initialName,
                              initialUsername: initialUsername,
                              initialEmail: initialEmail,
                              initialPhone: initialPhone,
                              isSaving: controller.isSaving,
                              errorMessage: controller.errorMessage,
                              onSave: ({
                                required String fullName,
                                required String username,
                                required String email,
                                required String phone,
                              }) async {
                                final success = await controller.updateProfile(
                                  fullName: fullName,
                                  username: username,
                                  email: email,
                                  phone: phone,
                                );

                                if (context.mounted) {
                                  if (success) {
                                    showThriftSnackBar(
                                      context,
                                      controller.successMessage ?? 'Profile updated successfully!',
                                    );
                                    context.pop();
                                  } else if (controller.errorMessage != null) {
                                    showThriftSnackBar(
                                      context,
                                      controller.errorMessage!,
                                      isError: true,
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
