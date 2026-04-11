import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hallienzlms/config/appConfig.dart';
import 'package:hallienzlms/theme/app_colors.dart';

class StructurePage extends StatefulWidget {
  final String? userName;
  final int initialIndex;

  const StructurePage({
    super.key,
    this.userName,
    this.initialIndex = 0,
  });

  @override
  State<StructurePage> createState() => _StructurePageState();
}

class _StructurePageState extends State<StructurePage> {
  static const List<_BottomNavItem> _navItems = [
    _BottomNavItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    _BottomNavItem(
      label: 'Study',
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book_rounded,
    ),
    _BottomNavItem(
      label: 'Assign',
      icon: Icons.edit_note_outlined,
      activeIcon: Icons.edit_note_rounded,
    ),
    _BottomNavItem(
      label: 'Exam',
      icon: Icons.gps_fixed_rounded,
      activeIcon: Icons.gps_fixed_rounded,
    ),
    _BottomNavItem(
      label: 'Syllabus',
      icon: Icons.description_outlined,
      activeIcon: Icons.description_rounded,
    ),
  ];

  static const List<_DashboardShortcut> _shortcuts = [
    _DashboardShortcut(
      label: 'Syllabus',
      icon: Icons.menu_book_outlined,
      color: AppColors.syllabus,
    ),
    _DashboardShortcut(
      label: 'Lesson Plan',
      icon: Icons.map_outlined,
      color: AppColors.lessonPlan,
    ),
    _DashboardShortcut(
      label: 'Notices',
      icon: Icons.notifications_none_rounded,
      color: AppColors.notices,
    ),
    _DashboardShortcut(
      label: 'Materials',
      icon: Icons.article_outlined,
      color: AppColors.materials,
    ),
    _DashboardShortcut(
      label: 'Assignments',
      icon: Icons.assignment_outlined,
      color: AppColors.assignments,
    ),
    _DashboardShortcut(
      label: 'Quizzes',
      icon: Icons.help_outline_rounded,
      color: AppColors.quizzes,
    ),
    _DashboardShortcut(
      label: 'Result',
      icon: Icons.workspace_premium_outlined,
      color: AppColors.result,
    ),
    _DashboardShortcut(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      color: AppColors.profile,
    ),
  ];

