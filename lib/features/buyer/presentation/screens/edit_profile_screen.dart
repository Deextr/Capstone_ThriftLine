import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../features/auth/data/auth_service.dart';
import '../../../../providers/auth_provider.dart';
import '../../../../widgets/thrift_widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _locationCtrl;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    final user = AuthService().getUserByUsername(auth.username ?? '');
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _locationCtrl = TextEditingController(text: user?.location ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Edit Profile'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop())),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: Column(
              children: [
                const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
                const SizedBox(height: 24),
                ThriftTextField(label: 'Name', controller: _nameCtrl),
                const SizedBox(height: 16),
                ThriftTextField(label: 'Location', controller: _locationCtrl),
                const Spacer(),
                ThriftButton(
                  label: 'Save',
                  onPressed: () {
                    showThriftSnackBar(context, 'Profile updated!');
                    context.pop();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
