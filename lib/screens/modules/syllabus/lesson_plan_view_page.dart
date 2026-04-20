import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:msitlms/config/appConfig.dart';
import 'package:msitlms/theme/app_colors.dart';

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
  String _selectedLessonFilter = 'all';

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
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: borderColor),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            message,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
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
          HttpHeaders.userAgentHeader: 'MSITLMS/1.0 (Flutter iOS/Android)',
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
        _selectedLessonFilter = 'all';
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

  List<_LessonPlanItem> _filteredLessons(List<_LessonPlanItem> lessons) {
    if (_selectedLessonFilter == 'all') return lessons;
    return lessons.where((lesson) {
      final lessonNo = lesson.lessonNo.trim();
      if (lessonNo.isNotEmpty) return lessonNo == _selectedLessonFilter;
      final index = lessons.indexOf(lesson);
      return (index + 1).toString() == _selectedLessonFilter;
    }).toList();
  }

  List<DropdownMenuItem<String>> _lessonFilterItems(List<_LessonPlanItem> lessons) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: 'all',
        child: Text('All Lessons'),
      ),
    ];

    for (int i = 0; i < lessons.length; i++) {
      final lessonNo = lessons[i].lessonNo.trim().isNotEmpty
          ? lessons[i].lessonNo.trim()
          : (i + 1).toString();
      items.add(
        DropdownMenuItem<String>(
          value: lessonNo,
          child: Text('Lesson $lessonNo'),
        ),
      );
    }
    return items;
  }

  Widget _buildTopInfo(_LessonPlanPayload payload) {
  final textPrimary = AppColors.textPrimary(context);
  final textSecondary = AppColors.textSecondary(context);
  final borderColor = AppColors.borderSoft(context);

  final title = payload.subject.name.isNotEmpty
      ? payload.subject.name
      : widget.subjectTitle;

  final code = payload.subject.subjectCode.trim();

  final ltpValue = [
    payload.subject.lectureHours.isNotEmpty
        ? payload.subject.lectureHours
        : '—',
    payload.subject.tutorialHours.isNotEmpty
        ? payload.subject.tutorialHours
        : '—',
    payload.subject.practicalHours.isNotEmpty
        ? payload.subject.practicalHours
        : '—',
  ].join(' / ');

  final creditValue = payload.subject.creditPoints.isNotEmpty
      ? payload.subject.creditPoints
      : '—';

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
    decoration: BoxDecoration(
      border: Border.all(color: borderColor.withOpacity(.7)),
      borderRadius: BorderRadius.circular(16),
      color: AppColors.surface(context),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                size: 15,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                code.isNotEmpty ? '$title ($code)' : title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
                textAlign: TextAlign.left,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 14,
              color: AppColors.primary.withOpacity(.85),
            ),
            const SizedBox(width: 6),
            Text(
              'LTP: $ltpValue',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(width: 14),
            Icon(
              Icons.star_rounded,
              size: 14,
              color: AppColors.primary.withOpacity(.85),
            ),
            const SizedBox(width: 6),
            Text(
              'Credit: $creditValue',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

 Widget _buildLessonBlock(_LessonPlanItem lesson, int index) {
  final textPrimary = AppColors.textPrimary(context);
  final textSecondary = AppColors.textSecondary(context);
  final dividerColor = AppColors.borderSoft(context);

  final lessonNumber = lesson.lessonNo.isNotEmpty
      ? lesson.lessonNo
      : (index + 1).toString();

  Widget buildMiniBadge({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    if (text.trim().isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11.8,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.symmetric(vertical: 16),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: dividerColor),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Text(
            lessonNumber,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
            textAlign: TextAlign.left,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.title.isNotEmpty
                      ? lesson.title
                      : 'Lesson $lessonNumber',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                  textAlign: TextAlign.left,
                ),
                if (lesson.unitTitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    lesson.unitTitle,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ],
                const SizedBox(height: 10),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (lesson.lessonType.isNotEmpty)
                      buildMiniBadge(
                        icon: Icons.category_rounded,
                        text: lesson.lessonType,
                        color: Colors.indigo,
                      ),
                    if (lesson.deliveryMode.isNotEmpty)
                      buildMiniBadge(
                        icon: Icons.play_circle_outline_rounded,
                        text: lesson.deliveryMode,
                        color: Colors.teal,
                      ),
                    if (lesson.durationHours.isNotEmpty)
                      buildMiniBadge(
                        icon: Icons.schedule_rounded,
                        text: '${lesson.durationHours} hrs',
                        color: Colors.orange,
                      ),
                  ],
                ),

                if (lesson.topicText.isNotEmpty)
                  _TextSection(
                    title: 'Topic',
                    content: lesson.topicText,
                    icon: Icons.notes_rounded,
                  ),
                if (lesson.learningObjectives.isNotEmpty)
                  _TextSection(
                    title: 'Learning Objectives',
                    content: lesson.learningObjectives,
                    icon: Icons.flag_rounded,
                  ),
                if (lesson.teachingMethod.isNotEmpty)
                  _TextSection(
                    title: 'Teaching Method',
                    content: lesson.teachingMethod,
                    icon: Icons.lightbulb_outline_rounded,
                  ),
                if (lesson.assessmentMethod.isNotEmpty)
                  _TextSection(
                    title: 'Assessment Method',
                    content: lesson.assessmentMethod,
                    icon: Icons.fact_check_outlined,
                  ),
                if (lesson.referenceMaterial.isNotEmpty)
                  _TextSection(
                    title: 'Reference Material',
                    content: lesson.referenceMaterial,
                    icon: Icons.bookmark_outline_rounded,
                  ),
                if (lesson.remarks.isNotEmpty)
                  _TextSection(
                    title: 'Remarks',
                    content: lesson.remarks,
                    icon: Icons.mode_comment_outlined,
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

 Widget _buildContent() {
  final payload = _payload;
  if (payload == null) {
    return _buildErrorCard(_errorMessage ?? 'Unable to load lesson plan.');
  }

  final filteredLessons = _filteredLessons(payload.lessons);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _buildTopInfo(payload),
      if (payload.subject.topicText.isNotEmpty) ...[
        const SizedBox(height: 18),
        Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 15,
              color: AppColors.textSecondary(context),
            ),
            const SizedBox(width: 6),
            Text(
              'Syllabus Description',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            payload.subject.topicText,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12.8,
              fontWeight: FontWeight.w500,
              height: 1.6,
            ),
            textAlign: TextAlign.left,
          ),
        ),
      ],
      const SizedBox(height: 18),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                Icon(
                  Icons.menu_book_outlined,
                  size: 15,
                  color: AppColors.textSecondary(context),
                ),
                const SizedBox(width: 6),
                Text(
                  'Detailed Lesson Plan',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withOpacity(.22),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedLessonFilter,
                    isDense: true,
                    borderRadius: BorderRadius.circular(12),
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    dropdownColor: AppColors.surface(context),
                    items: _lessonFilterItems(payload.lessons),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedLessonFilter = value;
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (filteredLessons.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'No lesson plans found for this filter.',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.left,
          ),
        )
      else
        Column(
          children: [
            for (int i = 0; i < filteredLessons.length; i++)
              _buildLessonBlock(filteredLessons[i], i),
          ],
        ),
    ],
  );
}

  Widget _buildErrorCard(String message) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: textSecondary,
            size: 26,
          ),
          const SizedBox(height: 8),
          Text(
            'Lesson Plan',
            style: TextStyle(
              color: textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
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
        backgroundColor: backgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          'Lesson Plan',
          style: TextStyle(
            color: textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => _showNotice(
              title: 'Export PDF',
              message: 'PDF export will be connected here next.',
            ),
            icon: Icon(
              Icons.picture_as_pdf_outlined,
              color: textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.textSecondary(context),
        onRefresh: () => _loadLessonPlan(showLoader: false),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: _loading
              ? SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Loading lesson plan...',
                          style: TextStyle(
                            color: textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
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

// class _SmallMetaText extends StatelessWidget {
//   final String label;
//   final String value;
//   final IconData icon;

//   const _SmallMetaText({
//     required this.label,
//     required this.value,
//     required this.icon,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final textPrimary = AppColors.textPrimary(context);
//     final textSecondary = AppColors.textSecondary(context);

//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Padding(
//           padding: const EdgeInsets.only(top: 1),
//           child: Icon(
//             icon,
//             size: 14,
//             color: AppColors.primary.withOpacity(.85),
//           ),
//         ),
//         const SizedBox(width: 6),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 label,
//                 style: TextStyle(
//                   color: textSecondary,
//                   fontSize: 11.5,
//                   fontWeight: FontWeight.w500,
//                 ),
//                 textAlign: TextAlign.left,
//               ),
//               const SizedBox(height: 1),
//               Text(
//                 value.trim().isNotEmpty ? value : '—',
//                 style: TextStyle(
//                   color: textPrimary,
//                   fontSize: 12.5,
//                   fontWeight: FontWeight.w600,
//                 ),
//                 textAlign: TextAlign.left,
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

class _InlineInfo extends StatelessWidget {
  final String label;
  final String value;

  const _InlineInfo({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();

    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        textAlign: TextAlign.left,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextSection extends StatelessWidget {
  final String title;
  final String content;
  final IconData icon;

  const _TextSection({
    required this.title,
    required this.content,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) return const SizedBox.shrink();

    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  icon,
                  size: 14,
                  color: AppColors.primary.withOpacity(.85),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              content,
              style: TextStyle(
                color: textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.55,
              ),
              textAlign: TextAlign.left,
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
