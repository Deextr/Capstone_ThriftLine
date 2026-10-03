import 'package:flutter/material.dart';

import '../../data/admin_review_rules.dart';
import 'admin_reports_hub_screen.dart';
import 'admin_reports_queue_screen.dart';

/// In-shell navigation: hub → category list without leaving the admin tab bar.
class AdminReportsShellTab extends StatefulWidget {
  const AdminReportsShellTab({super.key});

  @override
  State<AdminReportsShellTab> createState() => _AdminReportsShellTabState();
}

class _AdminReportsShellTabState extends State<AdminReportsShellTab> {
  AdminReportKind? _category;

  @override
  Widget build(BuildContext context) {
    if (_category == null) {
      return AdminReportsHubScreen(
        embedded: true,
        onCategorySelected: (kind) => setState(() => _category = kind),
      );
    }
    return AdminReportsQueueScreen(
      embedded: true,
      kind: _category!,
      onBackToHub: () => setState(() => _category = null),
    );
  }
}
