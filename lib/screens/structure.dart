import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:msitlms/config/appConfig.dart';
import 'package:msitlms/screens/common/dashboard/dashboard_page.dart';
import 'package:msitlms/screens/common/profile/profile_page.dart';
import 'package:msitlms/screens/modules/assignments/my_assignments_page.dart';
import 'package:msitlms/screens/modules/exam/my_quizz_page.dart';
import 'package:msitlms/screens/modules/notices/my_notices_page.dart';
import 'package:msitlms/screens/modules/study_materials/my_study_materials_page.dart';
import 'package:msitlms/screens/modules/syllabus/my_syllabus_page.dart';
import 'package:msitlms/screens/widgets/coming_soon_page.dart';
import 'package:msitlms/theme/app_colors.dart';

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
      label: 'Notice',
      icon: Icons.notifications_none_rounded,
      activeIcon: Icons.notifications_rounded,
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

  static const List<StudentDashboardShortcut> _shortcuts = [
    StudentDashboardShortcut(
      label: 'Syllabus',
      icon: Icons.menu_book_outlined,
      color: AppColors.syllabus,
    ),
    StudentDashboardShortcut(
      label: 'Lesson Plan',
      icon: Icons.map_outlined,
      color: AppColors.lessonPlan,
    ),
    StudentDashboardShortcut(
      label: 'Notices',
      icon: Icons.notifications_none_rounded,
      color: AppColors.notices,
    ),
    StudentDashboardShortcut(
      label: 'Materials',
      icon: Icons.article_outlined,
      color: AppColors.materials,
    ),
    StudentDashboardShortcut(
      label: 'Assignments',
      icon: Icons.assignment_outlined,
      color: AppColors.assignments,
    ),
    StudentDashboardShortcut(
      label: 'Quizzes',
      icon: Icons.help_outline_rounded,
      color: AppColors.quizzes,
    ),
    StudentDashboardShortcut(
      label: 'Result',
      icon: Icons.workspace_premium_outlined,
      color: AppColors.result,
    ),
    StudentDashboardShortcut(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      color: AppColors.profile,
    ),
  ];

  late int _currentIndex;
  String? _profileImageUrl;
  String? _profileAvatarText;
  String _displayUserName = 'Student';

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _navItems.length - 1).toInt();
    _displayUserName = widget.userName?.trim().isNotEmpty == true
        ? widget.userName!.trim()
        : 'Student';
    unawaited(_loadMiniProfile());
  }

  String get _safeUserName {
    final name = _displayUserName.trim();
    if (name.isEmpty) return 'Student';
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
                  'MSITLMS/1.0 (Flutter iOS/Android)',
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

  Future<void> _openProfilePage() async {
    final result = await Navigator.of(context).push<ProfilePageResult>(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          initialName: _safeUserName,
          initialImageUrl: _profileImageUrl,
          initialAvatarText: _profileAvatarText,
        ),
      ),
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        if (result.name != null && result.name!.trim().isNotEmpty) {
          _displayUserName = result.name!.trim();
        }
        if (result.imageUrl != null) {
          _profileImageUrl = result.imageUrl;
        }
        if (result.avatarText != null) {
          _profileAvatarText = result.avatarText;
        }
      });
    }

    unawaited(_loadMiniProfile());
  }

  void _handleDashboardShortcutTap(StudentDashboardShortcut shortcut) {
    final label = shortcut.label;

    if (label == 'Profile') {
      unawaited(_openProfilePage());
      return;
    }

    if (label == 'Syllabus') {
      _handleBottomNavTap(5);
      return;
    }

    if (label == 'Lesson Plan') {
      _handleBottomNavTap(5);
      return;
    }

    if (label == 'Notices') {
      _handleBottomNavTap(2);
      return;
    }

    if (label == 'Materials') {
      _handleBottomNavTap(1);
      return;
    }

    if (label == 'Assignments') {
      _handleBottomNavTap(3);
      return;
    }

    if (label == 'Quizzes' || label == 'Result') {
      _handleBottomNavTap(4);
      return;
    }

    _handleBottomNavTap(1);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = AppColors.background(context);
    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned(
            top: 220,
            left: -90,
            child: _glowOrb(
              color: AppColors.dashboardGlowStart(context),
              size: 300,
            ),
          ),
          Positioned(
            top: 340,
            right: -80,
            child: _glowOrb(
              color: AppColors.dashboardGlowEnd(context),
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
                        ? StudentDashboardPage(
                            userName: _safeUserName,
                            shortcuts: _shortcuts,
                            onShortcutTap: _handleDashboardShortcutTap,
                          )
                        : _currentIndex == 1
                            ? const MyStudyMaterialsPage()
                        : _currentIndex == 2
                            ? const MyNoticesPage()
                        : _currentIndex == 3
                            ? const MyAssignmentsPage()
                        : _currentIndex == 4
                            ? MyQuizzPage(
                                onBackToDashboard: () {
                                  if (!mounted) return;
                                  setState(() {
                                    _currentIndex = 0;
                                  });
                                },
                              )
                        : _currentIndex == 5
                            ? const MySyllabusPage()
                        : ComingSoonPage(
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
    final surfaceColor = AppColors.surface(context);
    final inkColor = AppColors.ink(context);
    final borderColor = AppColors.borderSoft(context);
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
        boxShadow: [
          BoxShadow(
            color: inkColor.withOpacity(0.035),
            blurRadius: 8,
            offset: const Offset(0, 1),
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
              GestureDetector(
                onTap: _openProfilePage,
                child: _buildHeaderCircle(
                  background: const LinearGradient(
                    colors: [
                      AppColors.dashboardAvatarStart,
                      AppColors.dashboardAvatarEnd,
                    ],
                  ),
                  showShadow: false,
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
    bool showShadow = true,
  }) {
    final surfaceColor = AppColors.surface(context);
    final inkColor = AppColors.ink(context);
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: background == null ? surfaceColor : null,
        gradient: background,
        shape: BoxShape.circle,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: (glowColor ?? inkColor).withOpacity(
                    glowColor == null ? 0.05 : 0.28,
                  ),
                  blurRadius: glowColor == null ? 12 : 18,
                  offset: Offset(0, glowColor == null ? 4 : 8),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  Widget _buildBottomNavigation() {
    final surfaceColor = AppColors.surface(context);
    final inkColor = AppColors.ink(context);
    final mutedColor = AppColors.dashboardMutedColor(context);
    final borderColor = AppColors.borderSoft(context);
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          top: BorderSide(color: borderColor),
        ),
        boxShadow: [
          BoxShadow(
            color: inkColor.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
          child: Row(
            children: List.generate(_navItems.length, (index) {
              final item = _navItems[index];
              final isSelected = _currentIndex == index;

              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _handleBottomNavTap(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected ? item.activeIcon : item.icon,
                          size: 23,
                          color: isSelected
                              ? AppColors.primary
                              : mutedColor,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.primary
                                : mutedColor,
                            fontSize: 9.5,
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

class _HeaderProfileFallback extends StatelessWidget {
  final String letter;

  const _HeaderProfileFallback({
    required this.letter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.isDark(context)
          ? AppColors.surface3(context)
          : AppColors.dashboardAvatarFallback,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: AppColors.isDark(context)
              ? AppColors.textSecondary(context)
              : AppColors.dashboardAvatarText,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
