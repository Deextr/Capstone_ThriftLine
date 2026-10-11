import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/admin_portal_session_controller.dart';

/// Forwards meaningful user interaction to [AdminPortalSessionController].
///
/// Automatic refreshes, Realtime updates, and other background work do not pass
/// through this listener.
class AdminPortalActivityListener extends StatelessWidget {
  const AdminPortalActivityListener({
    super.key,
    required this.controller,
    required this.enabled,
    required this.child,
  });

  final AdminPortalSessionController controller;
  final bool enabled;
  final Widget child;

  void _ping() {
    if (enabled) controller.onUserActivity();
  }

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _ping(),
      onPointerMove: (_) => _ping(),
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) _ping();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is UserScrollNotification) _ping();
          return false;
        },
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) _ping();
            return KeyEventResult.ignored;
          },
          child: child,
        ),
      ),
    );
  }
}
