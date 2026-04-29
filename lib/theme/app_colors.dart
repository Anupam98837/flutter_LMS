import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF8B2E3A);
  static const Color secondary = Color(0xFF6E252F);
  static const Color accent = Color(0xFF4A4F57);

  // Light theme
  static const Color lightBackground = Color(0xFFF4F5F7);
  static const Color lightSurface = Color(0xFFF9FAFB);
  static const Color lightSurface2 = Color(0xFFF4F6F8);
  static const Color lightSurface3 = Color(0xFFEEF1F4);

  static const Color lightInk = Color(0xFF15181D);
  static const Color lightTextPrimary = Color(0xFF181B20);
  static const Color lightTextSecondary = Color(0xFF666D76);

  static const Color lightBorderSoft = Color(0xFFE3E6EA);
  static const Color lightBorderMedium = Color(0xFFD2D7DE);
  static const Color lightBorderStrong = Color(0xFFC2C9D2);

  // Dark theme
  static const Color darkBackground = Color(0xFF1B1E24);
  static const Color darkSurface = Color(0xFF242830);
  static const Color darkSurface2 = Color(0xFF2B3038);
  static const Color darkSurface3 = Color(0xFF333943);

  static const Color darkInk = Color(0xFFF1F3F5);
  static const Color darkTextPrimary = Color(0xFFF4F6FA);
  static const Color darkTextSecondary = Color(0xFFB3BAC7);

  static const Color darkBorderSoft = Color(0xFF2A3040);
  static const Color darkBorderMedium = Color(0xFF3A4255);
  static const Color darkBorderStrong = Color(0xFF495268);

  // States
  static const Color success = Color(0xFF5BD77A);
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFF8A6D3B);
  static const Color info = Color(0xFF6E7781);

  // Shared UI accents
  static const Color primarySoft = Color(0xFFF1F0F1);
  static const Color primarySoftBorder = Color(0xFFD8D1D3);
  static const Color primaryGlow = Color(0xFF7E6368);
  static const Color accentText = Color(0xFF8B2E3A);

  static const Color dangerSurface = Color(0xFFF5F4F5);
  static const Color dangerBorder = Color(0xFFD8C5C8);
  static const Color dangerText = Color(0xFF8B2E3A);
  static const Color dangerStrong = Color(0xFFE53935);

  static const Color dashboardHero = Color(0xFF3F2027);
  static const Color dashboardGlowLeft = Color(0xFFE7EAED);
  static const Color dashboardGlowRight = Color(0xFFF0F1F3);
  static const Color dashboardPanelStart = Color(0xFFF1F2F4);
  static const Color dashboardPanelMid = Color(0xFFF7F8F9);
  static const Color dashboardPanelEnd = Color(0xFFF9FAFB);
  static const Color dashboardText = Color(0xFF353A40);
  static const Color dashboardMuted = Color(0xFF7A828C);
  static const Color dashboardAvatarStart = Color(0xFFE8EAED);
  static const Color dashboardAvatarEnd = Color(0xFFDDE1E6);
  static const Color dashboardAvatarFallback = Color(0xFFF1F2F4);
  static const Color dashboardAvatarText = Color(0xFF59616A);

  static const Color syllabus = Color(0xFFE24A68);
  static const Color lessonPlan = Color(0xFFEF8A2F);
  static const Color notices = Color(0xFF2F9B93);
  static const Color materials = Color(0xFFF0A322);
  static const Color assignments = Color(0xFF7C83F1);
  static const Color quizzes = Color(0xFF79869B);
  static const Color result = Color(0xFF30B981);
  static const Color routine = Color(0xFF4F87F7);
  static const Color profile = Color(0xFF2F9CE0);

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static Color background(BuildContext context) {
    return isDark(context) ? darkBackground : lightBackground;
  }

  static Color surface(BuildContext context) {
    return isDark(context) ? darkSurface : lightSurface;
  }

  static Color surface2(BuildContext context) {
    return isDark(context) ? darkSurface2 : lightSurface2;
  }

  static Color surface3(BuildContext context) {
    return isDark(context) ? darkSurface3 : lightSurface3;
  }

  static Color ink(BuildContext context) {
    return isDark(context) ? darkInk : lightInk;
  }

  static Color textPrimary(BuildContext context) {
    return isDark(context) ? darkTextPrimary : lightTextPrimary;
  }

  static Color textSecondary(BuildContext context) {
    return isDark(context) ? darkTextSecondary : lightTextSecondary;
  }

  static Color borderSoft(BuildContext context) {
    return isDark(context) ? darkBorderSoft : lightBorderSoft;
  }

  static Color borderMedium(BuildContext context) {
    return isDark(context) ? darkBorderMedium : lightBorderMedium;
  }

  static Color borderStrong(BuildContext context) {
    return isDark(context) ? darkBorderStrong : lightBorderStrong;
  }

  static Color softFill(BuildContext context) {
    return isDark(context) ? darkSurface3 : primarySoft;
  }

  static Color softBorder(BuildContext context) {
    return isDark(context) ? darkBorderMedium : primarySoftBorder;
  }

  static Color dangerFill(BuildContext context) {
    return isDark(context) ? const Color(0xFF2A2124) : dangerSurface;
  }

  static Color dangerOutline(BuildContext context) {
    return isDark(context) ? const Color(0xFF5A4348) : dangerBorder;
  }

  static Color dangerLabel(BuildContext context) {
    return isDark(context) ? const Color(0xFFF0C9CF) : dangerText;
  }

  static Color dangerAccent(BuildContext context) {
    return isDark(context) ? const Color(0xFFE4A8B2) : dangerStrong;
  }

  static Color dashboardGlowStart(BuildContext context) {
    return isDark(context) ? darkSurface2 : dashboardGlowLeft;
  }

  static Color dashboardGlowEnd(BuildContext context) {
    return isDark(context) ? darkSurface3 : dashboardGlowRight;
  }

  static Color dashboardPanelFrom(BuildContext context) {
    return isDark(context) ? darkSurface2 : dashboardPanelStart;
  }

  static Color dashboardPanelVia(BuildContext context) {
    return isDark(context) ? darkSurface3 : dashboardPanelMid;
  }

  static Color dashboardPanelTo(BuildContext context) {
    return isDark(context) ? darkSurface : dashboardPanelEnd;
  }

  static Color dashboardMutedColor(BuildContext context) {
    return isDark(context) ? darkTextSecondary : dashboardMuted;
  }
}
