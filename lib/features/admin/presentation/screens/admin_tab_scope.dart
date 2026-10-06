import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/route_names.dart';

class AdminTabScope extends InheritedWidget {
  const AdminTabScope({required this.openTab, required super.child, super.key});

  final void Function(int index) openTab;

  static const int dashboard = 0;
  static const int verifications = 1;
  static const int reports = 2;
  static const int settings = 3;

  static void open(BuildContext context, int index) {
    final scope = context.findAncestorWidgetOfExactType<AdminTabScope>();
    if (scope != null) {
      scope.openTab(index);
      return;
    }
    final route = switch (index) {
      dashboard => RouteNames.adminDashboard,
      verifications => RouteNames.adminVerifications,
      reports => RouteNames.adminReports,
      settings => RouteNames.adminSettings,
      _ => RouteNames.adminDashboard,
    };
    context.go(route);
  }

  @override
  bool updateShouldNotify(AdminTabScope oldWidget) => false;
}
