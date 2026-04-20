import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:msitlms/theme/app_colors.dart';

class StudentDashboardShortcut {
  final String label;
  final IconData icon;
  final Color color;

  const StudentDashboardShortcut({
    required this.label,
    required this.icon,
    required this.color,
  });
}

class StudentDashboardPage extends StatelessWidget {
  final String userName;
  final List<StudentDashboardShortcut> shortcuts;
  final ValueChanged<StudentDashboardShortcut> onShortcutTap;

  const StudentDashboardPage({
    super.key,
    required this.userName,
    required this.shortcuts,
    required this.onShortcutTap,
  });

  @override
  Widget build(BuildContext context) {
    final panelStart = AppColors.dashboardPanelFrom(context);
    final panelMid = AppColors.dashboardPanelVia(context);
    final panelEnd = AppColors.dashboardPanelTo(context);
    final backgroundColor = AppColors.background(context);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              panelStart.withOpacity(0.9),
              panelMid.withOpacity(0.65),
              backgroundColor,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashboardHeroCard(userName: userName),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [panelStart, panelMid, panelEnd],
                  ),
                ),
                child: Column(
                  children: [
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: shortcuts.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.82,
                      ),
                      itemBuilder: (context, index) {
                        final shortcut = shortcuts[index];
                        return _DashboardShortcutTile(
                          shortcut: shortcut,
                          onTap: () => onShortcutTap(shortcut),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardHeroCard extends StatelessWidget {
  final String userName;

  const _DashboardHeroCard({
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 196),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.dashboardHero,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.dashboardHero.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Positioned(
            right: 0,
            top: 2,
            child: _FireworksArt(),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi, $userName',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.72),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  'Get your all\nacademic access\nhere',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1.08,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 165),
                child: Text(
                  'Everything you need for study, notices, quizzes, and results in one place.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.76),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DashboardShortcutTile extends StatelessWidget {
  final StudentDashboardShortcut shortcut;
  final VoidCallback onTap;

  const _DashboardShortcutTile({
    required this.shortcut,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final inkColor = AppColors.ink(context);
    final isDark = AppColors.isDark(context);
    final textColor = AppColors.isDark(context)
        ? AppColors.textPrimary(context)
        : AppColors.dashboardText;
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final iconBoxSize = math.min(constraints.maxWidth, 56.0);

          return Column(
            children: [
              Container(
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      surfaceColor,
                      shortcut.color.withOpacity(isDark ? 0.22 : 0.16),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: inkColor.withOpacity(0.07),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: borderColor,
                  ),
                ),
                child: Center(
                  child: Icon(
                    shortcut.icon,
                    color: shortcut.color,
                    size: iconBoxSize * 0.42,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                shortcut.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FireworksArt extends StatelessWidget {
  const _FireworksArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 190,
      child: CustomPaint(
        painter: _FireworksPainter(),
      ),
    );
  }
}

class _FireworksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final bursts = <_BurstSpec>[
      _BurstSpec(
        center: Offset(size.width * 0.62, size.height * 0.38),
        radius: 28,
        color: const Color(0xFF5861C7),
        spokes: 12,
      ),
      _BurstSpec(
        center: Offset(size.width * 0.92, size.height * 0.28),
        radius: 24,
        color: const Color(0xFF5060B8),
        spokes: 10,
      ),
      _BurstSpec(
        center: Offset(size.width * 0.42, size.height * 0.58),
        radius: 26,
        color: const Color(0xFF4A66CE),
        spokes: 12,
      ),
      _BurstSpec(
        center: Offset(size.width * 0.86, size.height * 0.82),
        radius: 22,
        color: const Color(0xFFE84957),
        spokes: 10,
      ),
      _BurstSpec(
        center: Offset(size.width * 0.52, size.height * 0.08),
        radius: 18,
        color: const Color(0xFF6466C8),
        spokes: 10,
      ),
    ];

    for (final burst in bursts) {
      final ringPaint = Paint()
        ..color = burst.color.withOpacity(0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(burst.center, burst.radius * 0.18, ringPaint);

      for (int i = 0; i < burst.spokes; i++) {
        final angle = (math.pi * 2 / burst.spokes) * i;
        final start = Offset(
          burst.center.dx + math.cos(angle) * burst.radius * 0.26,
          burst.center.dy + math.sin(angle) * burst.radius * 0.26,
        );
        final end = Offset(
          burst.center.dx + math.cos(angle) * burst.radius,
          burst.center.dy + math.sin(angle) * burst.radius,
        );

        final spokePaint = Paint()
          ..color = burst.color.withOpacity(0.84)
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(start, end, spokePaint);

        final dotPaint = Paint()
          ..color = i.isEven
              ? const Color(0xFFD7B56A).withOpacity(0.95)
              : burst.color.withOpacity(0.92);
        canvas.drawCircle(end, 1.5, dotPaint);
      }
    }

    final arcPaintBlue = Paint()
      ..color = const Color(0xFF4A66CE)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    final arcPaintRed = Paint()
      ..color = const Color(0xFFE04A5E)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    final arcPaintGold = Paint()
      ..color = const Color(0xFFD8B15F)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;

    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.58, size.height * 1.02),
        radius: 98,
      ),
      -2.22,
      0.28,
      false,
      arcPaintBlue,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.66, size.height * 1.04),
        radius: 92,
      ),
      -2.0,
      0.26,
      false,
      arcPaintRed,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.48, size.height * 1.06),
        radius: 84,
      ),
      -2.12,
      0.24,
      false,
      arcPaintGold,
    );
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(size.width * 0.74, size.height * 1.03),
        radius: 78,
      ),
      -2.14,
      0.24,
      false,
      arcPaintGold,
    );

    final swirlPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawSwirl(
      canvas,
      Offset(size.width * 0.70, size.height * 0.20),
      15,
      const Color(0xFF4A8CD8),
      swirlPaint,
    );
    _drawSwirl(
      canvas,
      Offset(size.width * 0.70, size.height * 0.62),
      16,
      const Color(0xFF4A8CD8),
      swirlPaint,
    );
    _drawSwirl(
      canvas,
      Offset(size.width * 0.56, size.height * 0.86),
      16,
      const Color(0xFFE04A5E),
      swirlPaint,
    );

    final linePaint = Paint()
      ..color = const Color(0xFF0F172A).withOpacity(0.74)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.40, size.height * 0.80),
      Offset(size.width * 0.40, size.height * 0.92),
      linePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.26, size.height * 0.88),
      Offset(size.width * 0.26, size.height * 0.96),
      linePaint,
    );
  }

  void _drawSwirl(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    Paint paint,
  ) {
    paint
      ..color = color
      ..strokeWidth = 3;

    for (int i = 0; i < 3; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - (i * 4)),
        0.4,
        4.2,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BurstSpec {
  final Offset center;
  final double radius;
  final Color color;
  final int spokes;

  const _BurstSpec({
    required this.center,
    required this.radius,
    required this.color,
    required this.spokes,
  });
}
