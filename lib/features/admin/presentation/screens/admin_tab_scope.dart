import 'package:flutter/material.dart';

class AdminTabScope extends InheritedWidget {
  const AdminTabScope({required this.openTab, required super.child, super.key});

  final void Function(int index) openTab;

  static const int dashboard = 0;
  static const int verifications = 1;
  static const int reports = 2;
  static const int settings = 3;

  static void open(BuildContext context, int index) {
    context.findAncestorWidgetOfExactType<AdminTabScope>()?.openTab(index);
  }

  @override
  bool updateShouldNotify(AdminTabScope oldWidget) => false;
}
