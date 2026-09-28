import 'package:flutter/material.dart';

/// Full-screen form. Fields scroll. The action stays above the keyboard.
class KeyboardSafeForm extends StatelessWidget {
  const KeyboardSafeForm({
    super.key,
    required this.children,
    required this.action,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 8),
  });

  final List<Widget> children;
  final Widget action;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: padding,
              children: children,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(padding.left, 8, padding.right, 12),
            child: action,
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet form. Uses the current window height only.
/// Android already resizes the window for the IME (`adjustResize`); do not
/// also pad [MediaQuery.viewInsets] or the first keyboard show is cancelled.
class KeyboardSafeSheet extends StatelessWidget {
  const KeyboardSafeSheet({
    super.key,
    required this.children,
    required this.action,
  });

  final List<Widget> children;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final top = MediaQuery.paddingOf(context).top;
    final maxHeight = (height - top - 12).clamp(160.0, height);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                children: children,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: action,
            ),
          ],
        ),
      ),
    );
  }
}
