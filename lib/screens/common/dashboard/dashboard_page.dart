import 'dart:math' as math;
import 'dart:ui';

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
    final isDark = AppColors.isDark(context);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              panelStart.withOpacity(0.95),
              panelMid.withOpacity(0.7),
              backgroundColor,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashboardHeroCard(userName: userName),
              const SizedBox(height: 16),
              // Quick Access label
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text(
                  'Quick Access',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              // Glass shortcuts panel
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                AppColors.darkSurface.withOpacity(0.85),
                                AppColors.darkSurface2.withOpacity(0.7),
                              ]
                            : [
                                Colors.white.withOpacity(0.82),
                                panelStart.withOpacity(0.6),
                              ],
                      ),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkBorderMedium.withOpacity(0.5)
                            : AppColors.lightBorderMedium.withOpacity(0.7),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withOpacity(0.25)
                              : AppColors.primary.withOpacity(0.07),
                          blurRadius: 24,
                          spreadRadius: 0,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: shortcuts.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.80,
                      ),
                      itemBuilder: (context, index) {
                        return _DashboardShortcutTile(
                          shortcut: shortcuts[index],
                          onTap: () => onShortcutTap(shortcuts[index]),
                          index: index,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero card ──────────────────────────────────────────────────────────────
class _DashboardHeroCard extends StatelessWidget {
  final String userName;
  const _DashboardHeroCard({required this.userName});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 186),
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.dashboardHero,
            AppColors.dashboardHeroMid,
            AppColors.dashboardHeroEnd,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.dashboardHero.withOpacity(0.45),
            blurRadius: 28,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: AppColors.primary.withOpacity(0.18),
            blurRadius: 40,
            spreadRadius: -8,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative wave/art
          const Positioned(
            right: 0,
            top: 0,
            child: _OceanArt(),
          ),
          // Top teal glow orb
          Positioned(
            top: -20,
            right: 40,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primaryLight.withOpacity(0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.20),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent, // warm gold dot
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Hi, $userName 👋',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.90),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 210),
                child: const Text(
                  'Your academic\nportal awaits',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.06,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 175),
                child: Text(
                  'Study materials, notices, quizzes & results — all in one place.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
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

// ── Shortcut tile with press animation ───────────────────────────────────────
class _DashboardShortcutTile extends StatefulWidget {
  final StudentDashboardShortcut shortcut;
  final VoidCallback onTap;
  final int index;

  const _DashboardShortcutTile({
    required this.shortcut,
    required this.onTap,
    required this.index,
  });

  @override
  State<_DashboardShortcutTile> createState() => _DashboardShortcutTileState();
}

class _DashboardShortcutTileState extends State<_DashboardShortcutTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 160),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final textColor = isDark
        ? AppColors.textPrimary(context)
        : AppColors.dashboardText;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final iconBoxSize = math.min(constraints.maxWidth, 54.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [
                              AppColors.darkSurface3,
                              widget.shortcut.color.withOpacity(0.28),
                            ]
                          : [
                              Colors.white,
                              widget.shortcut.color.withOpacity(0.14),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? widget.shortcut.color.withOpacity(0.22)
                          : widget.shortcut.color.withOpacity(0.18),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.shortcut.color.withOpacity(
                          isDark ? 0.20 : 0.14,
                        ),
                        blurRadius: 12,
                        spreadRadius: 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      widget.shortcut.icon,
                      color: widget.shortcut.color,
                      size: iconBoxSize * 0.42,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.shortcut.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Maroon & Gold decorative art ──────────────────────────────────────────
class _OceanArt extends StatelessWidget {
  const _OceanArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 186,
      child: CustomPaint(painter: _MaroonGoldPainter()),
    );
  }
}

class _MaroonGoldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // ── Floating ornamental circles (rose & gold tones) ──
    final bubbleSpecs = [
      _CircleSpec(Offset(size.width * 0.78, size.height * 0.18), 26,
          const Color(0xFFD4A853)), // gold
      _CircleSpec(Offset(size.width * 0.58, size.height * 0.32), 18,
          const Color(0xFFA8263A)), // medium maroon
      _CircleSpec(Offset(size.width * 0.90, size.height * 0.55), 22,
          const Color(0xFFE8C87A)), // light gold
      _CircleSpec(Offset(size.width * 0.65, size.height * 0.72), 14,
          const Color(0xFFC98B90)), // dusty rose
      _CircleSpec(Offset(size.width * 0.46, size.height * 0.12), 10,
          const Color(0xFFD4A853)), // gold
    ];

    for (final b in bubbleSpecs) {
      final ringPaint = Paint()
        ..color = b.color.withOpacity(0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(b.center, b.radius, ringPaint);

      final fillPaint = Paint()
        ..color = b.color.withOpacity(0.13)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(b.center, b.radius * 0.7, fillPaint);

      // Shine highlight
      final highlightPaint = Paint()
        ..color = Colors.white.withOpacity(0.30)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(b.center.dx - b.radius * 0.18, b.center.dy - b.radius * 0.22),
        b.radius * 0.18,
        highlightPaint,
      );
    }

    // ── Arcing sweep lines (maroon / rose / gold) ──
    final arcMaroon = Paint()
      ..color = const Color(0xFFA8263A).withOpacity(0.50)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5;
    final arcRose = Paint()
      ..color = const Color(0xFFC98B90).withOpacity(0.38)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    final arcGold = Paint()
      ..color = const Color(0xFFD4A853).withOpacity(0.45)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;

    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(size.width * 0.55, size.height * 1.05), radius: 92),
      -2.20, 0.30, false, arcMaroon,
    );
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(size.width * 0.68, size.height * 1.08), radius: 84),
      -2.05, 0.28, false, arcGold,
    );
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(size.width * 0.42, size.height * 1.10), radius: 76),
      -2.15, 0.26, false, arcRose,
    );
    canvas.drawArc(
      Rect.fromCircle(
          center: Offset(size.width * 0.74, size.height * 1.03), radius: 68),
      -2.10, 0.24, false, arcGold,
    );

    // ── Streak connectors with end dots ──
    final streakPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;

    final streaks = [
      _StreakSpec(
        Offset(size.width * 0.62, size.height * 0.44),
        Offset(size.width * 0.80, size.height * 0.38),
        const Color(0xFFD4A853), // gold
      ),
      _StreakSpec(
        Offset(size.width * 0.50, size.height * 0.60),
        Offset(size.width * 0.70, size.height * 0.55),
        const Color(0xFFA8263A), // maroon
      ),
      _StreakSpec(
        Offset(size.width * 0.72, size.height * 0.78),
        Offset(size.width * 0.88, size.height * 0.72),
        const Color(0xFFE8C87A), // light gold
      ),
    ];

    for (final s in streaks) {
      streakPaint.color = s.color.withOpacity(0.44);
      canvas.drawLine(s.from, s.to, streakPaint);

      final dotPaint = Paint()
        ..color = s.color.withOpacity(0.72)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(s.from, 2.2, dotPaint);
      canvas.drawCircle(s.to, 2.2, dotPaint);
    }

    // ── Gold sparkle stars (4-point cross) ──
    final sparklePositions = [
      Offset(size.width * 0.55, size.height * 0.08),
      Offset(size.width * 0.84, size.height * 0.30),
      Offset(size.width * 0.48, size.height * 0.50),
      Offset(size.width * 0.92, size.height * 0.78),
    ];

    final sparklePaint = Paint()
      ..color = const Color(0xFFE8C87A).withOpacity(0.80)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final sp in sparklePositions) {
      // Horizontal arm
      canvas.drawLine(Offset(sp.dx - 4, sp.dy), Offset(sp.dx + 4, sp.dy), sparklePaint);
      // Vertical arm
      canvas.drawLine(Offset(sp.dx, sp.dy - 4), Offset(sp.dx, sp.dy + 4), sparklePaint);

      // Center dot
      final dotPaint = Paint()
        ..color = Colors.white.withOpacity(0.70)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(sp, 1.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CircleSpec {
  final Offset center;
  final double radius;
  final Color color;
  const _CircleSpec(this.center, this.radius, this.color);
}

class _StreakSpec {
  final Offset from;
  final Offset to;
  final Color color;
  const _StreakSpec(this.from, this.to, this.color);
}
