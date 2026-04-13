import 'package:flutter/material.dart';

import 'package:hallienzlms/theme/app_colors.dart';

class ComingSoonPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const ComingSoonPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = AppColors.surface(context);
    final inkColor = AppColors.ink(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final softFill = AppColors.softFill(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        child: Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.fromLTRB(26, 32, 26, 30),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: inkColor.withOpacity(0.06),
                  blurRadius: 26,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: softFill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.primary,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  '$title Coming Soon',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: softFill,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Coming Soon',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
