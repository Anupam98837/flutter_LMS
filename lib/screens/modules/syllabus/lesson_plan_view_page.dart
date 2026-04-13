import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hallienzlms/config/appConfig.dart';
import 'package:hallienzlms/theme/app_colors.dart';

class LessonPlanViewPage extends StatefulWidget {
  final String subjectUuid;
  final String subjectTitle;

  const LessonPlanViewPage({
    super.key,
    required this.subjectUuid,
    required this.subjectTitle,
  });

  @override
  State<LessonPlanViewPage> createState() => _LessonPlanViewPageState();
}

class _LessonPlanViewPageState extends State<LessonPlanViewPage> {
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;
  _LessonPlanPayload? _payload;

  @override
  void initState() {
    super.initState();
    _loadLessonPlan(showLoader: true);
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

  String _string(dynamic value) => value?.toString().trim() ?? '';

  String _htmlToText(dynamic value) {
    final raw = _string(value);
    if (raw.isEmpty) return '';
    return raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'</li\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  Future<void> _showNotice({
    required String title,
    required String message,
  }) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);

    return showDialog<void>(
      context: context,
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

  _LessonPlanPayload _parsePayload(Map<String, dynamic> payload) {
    final root = _asMap(payload['data']).isNotEmpty
        ? _asMap(payload['data'])
        : payload;
    final subjectMap = _asMap(root['syllabus_subject']);
    final summaryMap = _asMap(root['summary']);
    final lessons = _asList(root['lesson_plans'])
        .map((lesson) => _parseLesson(_asMap(lesson)))
        .toList();

    final subjectTypeMap = _asMap(subjectMap['subject_type']);

    return _LessonPlanPayload(
      subject: _LessonSubject(
        name: _string(subjectMap['subject_name']),
        courseName: _string(subjectMap['course_name']),
        semester: _string(subjectMap['semester']),
        intakeYear: _string(subjectMap['intake_year']),
        syllabusCode: _string(subjectMap['syllabus_code']),
        subjectCode: _string(subjectMap['subject_code']),
        status: _string(subjectMap['status']),
        institutionName: _string(subjectMap['institution_name']),
        subjectType: _string(subjectMap['subject_type_title']).isNotEmpty
            ? _string(subjectMap['subject_type_title'])
            : _string(subjectMap['subject_type_name']).isNotEmpty
                ? _string(subjectMap['subject_type_name'])
                : _string(subjectTypeMap['title']).isNotEmpty
                    ? _string(subjectTypeMap['title'])
                    : _string(subjectTypeMap['name']).isNotEmpty
                        ? _string(subjectTypeMap['name'])
                        : _string(subjectMap['subject_type']),
        creditPoints: _string(subjectMap['credit_points']),
        lectureHours: _string(subjectMap['lecture_hours']),
        tutorialHours: _string(subjectMap['tutorial_hours']),
        practicalHours: _string(subjectMap['practical_hours']),
        topicText: _htmlToText(subjectMap['topic_html']),
      ),
      lessonCount: _string(summaryMap['lesson_plan_count']).isNotEmpty
          ? _string(summaryMap['lesson_plan_count'])
          : lessons.length.toString(),
      lessons: lessons,
    );
  }

  _LessonPlanItem _parseLesson(Map<String, dynamic> map) {
    return _LessonPlanItem(
      lessonNo: _string(map['lesson_no']),
      title: _string(map['lesson_title']),
      unitTitle: _string(map['unit_title']),
      lessonType: _string(map['lesson_type']),
      deliveryMode: _string(map['delivery_mode']),
      completionStatus: _string(map['completion_status']),
      durationHours: _string(map['duration_hours']),
      topicText: _htmlToText(map['topic_html']),
      learningObjectives: _htmlToText(map['learning_objectives_html']),
      teachingMethod: _htmlToText(map['teaching_method_html']),
      assessmentMethod: _htmlToText(map['assessment_method_html']),
      referenceMaterial: _htmlToText(map['reference_material_html']),
      remarks: _htmlToText(map['remarks_html']),
    );
  }

  Future<void> _loadLessonPlan({required bool showLoader}) async {
    if (widget.subjectUuid.trim().isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = 'Lesson plan UUID is missing.';
      });
      return;
    }

    final token = await _readToken();

    setState(() {
      if (showLoader) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _errorMessage = null;
    });

    final client = http.Client();
    try {
      final response = await client.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/syllabus-lesson-plans/syllabus-subject/${Uri.encodeComponent(widget.subjectUuid)}/full',
        ),
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          if (token.isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $token',
          HttpHeaders.userAgentHeader: 'HallienzLMS/1.0 (Flutter iOS/Android)',
        },
      );

      dynamic decoded;
      try {
        decoded = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      } catch (_) {
        decoded = {};
      }

      final payload = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _string(payload['message']).isNotEmpty
              ? _string(payload['message'])
              : 'Unable to load lesson plan.',
        );
      }

      if (!mounted) return;
      setState(() {
        _payload = _parsePayload(payload);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      client.close();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Widget _buildHeader(_LessonPlanPayload payload) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final chips = <Widget>[
      if (payload.subject.syllabusCode.isNotEmpty)
        _InfoChip(label: payload.subject.syllabusCode),
      if (payload.subject.subjectCode.isNotEmpty)
        _InfoChip(label: payload.subject.subjectCode),
      if (payload.subject.status.isNotEmpty)
        _InfoChip(label: payload.subject.status),
    ];

    final subtitleParts = [
      if (payload.subject.courseName.isNotEmpty) payload.subject.courseName,
      if (payload.subject.semester.isNotEmpty)
        'Semester ${payload.subject.semester}',
      if (payload.subject.intakeYear.isNotEmpty)
        'Intake ${payload.subject.intakeYear}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          payload.subject.name.isNotEmpty
              ? payload.subject.name
              : widget.subjectTitle,
          style: TextStyle(
            color: textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        if (subtitleParts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            subtitleParts.join(' • '),
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
        ],
      ],
    );
  }

  Widget _buildOverview(_LessonPlanPayload payload) {
    final borderColor = AppColors.borderSoft(context);
    final surfaceColor = AppColors.surface(context);
    final textPrimary = AppColors.textPrimary(context);
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Overview',
              style: TextStyle(
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Institution',
            value: payload.subject.institutionName,
          ),
          _InfoRow(
            label: 'Course',
            value: payload.subject.courseName,
          ),
          _InfoRow(
            label: 'Paper Code',
            value: payload.subject.subjectCode,
          ),
          _InfoRow(
            label: 'Subject Type',
            value: payload.subject.subjectType,
          ),
          _InfoRow(
            label: 'Semester / Intake',
            value: [
              if (payload.subject.semester.isNotEmpty)
                'Sem ${payload.subject.semester}',
              if (payload.subject.intakeYear.isNotEmpty)
                payload.subject.intakeYear,
            ].join(' • '),
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(_LessonPlanPayload payload) {
    final borderColor = AppColors.borderSoft(context);
    final surfaceColor = AppColors.surface(context);
    final textPrimary = AppColors.textPrimary(context);
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Key Metrics',
              style: TextStyle(
                color: textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _InfoRow(
            label: 'Credit Points',
            value: payload.subject.creditPoints,
          ),
          _InfoRow(
            label: 'L / T / P',
            value: [
              payload.subject.lectureHours.isNotEmpty
                  ? payload.subject.lectureHours
                  : '—',
              payload.subject.tutorialHours.isNotEmpty
                  ? payload.subject.tutorialHours
                  : '—',
              payload.subject.practicalHours.isNotEmpty
                  ? payload.subject.practicalHours
                  : '—',
            ].join(' / '),
          ),
          _InfoRow(
            label: 'Total Lessons',
            value: payload.lessonCount,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required String content,
  }) {
    if (content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final borderColor = AppColors.borderSoft(context);
    final surfaceColor = AppColors.surface(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonCard(_LessonPlanItem lesson, int index) {
    final borderColor = AppColors.borderSoft(context);
    final surfaceColor = AppColors.surface(context);
    final softFill = AppColors.surface3(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final lessonNumber = lesson.lessonNo.isNotEmpty
        ? lesson.lessonNo
        : (index + 1).toString().padLeft(2, '0');

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: softFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    lessonNumber,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.title.isNotEmpty
                            ? lesson.title
                            : 'Lesson $lessonNumber',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                        ),
                      ),
                      if (lesson.unitTitle.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          lesson.unitTitle,
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: lesson.lessonType, fallback: 'Lesson Type'),
                _InfoChip(label: lesson.deliveryMode, fallback: 'Delivery'),
                _InfoChip(label: lesson.completionStatus, fallback: 'Status'),
                _InfoChip(
                  label: lesson.durationHours.isNotEmpty
                      ? '${lesson.durationHours} hrs'
                      : '',
                  fallback: 'Duration',
                ),
              ],
            ),
            if (lesson.topicText.isNotEmpty) ...[
              const SizedBox(height: 14),
              _LessonMiniSection(
                title: 'Topic Details',
                content: lesson.topicText,
              ),
            ],
            if (lesson.learningObjectives.isNotEmpty ||
                lesson.teachingMethod.isNotEmpty) ...[
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 560;
                  final children = <Widget>[
                    if (lesson.learningObjectives.isNotEmpty)
                      _LessonMiniSection(
                        title: 'Learning Objectives',
                        content: lesson.learningObjectives,
                      ),
                    if (lesson.teachingMethod.isNotEmpty)
                      _LessonMiniSection(
                        title: 'Teaching Method',
                        content: lesson.teachingMethod,
                      ),
                  ];

                  if (!isWide || children.length == 1) {
                    return Column(
                      children: [
                        for (int i = 0; i < children.length; i++) ...[
                          children[i],
                          if (i != children.length - 1)
                            const SizedBox(height: 12),
                        ],
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: children[0]),
                      const SizedBox(width: 12),
                      Expanded(child: children[1]),
                    ],
                  );
                },
              ),
            ],
            if (lesson.assessmentMethod.isNotEmpty) ...[
              const SizedBox(height: 14),
              _LessonMiniSection(
                title: 'Assessment Method',
                content: lesson.assessmentMethod,
              ),
            ],
            if (lesson.referenceMaterial.isNotEmpty) ...[
              const SizedBox(height: 14),
              _LessonMiniSection(
                title: 'Reference Material',
                content: lesson.referenceMaterial,
              ),
            ],
            if (lesson.remarks.isNotEmpty) ...[
              const SizedBox(height: 14),
              _LessonMiniSection(
                title: 'Remarks',
                content: lesson.remarks,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final payload = _payload;
    if (payload == null) {
      return _buildErrorCard(_errorMessage ?? 'Unable to load lesson plan.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(payload),
        const SizedBox(height: 18),
        _buildOverview(payload),
        const SizedBox(height: 14),
        _buildMetrics(payload),
        if (payload.subject.topicText.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildSection(
            title: 'Syllabus Description',
            content: payload.subject.topicText,
          ),
        ],
        const SizedBox(height: 18),
        Text(
          'Detailed Lesson Plans',
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        if (payload.lessons.isEmpty)
          _buildSection(
            title: 'Lesson Plans',
            content: 'No lesson plans found for this paper.',
          )
        else
          Column(
            children: [
              for (int i = 0; i < payload.lessons.length; i++) ...[
                _buildLessonCard(payload.lessons[i], i),
                if (i != payload.lessons.length - 1)
                  const SizedBox(height: 12),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildErrorCard(String message) {
    final borderColor = AppColors.borderSoft(context);
    final surfaceColor = AppColors.surface(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: textSecondary,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            'Lesson Plan Preview',
            style: TextStyle(
              color: textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final backgroundColor = AppColors.background(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
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
              'Lesson Plan',
              style: TextStyle(
                color: textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _showNotice(
              title: 'Export PDF',
              message: 'PDF export will be connected here next.',
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: const Text('Export'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.dashboardMutedColor(context),
        onRefresh: () => _loadLessonPlan(showLoader: false),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: _loading
              ? SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: AppColors.dashboardMutedColor(context),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Loading lesson plan...',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildContent(),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String? fallback;

  const _InfoChip({
    required this.label,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final value = label.trim().isNotEmpty ? label.trim() : fallback?.trim() ?? '';
    if (value.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface3(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderSoft(context)),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: AppColors.textPrimary(context),
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: AppColors.borderSoft(context)),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
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
              value.trim().isNotEmpty ? value : '—',
              style: TextStyle(
                color: textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonMiniSection extends StatelessWidget {
  final String title;
  final String content;

  const _LessonMiniSection({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) return const SizedBox.shrink();
    final borderColor = AppColors.borderSoft(context);
    final surfaceColor = AppColors.surface3(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: TextStyle(
              color: AppColors.textSecondary(context),
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

class _LessonPlanPayload {
  final _LessonSubject? _subject;
  final String? _lessonCount;
  final List<_LessonPlanItem>? _lessons;

  const _LessonPlanPayload({
    required _LessonSubject subject,
    required String lessonCount,
    required List<_LessonPlanItem> lessons,
  })  : _subject = subject,
        _lessonCount = lessonCount,
        _lessons = lessons;

  _LessonSubject get subject => _subject ?? const _LessonSubject();
  String get lessonCount => _lessonCount ?? '';
  List<_LessonPlanItem> get lessons => _lessons ?? const <_LessonPlanItem>[];
}

class _LessonSubject {
  final String? _name;
  final String? _courseName;
  final String? _semester;
  final String? _intakeYear;
  final String? _syllabusCode;
  final String? _subjectCode;
  final String? _status;
  final String? _institutionName;
  final String? _subjectType;
  final String? _creditPoints;
  final String? _lectureHours;
  final String? _tutorialHours;
  final String? _practicalHours;
  final String? _topicText;

  const _LessonSubject({
    String? name,
    String? courseName,
    String? semester,
    String? intakeYear,
    String? syllabusCode,
    String? subjectCode,
    String? status,
    String? institutionName,
    String? subjectType,
    String? creditPoints,
    String? lectureHours,
    String? tutorialHours,
    String? practicalHours,
    String? topicText,
  })  : _name = name,
        _courseName = courseName,
        _semester = semester,
        _intakeYear = intakeYear,
        _syllabusCode = syllabusCode,
        _subjectCode = subjectCode,
        _status = status,
        _institutionName = institutionName,
        _subjectType = subjectType,
        _creditPoints = creditPoints,
        _lectureHours = lectureHours,
        _tutorialHours = tutorialHours,
        _practicalHours = practicalHours,
        _topicText = topicText;

  String get name => _name ?? '';
  String get courseName => _courseName ?? '';
  String get semester => _semester ?? '';
  String get intakeYear => _intakeYear ?? '';
  String get syllabusCode => _syllabusCode ?? '';
  String get subjectCode => _subjectCode ?? '';
  String get status => _status ?? '';
  String get institutionName => _institutionName ?? '';
  String get subjectType => _subjectType ?? '';
  String get creditPoints => _creditPoints ?? '';
  String get lectureHours => _lectureHours ?? '';
  String get tutorialHours => _tutorialHours ?? '';
  String get practicalHours => _practicalHours ?? '';
  String get topicText => _topicText ?? '';
}

class _LessonPlanItem {
  final String? _lessonNo;
  final String? _title;
  final String? _unitTitle;
  final String? _lessonType;
  final String? _deliveryMode;
  final String? _completionStatus;
  final String? _durationHours;
  final String? _topicText;
  final String? _learningObjectives;
  final String? _teachingMethod;
  final String? _assessmentMethod;
  final String? _referenceMaterial;
  final String? _remarks;

  const _LessonPlanItem({
    String? lessonNo,
    String? title,
    String? unitTitle,
    String? lessonType,
    String? deliveryMode,
    String? completionStatus,
    String? durationHours,
    String? topicText,
    String? learningObjectives,
    String? teachingMethod,
    String? assessmentMethod,
    String? referenceMaterial,
    String? remarks,
  })  : _lessonNo = lessonNo,
        _title = title,
        _unitTitle = unitTitle,
        _lessonType = lessonType,
        _deliveryMode = deliveryMode,
        _completionStatus = completionStatus,
        _durationHours = durationHours,
        _topicText = topicText,
        _learningObjectives = learningObjectives,
        _teachingMethod = teachingMethod,
        _assessmentMethod = assessmentMethod,
        _referenceMaterial = referenceMaterial,
        _remarks = remarks;

  String get lessonNo => _lessonNo ?? '';
  String get title => _title ?? '';
  String get unitTitle => _unitTitle ?? '';
  String get lessonType => _lessonType ?? '';
  String get deliveryMode => _deliveryMode ?? '';
  String get completionStatus => _completionStatus ?? '';
  String get durationHours => _durationHours ?? '';
  String get topicText => _topicText ?? '';
  String get learningObjectives => _learningObjectives ?? '';
  String get teachingMethod => _teachingMethod ?? '';
  String get assessmentMethod => _assessmentMethod ?? '';
  String get referenceMaterial => _referenceMaterial ?? '';
  String get remarks => _remarks ?? '';
}
