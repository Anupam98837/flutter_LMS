import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFFB41453);
  static const Color secondary = Color(0xFFD81B60);
  static const Color accent = Color(0xFFE95686);

  // Light theme
  static const Color lightBackground = Color(0xFFFFFAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFFFFCFD);
  static const Color lightSurface3 = Color(0xFFFFF3F7);

  static const Color lightInk = Color(0xFF1A1F2B);
  static const Color lightTextPrimary = Color(0xFF1C212B);
  static const Color lightTextSecondary = Color(0xFF8E97A8);

  static const Color lightBorderSoft = Color(0xFFEAEFF5);
  static const Color lightBorderMedium = Color(0xFFD7DEE9);
  static const Color lightBorderStrong = Color(0xFFC8D0DC);

  // Dark theme
  static const Color darkBackground = Color(0xFF11121A);
  static const Color darkSurface = Color(0xFF1A1C26);
  static const Color darkSurface2 = Color(0xFF202330);
  static const Color darkSurface3 = Color(0xFF272B39);

  static const Color darkInk = Color(0xFFF8D8E5);
  static const Color darkTextPrimary = Color(0xFFF4F6FA);
  static const Color darkTextSecondary = Color(0xFFB3BAC7);

  static const Color darkBorderSoft = Color(0xFF2A3040);
  static const Color darkBorderMedium = Color(0xFF3A4255);
  static const Color darkBorderStrong = Color(0xFF495268);

  // States
  static const Color success = Color(0xFF5BD77A);
  static const Color error = Color(0xFFE53935);
  static const Color warning = Color(0xFFF5A524);
  static const Color info = Color(0xFF7A9CFF);

  // Shared UI accents
  static const Color primarySoft = Color(0xFFF9DFEA);
  static const Color primarySoftBorder = Color(0xFFF0C3D5);
  static const Color primaryGlow = Color(0xFFE84E7D);
  static const Color accentText = Color(0xFFE12468);

  static const Color dangerSurface = Color(0xFFFFEEF0);
  static const Color dangerBorder = Color(0xFFF5B8BD);
  static const Color dangerText = Color(0xFFE54843);
  static const Color dangerStrong = Color(0xFFE53935);

  static const Color dashboardHero = Color(0xFF313B63);
  static const Color dashboardGlowLeft = Color(0xFFDCE5FF);
  static const Color dashboardGlowRight = Color(0xFFE6F6FF);
  static const Color dashboardPanelStart = Color(0xFFF3F5FF);
  static const Color dashboardPanelMid = Color(0xFFF6FBFF);
  static const Color dashboardPanelEnd = Color(0xFFFFFFFF);
  static const Color dashboardText = Color(0xFF36445D);
  static const Color dashboardMuted = Color(0xFF8D95A4);
  static const Color dashboardAvatarStart = Color(0xFFD3F7F0);
  static const Color dashboardAvatarEnd = Color(0xFFBCE6F8);
  static const Color dashboardAvatarFallback = Color(0xFFE7F7F5);
  static const Color dashboardAvatarText = Color(0xFF4F6676);

  static const Color syllabus = Color(0xFFE53B67);
  static const Color lessonPlan = Color(0xFFFF8A24);
  static const Color notices = Color(0xFF29A49D);
  static const Color materials = Color(0xFFF5A31C);
  static const Color assignments = Color(0xFF7B84EE);
  static const Color quizzes = Color(0xFF73839D);
  static const Color result = Color(0xFF2BC28C);
  static const Color profile = Color(0xFF2F9CE5);

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
}
