import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Brand — Maroon Primary With Neutral Support ─────────────────────────
  static const Color primary = Color(0xFF8B1A2B);
  static const Color primaryLight = Color(0xFFA3293D);
  static const Color primaryDark = Color(0xFF6E1522);
  static const Color secondary = Color(0xFF4B5563);
  static const Color accent = Color(0xFF9CA3AF);

  // ── Light theme ──────────────────────────────────────────────────────────
  static const Color lightBackground = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFF7F7F8);
  static const Color lightSurface3 = Color(0xFFF0F1F3);

  static const Color lightInk = Color(0xFF121417);
  static const Color lightTextPrimary = Color(0xFF0F172A);  // slate-900
  static const Color lightTextSecondary = Color(0xFF475569); // slate-600

  static const Color lightBorderSoft = Color(0xFFE5E7EB);
  static const Color lightBorderMedium = Color(0xFFD1D5DB);
  static const Color lightBorderStrong = Color(0xFF9CA3AF);

  // ── Dark theme ───────────────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF0B0D10);
  static const Color darkSurface = Color(0xFF121417);
  static const Color darkSurface2 = Color(0xFF171A1F);
  static const Color darkSurface3 = Color(0xFF1F232A);

  static const Color darkInk = Color(0xFFF4F4F5);
  static const Color darkTextPrimary = Color(0xFFF5F5F5);
  static const Color darkTextSecondary = Color(0xFF94A3B8); // slate-400

  static const Color darkBorderSoft = Color(0xFF242831);
  static const Color darkBorderMedium = Color(0xFF323844);
  static const Color darkBorderStrong = Color(0xFF454D5C);

  // ── States ───────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF6B7280);

  // ── Shared UI accents ────────────────────────────────────────────────────
  static const Color primarySoft = Color(0xFFF3F4F6);
  static const Color primarySoftBorder = Color(0xFFE5E7EB);
  static const Color primaryGlow = Color(0xFF6B7280);
  static const Color accentText = Color(0xFF8B1A2B);

  static const Color dangerSurface = Color(0xFFFFF1F2);
  static const Color dangerBorder = Color(0xFFFECACA);
  static const Color dangerText = Color(0xFF991B1B);
  static const Color dangerStrong = Color(0xFFEF4444);

  // ── Dashboard ────────────────────────────────────────────────────────────
  static const Color dashboardHero = Color(0xFF181B20);
  static const Color dashboardHeroMid = Color(0xFF20242B);
  static const Color dashboardHeroEnd = Color(0xFF2A2F38);
  static const Color dashboardGlowLeft = Color(0xFFEDEEF0);
  static const Color dashboardGlowRight = Color(0xFFF2F3F5);
  static const Color dashboardPanelStart = Color(0xFFF5F6F7);
  static const Color dashboardPanelMid = Color(0xFFF8F8F9);
  static const Color dashboardPanelEnd = Color(0xFFFCFCFD);
  static const Color dashboardText = Color(0xFF0F172A);
  static const Color dashboardMuted = Color(0xFF64748B);
  static const Color dashboardAvatarStart = Color(0xFFE5E7EB);
  static const Color dashboardAvatarEnd = Color(0xFFD1D5DB);
  static const Color dashboardAvatarFallback = Color(0xFFF3F4F6);
  static const Color dashboardAvatarText = Color(0xFF374151);

  // ── Module accent colors ──────────────────────────────────────────────────
  static const Color syllabus = Color(0xFFE24A68);
  static const Color lessonPlan = Color(0xFFEF8A2F);
  static const Color notices = Color(0xFF4B5563);
  static const Color materials = Color(0xFFF59E0B);
  static const Color assignments = Color(0xFF7C5CFC);
  static const Color quizzes = Color(0xFF6366F1);
  static const Color result = Color(0xFF10B981);
  static const Color routine = Color(0xFF6B7280);
  static const Color profile = Color(0xFF9CA3AF);

  // ── Context helpers ───────────────────────────────────────────────────────
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color background(BuildContext context) =>
      isDark(context) ? darkBackground : lightBackground;

  static Color surface(BuildContext context) =>
      isDark(context) ? darkSurface : lightSurface;

  static Color surface2(BuildContext context) =>
      isDark(context) ? darkSurface2 : lightSurface2;

  static Color surface3(BuildContext context) =>
      isDark(context) ? darkSurface3 : lightSurface3;

  static Color ink(BuildContext context) =>
      isDark(context) ? darkInk : lightInk;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? darkTextPrimary : lightTextPrimary;

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? darkTextSecondary : lightTextSecondary;

  static Color borderSoft(BuildContext context) =>
      isDark(context) ? darkBorderSoft : lightBorderSoft;

  static Color borderMedium(BuildContext context) =>
      isDark(context) ? darkBorderMedium : lightBorderMedium;

  static Color borderStrong(BuildContext context) =>
      isDark(context) ? darkBorderStrong : lightBorderStrong;

  static Color softFill(BuildContext context) =>
      isDark(context) ? darkSurface3 : primarySoft;

  static Color softBorder(BuildContext context) =>
      isDark(context) ? darkBorderMedium : primarySoftBorder;

  static Color dangerFill(BuildContext context) =>
      isDark(context) ? const Color(0xFF1C0E0E) : dangerSurface;

  static Color dangerOutline(BuildContext context) =>
      isDark(context) ? const Color(0xFF4A2020) : dangerBorder;

  static Color dangerLabel(BuildContext context) =>
      isDark(context) ? const Color(0xFFFCA5A5) : dangerText;

  static Color dangerAccent(BuildContext context) =>
      isDark(context) ? const Color(0xFFF87171) : dangerStrong;

  static Color dashboardGlowStart(BuildContext context) =>
      isDark(context) ? darkSurface2 : dashboardGlowLeft;

  static Color dashboardGlowEnd(BuildContext context) =>
      isDark(context) ? darkSurface3 : dashboardGlowRight;

  static Color dashboardPanelFrom(BuildContext context) =>
      isDark(context) ? darkSurface2 : dashboardPanelStart;

  static Color dashboardPanelVia(BuildContext context) =>
      isDark(context) ? darkSurface3 : dashboardPanelMid;

  static Color dashboardPanelTo(BuildContext context) =>
      isDark(context) ? darkSurface : dashboardPanelEnd;

  static Color dashboardMutedColor(BuildContext context) =>
      isDark(context) ? darkTextSecondary : dashboardMuted;
}
