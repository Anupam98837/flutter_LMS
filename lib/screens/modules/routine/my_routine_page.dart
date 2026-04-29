import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:msitlms/config/appConfig.dart';
import 'package:msitlms/theme/app_colors.dart';

class MyRoutinePage extends StatefulWidget {
  final VoidCallback? onOpenSyllabus;

  const MyRoutinePage({
    super.key,
    this.onOpenSyllabus,
  });

  @override
  State<MyRoutinePage> createState() => _MyRoutinePageState();
}

class _MyRoutinePageState extends State<MyRoutinePage> {
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;
  int? _currentSemester;
  List<_RoutineSemester> _semesters = const <_RoutineSemester>[];

  @override
  void initState() {
    super.initState();
    _loadRoutine(showLoader: true);
  }

  Future<String> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token')?.trim() ?? '';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    return const [];
  }

  String _stringValue(dynamic value) => value?.toString().trim() ?? '';

  int? _intValue(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  Future<Map<String, dynamic>> _getJson({
    required String endpoint,
    required String token,
  }) async {
    final client = http.Client();

    try {
      final response = await client.get(
        Uri.parse(endpoint),
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
          HttpHeaders.userAgentHeader: 'MSITLMS/1.0 (Flutter iOS/Android)',
        },
      );

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

  ({List<_RoutineSemester> semesters, int? currentSemester})
  _extractRoutineData(Map<String, dynamic> payload) {
    final root = _asMap(payload['data']).isNotEmpty
        ? _asMap(payload['data'])
        : payload;
    final academic = _asMap(root['academic']);
    final summary = _asMap(root['summary']);
    final currentSemester = _intValue(academic['current_semester']) ??
        _intValue(summary['current_semester']);

    final semestersByNumber = <int, _RoutineSemester>{};

    for (final item in _asList(root['semesters'])) {
      final row = _asMap(item);
      final semester = _intValue(row['semester']) ?? _intValue(row['semester_no']);
      if (semester == null || semester <= 0) continue;
      if (currentSemester != null && semester > currentSemester) continue;

      final info = _extractSemesterInfo(row);
      semestersByNumber[semester] = _RoutineSemester(
        semester: semester,
        publicUuid: info.publicUuid,
        sectionId: info.sectionId,
        sectionCount: info.sectionCount,
        dayCount: info.dayCount,
        slotCount: info.slotCount,
      );
    }

    if (semestersByNumber.isEmpty) {
      final grouped = <int, List<Map<String, dynamic>>>{};
      for (final item in _asList(root['routines'])) {
        final row = _asMap(item);
        final semester = _intValue(row['semester']);
        if (semester == null || semester <= 0) continue;
        if (currentSemester != null && semester > currentSemester) continue;
        grouped.putIfAbsent(semester, () => <Map<String, dynamic>>[]).add(row);
      }

      for (final entry in grouped.entries) {
        final info = _extractFromRoutineRows(entry.value);
        semestersByNumber[entry.key] = _RoutineSemester(
          semester: entry.key,
          publicUuid: info.publicUuid,
          sectionId: info.sectionId,
          sectionCount: info.sectionCount,
          dayCount: info.dayCount,
          slotCount: info.slotCount,
        );
      }
    }

    final semesters = semestersByNumber.values.toList()
      ..sort((a, b) => b.semester.compareTo(a.semester));

    return (
      semesters: semesters,
      currentSemester: currentSemester,
    );
  }

  ({
    String publicUuid,
    int? sectionId,
    int sectionCount,
    int dayCount,
    int slotCount,
  }) _extractSemesterInfo(Map<String, dynamic> row) {
    final routines = <Map<String, dynamic>>[];

    void addRows(dynamic value, {Map<String, dynamic>? sectionPayload}) {
      if (value is List) {
        for (final item in value) {
          final normalized = _asMap(item);
          if (normalized.isNotEmpty) {
            routines.add({
              ...normalized,
              if (sectionPayload != null) '_section_payload': sectionPayload,
            });
          }
        }
        return;
      }

      if (value is Map) {
        for (final entry in value.entries) {
          final rows = _asList(entry.value);
          for (final item in rows) {
            final normalized = _asMap(item);
            if (normalized.isNotEmpty) {
              routines.add({
                ...normalized,
                'day_of_week': _stringValue(normalized['day_of_week']).isNotEmpty
                    ? normalized['day_of_week']
                    : entry.key,
                if (sectionPayload != null) '_section_payload': sectionPayload,
              });
            }
          }
        }
      }
    }

    addRows(row['routines']);
    addRows(row['days']);

    for (final section in _asList(row['sections'])) {
      final sectionMap = _asMap(section);
      addRows(sectionMap['routines'], sectionPayload: sectionMap);
      addRows(sectionMap['days'], sectionPayload: sectionMap);
    }

    return _extractFromRoutineRows(routines);
  }

  ({
    String publicUuid,
    int? sectionId,
    int sectionCount,
    int dayCount,
    int slotCount,
  }) _extractFromRoutineRows(List<Map<String, dynamic>> rows) {
    String publicUuid = '';
    int? sectionId;
    final sections = <String>{};
    final days = <String>{};

    for (final row in rows) {
      final nestedSection = _asMap(row['_section_payload']);
      final rowSectionId = _intValue(row['section']) ??
          _intValue(row['section_id']) ??
          _intValue(row['course_section_id']) ??
          _intValue(nestedSection['section_id']) ??
          _intValue(nestedSection['id']);

      if (rowSectionId != null) {
        sections.add(rowSectionId.toString());
        sectionId ??= rowSectionId;
      }

      final day = _stringValue(row['day_of_week']).isNotEmpty
          ? _stringValue(row['day_of_week'])
          : _stringValue(row['day']);
      if (day.isNotEmpty) {
        days.add(day);
      }

      final uuid = _stringValue(row['uuid']).isNotEmpty
          ? _stringValue(row['uuid'])
          : _stringValue(row['routine_uuid']).isNotEmpty
              ? _stringValue(row['routine_uuid'])
              : _stringValue(row['public_uuid']);

      if (publicUuid.isEmpty && uuid.isNotEmpty) {
        publicUuid = uuid;
      }
    }

    return (
      publicUuid: publicUuid,
      sectionId: sectionId,
      sectionCount: sections.isEmpty ? 1 : sections.length,
      dayCount: days.length,
      slotCount: rows.length,
    );
  }

  Future<void> _loadRoutine({required bool showLoader}) async {
    final token = await _readToken();
    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Session missing. Please login again.';
      });
      return;
    }

    setState(() {
      if (showLoader) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _errorMessage = null;
    });

    try {
      final result = await _getJson(
        endpoint: '${AppConfig.baseUrl}/api/routines/my-published',
        token: token,
      );

      final statusCode = result['statusCode'] as int;
      final payload = result['data'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        throw Exception(
          _stringValue(payload['message']).isNotEmpty
              ? _stringValue(payload['message'])
              : 'Failed to load routine.',
        );
      }

      final extracted = _extractRoutineData(payload);

      if (!mounted) return;
      setState(() {
        _semesters = extracted.semesters;
        _currentSemester = extracted.currentSemester;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _showOverlayNotice({
    required String title,
    required String message,
  }) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: borderColor),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Uri? _buildRoutineUri(_RoutineSemester semester) {
    if (semester.publicUuid.isEmpty) return null;
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/routine/public/${Uri.encodeComponent(semester.publicUuid)}',
    );
    if (semester.sectionId == null) {
      return uri;
    }
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'section_id': semester.sectionId.toString(),
      },
    );
  }

  Future<void> _openRoutinePage(_RoutineSemester semester) async {
    final uri = _buildRoutineUri(semester);
    if (uri == null) {
      await _showOverlayNotice(
        title: 'Routine',
        message: 'Public routine link is not available for this semester.',
      );
      return;
    }

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const HttpException('Unable to open routine page');
      }
    } catch (_) {
      await _showOverlayNotice(
        title: 'Routine',
        message: 'We could not open the routine page right now.',
      );
    }
  }

  Widget _buildHeader() {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSoft(context)),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'My Routine',
              style: TextStyle(
                color: textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            if (widget.onOpenSyllabus != null)
              TextButton.icon(
                onPressed: widget.onOpenSyllabus,
                icon: const Icon(
                  Icons.menu_book_outlined,
                  size: 16,
                ),
                label: const Text('Syllabus'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 0,
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(
                    fontSize: 12.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'View your published routine here',
          style: TextStyle(
            color: textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (_, __) {
        return Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderSoft(context)),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 62,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.surface3(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface3(context),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.event_busy_rounded,
              color: Color(0xFF6A717C),
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No routine found',
            style: TextStyle(
              color: textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _errorMessage ?? 'Published routine is not available right now.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemesterGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _semesters.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final semester = _semesters[index];
        return _RoutineSemesterCard(
          semester: semester,
          onTap: () => _openRoutinePage(semester),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.dashboardMutedColor(context);
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          color: muted,
          onRefresh: () => _loadRoutine(showLoader: false),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 2),
                  if (_loading)
                    _buildLoadingState()
                  else if (_semesters.isEmpty)
                    _buildEmptyState()
                  else
                    _buildSemesterGrid(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoutineSemesterCard extends StatelessWidget {
  final _RoutineSemester semester;
  final VoidCallback onTap;

  const _RoutineSemesterCard({
    required this.semester,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.borderSoft(context);
    final inkColor = AppColors.ink(context);
    final surfaceColor = AppColors.surface(context);
    final textPrimary = AppColors.textPrimary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          children: [
            Ink(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: inkColor.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.calendar_month_rounded,
                  size: 20,
                  color: Color(0xFF66707C),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Semester ${semester.semester}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textPrimary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineSemester {
  final int semester;
  final String publicUuid;
  final int? sectionId;
  final int sectionCount;
  final int dayCount;
  final int slotCount;

  const _RoutineSemester({
    required this.semester,
    required this.publicUuid,
    required this.sectionId,
    required this.sectionCount,
    required this.dayCount,
    required this.slotCount,
  });
}
