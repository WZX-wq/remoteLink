import 'package:flutter/material.dart';

class KqTheme {
  final bool isDark;

  const KqTheme._(this.isDark);

  factory KqTheme.of(BuildContext context) {
    return KqTheme._(Theme.of(context).brightness == Brightness.dark);
  }

  Color get ink => isDark ? const Color(0xFFE8F2FF) : const Color(0xFF10243E);
  Color get muted => isDark ? const Color(0xFF94AFCB) : const Color(0xFF5D7190);
  Color get primary =>
      isDark ? const Color(0xFF38A8FF) : const Color(0xFF1277D9);
  Color get primaryDeep =>
      isDark ? const Color(0xFF68BEFF) : const Color(0xFF075BB6);
  Color get line => isDark ? const Color(0xFF294866) : const Color(0xFFD4E8FA);
  Color get panel => isDark ? const Color(0xF01A2636) : const Color(0xF8FFFFFF);
  Color get panelStrong =>
      isDark ? const Color(0xFF172232) : const Color(0xFFFFFFFF);
  Color get surface =>
      isDark ? const Color(0xFF121D2B) : const Color(0xFFF8FCFF);
  Color get surfaceSoft =>
      isDark ? const Color(0xFF1E3045) : const Color(0xFFEAF6FF);
  Color get field => isDark ? const Color(0xFF0F1A28) : const Color(0xFFFFFFFF);
  Color get shadow =>
      isDark ? Colors.black.withOpacity(0.34) : primary.withOpacity(0.1);
  Color get iconTile =>
      isDark ? const Color(0xFF203A55) : const Color(0xFFEAF6FF);
  Color get iconTile2 =>
      isDark ? const Color(0xFF142638) : const Color(0xFFD9ECFC);
  Color get iconBorder =>
      isDark ? const Color(0xFF315777) : const Color(0xFFC6E0F4);
  Color get online => const Color(0xFF16A77A);
  Color get offline =>
      isDark ? const Color(0xFFFF6B7B) : const Color(0xFFD65B68);
  Color get warning =>
      isDark ? const Color(0xFFF1B14C) : const Color(0xFFE09B27);

  List<Color> get pageGradient => isDark
      ? const [
          Color(0xFF08111D),
          Color(0xFF102237),
          Color(0xFF0B1624),
        ]
      : const [
          Color(0xFFF4FBFF),
          Color(0xFFEAF6FF),
          Color(0xFFF9FCFF),
        ];

  List<Color> get panelGradient => isDark
      ? const [
          Color(0xFF1B2B3D),
          Color(0xFF111D2C),
        ]
      : const [
          Color(0xFFFFFFFF),
          Color(0xFFEAF6FF),
        ];

  List<Color> get workSurfaceGradient => isDark
      ? const [
          Color(0xFF111E2D),
          Color(0xFF162A40),
        ]
      : const [
          Color(0xFFF3F9FF),
          Color(0xFFEAF6FF),
        ];
}
