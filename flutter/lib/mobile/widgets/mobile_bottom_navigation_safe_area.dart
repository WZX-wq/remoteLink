import 'package:flutter/material.dart';

class MobileBottomNavigationSafeArea extends StatelessWidget {
  const MobileBottomNavigationSafeArea({
    super.key,
    required this.isIOS,
    required this.child,
  });

  final bool isIOS;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!isIOS) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: child,
      );
    }
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 14),
      child: child,
    );
  }
}
