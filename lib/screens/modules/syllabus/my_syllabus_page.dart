import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:msitlms/config/appConfig.dart';
import 'package:msitlms/screens/modules/syllabus/lesson_plan_view_page.dart';
import 'package:msitlms/theme/app_colors.dart';

class MySyllabusPage extends StatefulWidget {
  const MySyllabusPage({super.key});

  @override
  State<MySyllabusPage> createState() => _MySyllabusPageState();
}

class _MySyllabusPageState extends State<MySyllabusPage> {
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;
  List<_SyllabusSemester> _semesters = const <_SyllabusSemester>[];
  int? _currentSemester;

  @override
  void initState() {
    super.initState();
    _loadSemesters(showLoader: true);
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

  String _plainText(dynamic value) {
    final raw = _stringValue(value);
    if (raw.isEmpty) return '';
    return raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

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

  _SyllabusSubject _normalizeSubject(
    Map<String, dynamic> raw,
    Map<String, dynamic> semesterRow,
  ) {
    return _SyllabusSubject(
      title: _stringValue(raw['subject_name']).isNotEmpty
          ? _stringValue(raw['subject_name'])
          : _stringValue(raw['name']).isNotEmpty
              ? _stringValue(raw['name'])
              : _stringValue(raw['title']),
      code: _stringValue(raw['subject_code']).isNotEmpty
          ? _stringValue(raw['subject_code'])
          : _stringValue(raw['code']),
      uuid: _stringValue(raw['syllabus_subject_uuid']).isNotEmpty
          ? _stringValue(raw['syllabus_subject_uuid'])
          : _stringValue(raw['subject_uuid']).isNotEmpty
              ? _stringValue(raw['subject_uuid'])
              : _stringValue(raw['uuid']),
      typeTitle: _stringValue(raw['subject_type_title']).isNotEmpty
          ? _stringValue(raw['subject_type_title'])
          : _stringValue(raw['subject_type_name']).isNotEmpty
              ? _stringValue(raw['subject_type_name'])
              : _stringValue(_asMap(raw['subject_type'])['title']).isNotEmpty
                  ? _stringValue(_asMap(raw['subject_type'])['title'])
                  : _stringValue(_asMap(raw['subject_type'])['name']),
      ltp: _stringValue(raw['l_t_p']).isNotEmpty
          ? _stringValue(raw['l_t_p'])
          : [
              _stringValue(raw['lecture_hours']).isNotEmpty
                  ? _stringValue(raw['lecture_hours'])
                  : '0',
              _stringValue(raw['tutorial_hours']).isNotEmpty
                  ? _stringValue(raw['tutorial_hours'])
                  : '0',
              _stringValue(raw['practical_hours']).isNotEmpty
                  ? _stringValue(raw['practical_hours'])
                  : '0',
            ].join('-'),
      topicText: _plainText(raw['topic_html']).isNotEmpty
          ? _plainText(raw['topic_html'])
          : _plainText(raw['description_html']),
      semester: _intValue(raw['semester']) ?? _intValue(semesterRow['semester']),
    );
  }

  ({List<_SyllabusSemester> semesters, int? currentSemester}) _extractSemesters(
    Map<String, dynamic> payload,
  ) {
    final root = _asMap(payload['data']).isNotEmpty
        ? _asMap(payload['data'])
        : payload;
    final academic = _asMap(root['academic']);
    final summary = _asMap(root['summary']);
    final currentSemester = _intValue(academic['current_semester']) ??
        _intValue(summary['semester']);
    final semestersByNumber = <int, _SyllabusSemester>{};

    for (final item in _asList(root['semesters'])) {
      final row = _asMap(item);
      final meta = _asMap(row['syllabus_meta']).isNotEmpty
          ? _asMap(row['syllabus_meta'])
          : _asMap(row['meta']);
      final semester = _intValue(row['semester']);
      if (semester == null || semester <= 0) {
        continue;
      }
      if (currentSemester != null && semester > currentSemester) {
        continue;
      }

      final subjects = _asList(row['subjects'])
          .map((subject) => _normalizeSubject(_asMap(subject), row))
          .where((subject) => subject.title.isNotEmpty || subject.code.isNotEmpty)
          .toList();

      semestersByNumber[semester] = _SyllabusSemester(
        semester: semester,
        downloadId: _stringValue(row['id']).isNotEmpty
            ? _stringValue(row['id'])
            : _stringValue(meta['id']).isNotEmpty
                ? _stringValue(meta['id'])
                : _stringValue(row['row_key']).isNotEmpty
                    ? _stringValue(row['row_key'])
                    : _stringValue(row['syllabus_code']).isNotEmpty
                        ? _stringValue(row['syllabus_code'])
                        : semester.toString(),
        courseTitle: _stringValue(row['course_title']).isNotEmpty
            ? _stringValue(row['course_title'])
            : _stringValue(row['course_name']).isNotEmpty
                ? _stringValue(row['course_name'])
                : _stringValue(academic['course_title']),
        courseCode: _stringValue(row['course_code']).isNotEmpty
            ? _stringValue(row['course_code'])
            : _stringValue(academic['course_code']),
        institutionName: _stringValue(row['institution_name']).isNotEmpty
            ? _stringValue(row['institution_name'])
            : _stringValue(academic['institution_name']),
        intakeYear: _stringValue(row['intake_year']).isNotEmpty
            ? _stringValue(row['intake_year'])
            : _stringValue(row['year']).isNotEmpty
                ? _stringValue(row['year'])
                : _stringValue(academic['admission_year']),
        syllabusCode: _stringValue(row['syllabus_code']).isNotEmpty
            ? _stringValue(row['syllabus_code'])
            : _stringValue(meta['syllabus_code']),
        publicUuid: _stringValue(row['public_uuid']).isNotEmpty
            ? _stringValue(row['public_uuid'])
            : _stringValue(meta['public_uuid']).isNotEmpty
                ? _stringValue(meta['public_uuid'])
                : _stringValue(row['uuid']).isNotEmpty
                    ? _stringValue(row['uuid'])
                    : _stringValue(meta['uuid']).isNotEmpty
                        ? _stringValue(meta['uuid'])
                        : subjects.isNotEmpty
                            ? subjects.first.uuid
                            : '',
        creditPattern: _stringValue(meta['credit_pattern']),
        prerequisites: _plainText(meta['prerequisites_html']),
        generalInstructions: _plainText(meta['general_instructions_html']),
        courseOutcomes: _plainText(meta['course_outcomes_html']),
        programOutcomes: _plainText(meta['program_outcomes_html']),
        textbooks: _plainText(meta['textbooks_html']),
        referenceBooks: _plainText(meta['reference_books_html']),
        onlineResources: _plainText(meta['online_resources_html']),
        subjects: subjects,
      );
    }

    if (semestersByNumber.isEmpty) {
      final semester = _intValue(summary['semester']) ??
          _intValue(_asMap(root['syllabus_meta'])['semester']);
      final meta = _asMap(root['syllabus_meta']);
      final subjects = _asList(root['subjects'])
          .map((subject) => _normalizeSubject(_asMap(subject), root))
          .where((subject) => subject.title.isNotEmpty || subject.code.isNotEmpty)
          .toList();

      if (semester != null &&
          semester > 0 &&
          (currentSemester == null || semester <= currentSemester)) {
        semestersByNumber[semester] = _SyllabusSemester(
          semester: semester,
          downloadId: _stringValue(root['id']).isNotEmpty
              ? _stringValue(root['id'])
              : _stringValue(meta['id']).isNotEmpty
                  ? _stringValue(meta['id'])
                  : _stringValue(summary['syllabus_code']).isNotEmpty
                      ? _stringValue(summary['syllabus_code'])
                      : semester.toString(),
          courseTitle: _stringValue(summary['course_title']).isNotEmpty
              ? _stringValue(summary['course_title'])
              : _stringValue(academic['course_title']),
          courseCode: _stringValue(summary['course_code']).isNotEmpty
              ? _stringValue(summary['course_code'])
              : _stringValue(academic['course_code']),
          institutionName: _stringValue(academic['institution_name']),
          intakeYear: _stringValue(summary['year']).isNotEmpty
              ? _stringValue(summary['year'])
              : _stringValue(academic['admission_year']),
          syllabusCode: _stringValue(summary['syllabus_code']).isNotEmpty
              ? _stringValue(summary['syllabus_code'])
              : _stringValue(meta['syllabus_code']),
          publicUuid: _stringValue(root['public_uuid']).isNotEmpty
              ? _stringValue(root['public_uuid'])
              : _stringValue(meta['public_uuid']).isNotEmpty
                  ? _stringValue(meta['public_uuid'])
                  : _stringValue(root['uuid']).isNotEmpty
                      ? _stringValue(root['uuid'])
                      : _stringValue(meta['uuid']).isNotEmpty
                          ? _stringValue(meta['uuid'])
                          : subjects.isNotEmpty
                              ? subjects.first.uuid
                              : '',
          creditPattern: _stringValue(meta['credit_pattern']),
          prerequisites: _plainText(meta['prerequisites_html']),
          generalInstructions: _plainText(meta['general_instructions_html']),
          courseOutcomes: _plainText(meta['course_outcomes_html']),
          programOutcomes: _plainText(meta['program_outcomes_html']),
          textbooks: _plainText(meta['textbooks_html']),
          referenceBooks: _plainText(meta['reference_books_html']),
          onlineResources: _plainText(meta['online_resources_html']),
          subjects: subjects,
        );
      }
    }

    final semesters = semestersByNumber.values.toList()
      ..sort((a, b) => a.semester.compareTo(b.semester));

    return (semesters: semesters, currentSemester: currentSemester);
  }

  Future<void> _loadSemesters({required bool showLoader}) async {
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
        endpoint: '${AppConfig.baseUrl}/api/syllabus-subjects/my-syllabus',
        token: token,
      );

      final statusCode = result['statusCode'] as int;
      final payload = result['data'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        throw Exception(
          _stringValue(payload['message']).isNotEmpty
              ? _stringValue(payload['message'])
              : 'Failed to load syllabus.',
        );
      }

      final extracted = _extractSemesters(payload);

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

  Future<void> _showOverlayNotice(
    BuildContext overlayContext, {
    required String title,
    required String message,
  }) {
    final textPrimary = AppColors.textPrimary(overlayContext);
    final textSecondary = AppColors.textSecondary(overlayContext);
    final surfaceColor = AppColors.surface(overlayContext);
    final borderColor = AppColors.borderSoft(overlayContext);
    return showDialog<void>(
      context: overlayContext,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: surfaceColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: borderColor),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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

  Future<void> _downloadSemesterSyllabus(
    BuildContext overlayContext,
    _SyllabusSemester semester,
  ) async {
    final token = await _readToken();
    if (token.isEmpty) {
      if (!mounted) return;
      await _showOverlayNotice(
        overlayContext,
        title: 'Download',
        message: 'Session missing. Please login again.',
      );
      return;
    }

    final downloadId = semester.downloadId;
    if (downloadId.isEmpty) {
      await _showOverlayNotice(
        overlayContext,
        title: 'Download',
        message: 'Technical issue. Download is not possible right now.',
      );
      return;
    }

    final client = http.Client();
    try {
      final response = await client.get(
        Uri.parse(
          '${AppConfig.baseUrl}/syllabus/download/${Uri.encodeComponent(downloadId)}',
        ),
        headers: {
          HttpHeaders.acceptHeader: 'application/pdf,application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
          HttpHeaders.userAgentHeader: 'MSITLMS/1.0 (Flutter iOS/Android)',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _showOverlayNotice(
          overlayContext,
          title: 'Download',
          message:
              'Syllabus download request completed successfully.',
        );
        return;
      }

      await _showOverlayNotice(
        overlayContext,
        title: 'Download',
        message: 'Technical issue. Download is not possible right now.',
      );
    } catch (_) {
      await _showOverlayNotice(
        overlayContext,
        title: 'Download',
        message: 'Technical issue. Download is not possible right now.',
      );
    } finally {
      client.close();
    }
  }

  Future<void> _openLessonPlanPage(
    BuildContext sheetContext,
    _SyllabusSubject subject,
  ) async {
    if (subject.uuid.isEmpty) {
      await _showOverlayNotice(
        sheetContext,
        title: 'Lesson Plan',
        message: 'Lesson plan is not available for this subject right now.',
      );
      return;
    }

    Navigator.of(sheetContext).pop();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LessonPlanViewPage(
          subjectUuid: subject.uuid,
          subjectTitle: subject.title,
        ),
      ),
    );
  }

  void _openSyllabusPreviewSheet(
    BuildContext overlayContext,
    _SyllabusSemester semester,
  ) {
    final surfaceColor = AppColors.surface(overlayContext);
    final textPrimary = AppColors.textPrimary(overlayContext);
    final textSecondary = AppColors.textSecondary(overlayContext);
    final borderColor = AppColors.borderSoft(overlayContext);
    final softFill = AppColors.surface3(overlayContext);

    showModalBottomSheet<void>(
      context: overlayContext,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (previewContext) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(previewContext).size.height * 0.9,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: borderColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Semester ${semester.semester} Syllabus',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              semester.courseTitle.isNotEmpty
                                  ? semester.courseTitle
                                  : 'Syllabus Preview',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _openPublicSyllabusPage(previewContext, semester),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Syllabus'),
                      ),
                    ],
                  ),
                ),
                Divider(color: borderColor, height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (semester.institutionName.isNotEmpty)
                          Text(
                            semester.institutionName,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        if (semester.courseTitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            semester.courseTitle,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _PreviewInfoGrid(semester: semester),
                        if (semester.prerequisites.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _PreviewSection(
                            title: 'Pre-Requisite',
                            content: semester.prerequisites,
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          'Subjects',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: softFill,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: borderColor),
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < semester.subjects.length; i++) ...[
                                _PreviewSubjectRow(subject: semester.subjects[i]),
                                if (i != semester.subjects.length - 1)
                                  Divider(color: borderColor, height: 1),
                              ],
                            ],
                          ),
                        ),
                        for (final section in semester.metaSections)
                          if (section.content.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _PreviewSection(
                              title: section.title,
                              content: section.content,
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPublicSyllabusPage(
    BuildContext overlayContext,
    _SyllabusSemester semester,
  ) async {
    if (semester.publicUuid.isEmpty) {
      await _showOverlayNotice(
        overlayContext,
        title: 'Syllabus',
        message: 'Public syllabus link is not available for this semester.',
      );
      return;
    }

    if (Navigator.of(overlayContext).canPop()) {
      Navigator.of(overlayContext).pop();
    }

    final uri = Uri.parse(
      '${AppConfig.baseUrl}/syllabus/public/${Uri.encodeComponent(semester.publicUuid)}',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const HttpException('Unable to open syllabus page');
      }
    } catch (_) {
      await _showOverlayNotice(
        overlayContext,
        title: 'Syllabus',
        message: 'We could not open the syllabus page right now.',
      );
    }
  }

  void _openSemesterSheet(_SyllabusSemester semester) {
    final surfaceColor = AppColors.surface(context);
    final softFill = AppColors.surface3(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = AppColors.borderSoft(context);
    final muted = AppColors.dashboardMutedColor(context);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.78,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: borderColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Semester ${semester.semester}',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${semester.subjects.length} subject${semester.subjects.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _openPublicSyllabusPage(sheetContext, semester),
                        icon: const Icon(Icons.menu_book_rounded, size: 16),
                        label: const Text('Syllabus'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: textPrimary,
                          side: BorderSide(color: borderColor),
                          backgroundColor: softFill,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (semester.courseTitle.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      semester.courseTitle,
                      style: TextStyle(
                        color: muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Divider(color: borderColor, height: 1),
                  const SizedBox(height: 6),
                  Text(
                    'Subjects',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: semester.subjects.isEmpty
                        ? Center(
                            child: Text(
                              'No subjects available for this semester yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: semester.subjects.length,
                            separatorBuilder: (_, __) =>
                                Divider(color: borderColor, height: 1),
                            itemBuilder: (context, index) {
                              final subject = semester.subjects[index];
                              return _SubjectRow(
                                subject: subject,
                                onLessonPlanTap: () =>
                                    _openLessonPlanPage(sheetContext, subject),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.16),
                ),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'My Syllabus',
              style: TextStyle(
                color: textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'View your syllabus and lesson plan here',
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
              Icons.menu_book_rounded,
              color: Color(0xFF6A717C),
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No syllabus found',
            style: TextStyle(
              color: textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _errorMessage ?? 'Semester data is not available right now.',
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
        return _SemesterCard(
          semester: semester.semester,
          onTap: () => _openSemesterSheet(semester),
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
          onRefresh: () => _loadSemesters(showLoader: false),
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

class _SemesterCard extends StatelessWidget {
  final int semester;
  final VoidCallback onTap;

  const _SemesterCard({
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
                  Icons.menu_book_rounded,
                  size: 20,
                  color: Color(0xFF66707C),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Semester $semester',
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

class _SubjectRow extends StatelessWidget {
  final _SyllabusSubject subject;
  final VoidCallback onLessonPlanTap;

  const _SubjectRow({
    required this.subject,
    required this.onLessonPlanTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = AppColors.borderSoft(context);
    final softFill = AppColors.surface3(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: softFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Icon(
              Icons.article_outlined,
              size: 18,
              color: textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  subject.title.isNotEmpty ? subject.title : 'Untitled Subject',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subject.code.isNotEmpty ? subject.code : 'No code available',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onLessonPlanTap,
            style: TextButton.styleFrom(
              foregroundColor: textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('Lesson Plan'),
                SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyllabusSemester {
  final int semester;
  final String? _downloadId;
  final String? _publicUuid;
  final String? _courseTitle;
  final String? _courseCode;
  final String? _institutionName;
  final String? _intakeYear;
  final String? _syllabusCode;
  final String? _creditPattern;
  final String? _prerequisites;
  final String? _generalInstructions;
  final String? _courseOutcomes;
  final String? _programOutcomes;
  final String? _textbooks;
  final String? _referenceBooks;
  final String? _onlineResources;
  final List<_SyllabusSubject>? _subjects;

  const _SyllabusSemester({
    required this.semester,
    String? downloadId,
    String? publicUuid,
    String? courseTitle,
    String? courseCode,
    String? institutionName,
    String? intakeYear,
    String? syllabusCode,
    String? creditPattern,
    String? prerequisites,
    String? generalInstructions,
    String? courseOutcomes,
    String? programOutcomes,
    String? textbooks,
    String? referenceBooks,
    String? onlineResources,
    List<_SyllabusSubject>? subjects,
  })  : _downloadId = downloadId,
        _publicUuid = publicUuid,
        _courseTitle = courseTitle,
        _courseCode = courseCode,
        _institutionName = institutionName,
        _intakeYear = intakeYear,
        _syllabusCode = syllabusCode,
        _creditPattern = creditPattern,
        _prerequisites = prerequisites,
        _generalInstructions = generalInstructions,
        _courseOutcomes = courseOutcomes,
        _programOutcomes = programOutcomes,
        _textbooks = textbooks,
        _referenceBooks = referenceBooks,
        _onlineResources = onlineResources,
        _subjects = subjects;

  String get downloadId => _downloadId ?? '';
  String get publicUuid => _publicUuid ?? '';
  String get courseTitle => _courseTitle ?? '';
  String get courseCode => _courseCode ?? '';
  String get institutionName => _institutionName ?? '';
  String get intakeYear => _intakeYear ?? '';
  String get syllabusCode => _syllabusCode ?? '';
  String get creditPattern => _creditPattern ?? '';
  String get prerequisites => _prerequisites ?? '';
  String get generalInstructions => _generalInstructions ?? '';
  String get courseOutcomes => _courseOutcomes ?? '';
  String get programOutcomes => _programOutcomes ?? '';
  String get textbooks => _textbooks ?? '';
  String get referenceBooks => _referenceBooks ?? '';
  String get onlineResources => _onlineResources ?? '';
  List<_SyllabusSubject> get subjects => _subjects ?? const <_SyllabusSubject>[];

  List<_PreviewMetaSection> get metaSections => [
        _PreviewMetaSection(
          title: 'General Instructions',
          content: generalInstructions,
        ),
        _PreviewMetaSection(
          title: 'Course Outcomes',
          content: courseOutcomes,
        ),
        _PreviewMetaSection(
          title: 'Program Outcomes',
          content: programOutcomes,
        ),
        _PreviewMetaSection(
          title: 'Textbooks',
          content: textbooks,
        ),
        _PreviewMetaSection(
          title: 'Reference Books',
          content: referenceBooks,
        ),
        _PreviewMetaSection(
          title: 'Online Resources',
          content: onlineResources,
        ),
      ];
}

class _SyllabusSubject {
  final String? _title;
  final String? _code;
  final String? _uuid;
  final String? _typeTitle;
  final String? _ltp;
  final String? _topicText;
  final int? semester;

  const _SyllabusSubject({
    String? title,
    String? code,
    String? uuid,
    String? typeTitle,
    String? ltp,
    String? topicText,
    required this.semester,
  })  : _title = title,
        _code = code,
        _uuid = uuid,
        _typeTitle = typeTitle,
        _ltp = ltp,
        _topicText = topicText;

  String get title => _title ?? '';
  String get code => _code ?? '';
  String get uuid => _uuid ?? '';
  String get typeTitle => _typeTitle ?? '';
  String get ltp => _ltp ?? '';
  String get topicText => _topicText ?? '';
}

class _PreviewInfoGrid extends StatelessWidget {
  final _SyllabusSemester semester;

  const _PreviewInfoGrid({
    required this.semester,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.borderSoft(context);
    final surfaceColor = AppColors.surface(context);
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          _PreviewInfoRow(label: 'Course Code', value: semester.courseCode),
          _PreviewInfoRow(label: 'Syllabus Code', value: semester.syllabusCode),
          _PreviewInfoRow(
            label: 'Semester',
            value: semester.semester.toString(),
          ),
          _PreviewInfoRow(label: 'L-T-P', value: semester.creditPattern),
          _PreviewInfoRow(label: 'Year', value: semester.intakeYear, isLast: true),
        ],
      ),
    );
  }
}

class _PreviewInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _PreviewInfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = AppColors.borderSoft(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: borderColor),
              ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '—',
              style: TextStyle(
                color: textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSubjectRow extends StatelessWidget {
  final _SyllabusSubject subject;

  const _PreviewSubjectRow({
    required this.subject,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subject.title.isNotEmpty ? subject.title : 'Untitled Subject',
            style: TextStyle(
              color: textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                subject.code.isNotEmpty ? subject.code : '—',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subject.ltp.isNotEmpty)
                Text(
                  'L-T-P ${subject.ltp}',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (subject.typeTitle.isNotEmpty)
                Text(
                  subject.typeTitle,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (subject.topicText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subject.topicText,
              style: TextStyle(
                color: textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final String title;
  final String content;

  const _PreviewSection({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = AppColors.borderSoft(context);
    final surfaceColor = AppColors.surface(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewMetaSection {
  final String title;
  final String content;

  const _PreviewMetaSection({
    required this.title,
    required this.content,
  });
}