  late int _currentIndex;
  String? _profileImageUrl;
  String? _profileAvatarText;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _navItems.length - 1).toInt();
    unawaited(_loadMiniProfile());
  }

  String get _safeUserName {
    final name = widget.userName?.trim();
    if (name == null || name.isEmpty) return 'Student';
    return name;
  }

  String get _profileFallbackLetter {
    final avatarText = _profileAvatarText?.trim();
    if (avatarText != null && avatarText.isNotEmpty) {
      return avatarText.substring(0, 1).toUpperCase();
    }
    return _safeUserName.substring(0, 1).toUpperCase();
  }

  String? _normalizeProfileImageUrl(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) {
      return '${AppConfig.baseUrl}$raw';
    }
    return '${AppConfig.baseUrl}/$raw';
  }

  Future<Map<String, dynamic>> _getJson(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    final client = http.Client();

    try {
      final response = await client
          .get(
            Uri.parse(endpoint),
            headers: {
              HttpHeaders.acceptHeader: 'application/json',
              HttpHeaders.userAgentHeader:
                  'HallienzLMS/1.0 (Flutter iOS/Android)',
              ...?headers,
            },
          )
          .timeout(const Duration(seconds: 20));

      dynamic decoded;
      try {
        decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      } catch (_) {
        decoded = {};
      }

      return {
        'statusCode': response.statusCode,
        'data': decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{},
      };
    } finally {
      client.close();
    }
  }

  Future<void> _loadMiniProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token')?.trim() ?? '';

    if (token.isEmpty) return;

    try {
      final result = await _getJson(
        '${AppConfig.baseUrl}/api/profile/mini',
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
      );

      final statusCode = result['statusCode'] as int;
      if (statusCode < 200 || statusCode >= 300 || !mounted) return;

      final payload = result['data'] as Map<String, dynamic>;
      final block = payload['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(payload['data'] as Map)
          : payload;

      setState(() {
        _profileImageUrl = _normalizeProfileImageUrl(
          block['image']?.toString(),
        );
        _profileAvatarText = block['avatar_text']?.toString();
      });
    } catch (_) {
      // Keep the header fallback initial when the profile mini API is unavailable.
    }
  }

  void _handleBottomNavTap(int index) {
    if (_currentIndex == index) return;

    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: Stack(
        children: [
          Positioned(
            top: 220,
            left: -90,
            child: _glowOrb(
              color: AppColors.dashboardGlowLeft,
              size: 300,
            ),
          ),
          Positioned(
            top: 340,
            right: -80,
            child: _glowOrb(
              color: AppColors.dashboardGlowRight,
              size: 260,
            ),
          ),
          Column(
            children: [
              _buildHeader(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey<int>(_currentIndex),
                    child: _currentIndex == 0
                        ? _buildDashboard()
                        : _ComingSoonPage(
                            title: _navItems[_currentIndex].label,
                            subtitle:
                                '${_navItems[_currentIndex].label} section is coming soon.',
                            icon: _navItems[_currentIndex].activeIcon,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.lightInk.withOpacity(0.08),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              _buildHeaderCircle(
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const Spacer(),
              _buildHeaderCircle(
                background: const LinearGradient(
                  colors: [
                    AppColors.dashboardAvatarStart,
                    AppColors.dashboardAvatarEnd,
                  ],
                ),
                glowColor: AppColors.dashboardAvatarEnd,
                child: ClipOval(
                  child: _profileImageUrl != null
                      ? Image.network(
                          _profileImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) {
                            return _HeaderProfileFallback(
                              letter: _profileFallbackLetter,
                            );
                          },
                        )
                      : _HeaderProfileFallback(
                          letter: _profileFallbackLetter,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCircle({
    required Widget child,
    LinearGradient? background,
    Color? glowColor,
  }) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: background == null ? Colors.white : null,
        gradient: background,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (glowColor ?? AppColors.lightInk).withOpacity(
              glowColor == null ? 0.05 : 0.28,
            ),
            blurRadius: glowColor == null ? 12 : 18,
            offset: Offset(0, glowColor == null ? 4 : 8),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildDashboard() {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroCard(),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.dashboardPanelStart,
                    AppColors.dashboardPanelMid,
                    AppColors.dashboardPanelEnd,
                  ],
                ),
              ),
              child: Column(
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _shortcuts.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.82,
                    ),
                    itemBuilder: (context, index) {
                      final shortcut = _shortcuts[index];
                      return _DashboardShortcutTile(
                        shortcut: shortcut,
                        onTap: () {},
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
    );
  }

  Widget _buildHeroCard() {
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
                'Hi, $_safeUserName',
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

  Widget _buildBottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.lightInk.withOpacity(0.07),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Row(
            children: List.generate(_navItems.length, (index) {
              final item = _navItems[index];
              final isSelected = _currentIndex == index;

              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _handleBottomNavTap(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected ? item.activeIcon : item.icon,
                          size: 27,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.dashboardMuted,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.dashboardMuted,
                            fontSize: 10.5,
                            fontWeight: isSelected
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _glowOrb({
    required Color color,
    required double size,
  }) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(0.72),
              color.withOpacity(0.24),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _BottomNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}

class _DashboardShortcut {
  final String label;
  final IconData icon;
  final Color color;

  const _DashboardShortcut({
    required this.label,
    required this.icon,
    required this.color,
  });
}

class _DashboardShortcutTile extends StatelessWidget {
  final _DashboardShortcut shortcut;
  final VoidCallback onTap;

  const _DashboardShortcutTile({
    required this.shortcut,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.lightInk.withOpacity(0.07),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.lightBorderSoft,
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
                style: const TextStyle(
                  color: AppColors.dashboardText,
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

class _HeaderProfileFallback extends StatelessWidget {
  final String letter;

  const _HeaderProfileFallback({
    required this.letter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.dashboardAvatarFallback,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          color: AppColors.dashboardAvatarText,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ComingSoonPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ComingSoonPage({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppColors.lightInk.withOpacity(0.06),
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
                    color: AppColors.primary.withOpacity(0.10),
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
                  style: const TextStyle(
                    color: AppColors.lightTextPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.lightTextSecondary,
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
                    color: AppColors.primary.withOpacity(0.08),
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
