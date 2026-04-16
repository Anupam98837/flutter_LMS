import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hallienzlms/config/appConfig.dart';
import 'package:hallienzlms/theme/app_colors.dart';

class MyAssignmentsPage extends StatefulWidget {
  const MyAssignmentsPage({super.key});

  @override
  State<MyAssignmentsPage> createState() => _MyAssignmentsPageState();
}

class _MyAssignmentsPageState extends State<MyAssignmentsPage> {
  bool _loading = true;
  String? _errorMessage;
  List<_AssignmentSemester> _semesters = const <_AssignmentSemester>[];
  int? _currentSemester;
  String _selectedSemesterKey = 'all';
  String _selectedSubjectKey = 'all';

  @override
  void initState() {
    super.initState();
    _loadAssignments(showLoader: true);
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

  num? _numValue(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }

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
          HttpHeaders.userAgentHeader: 'HallienzLMS/1.0 (Flutter iOS/Android)',
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

  String _normalizeRemoteUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return '';

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return '';
    if (parsed.hasScheme) return parsed.toString();

    final baseUri = Uri.tryParse(AppConfig.baseUrl);
    return baseUri?.resolveUri(parsed).toString() ?? '';
  }

  _AssignmentSubmission _normalizeSubmission(Map<String, dynamic> raw) {
    return _AssignmentSubmission(
      attemptNumber: _intValue(raw['attempt_number']) ?? 0,
      finalMarks: _numValue(raw['final_marks']),
      marksObtained: _numValue(raw['marks_obtained']),
    );
  }

  _StudentAssignment _normalizeAssignment(
    Map<String, dynamic> raw,
    _AssignmentSemester semester,
  ) {
    final subject = _asMap(raw['subject']);
    final assignedBy = _asMap(raw['assigned_by']);
    final submissions = _asList(raw['my_submissions'])
        .map((item) => _normalizeSubmission(_asMap(item)))
        .toList();

    return _StudentAssignment(
      id: _stringValue(raw['id']),
      uuid: _stringValue(raw['uuid']),
      title: _stringValue(raw['title']).isNotEmpty
          ? _stringValue(raw['title'])
          : 'Assignment',
      description: _plainText(raw['short_description']).isNotEmpty
          ? _plainText(raw['short_description'])
          : _plainText(raw['instruction']).isNotEmpty
              ? _plainText(raw['instruction'])
              : _plainText(raw['description']),
      subjectName: _stringValue(subject['name']).isNotEmpty
          ? _stringValue(subject['name'])
          : _stringValue(raw['subject_name']),
      subjectCode: _stringValue(subject['code']).isNotEmpty
          ? _stringValue(subject['code'])
          : _stringValue(raw['subject_code']),
      subjectKey: _stringValue(subject['id']).isNotEmpty
          ? _stringValue(subject['id'])
          : _stringValue(subject['code']).isNotEmpty
              ? _stringValue(subject['code'])
              : _stringValue(subject['name']).isNotEmpty
                  ? _stringValue(subject['name'])
                  : _stringValue(raw['subject_name']),
      assignedByName: _stringValue(assignedBy['name']).isNotEmpty
          ? _stringValue(assignedBy['name'])
          : _stringValue(raw['assigned_by_name']).isNotEmpty
              ? _stringValue(raw['assigned_by_name'])
              : 'System',
      assignedByImage: _normalizeRemoteUrl(
        _stringValue(assignedBy['image']).isNotEmpty
            ? _stringValue(assignedBy['image'])
            : _stringValue(raw['assigned_by_image']),
      ),
      dueAt: _stringValue(raw['due_at']).isNotEmpty
          ? _stringValue(raw['due_at'])
          : _stringValue(raw['end_at']).isNotEmpty
              ? _stringValue(raw['end_at'])
              : _stringValue(raw['created_at']),
      createdAt: _stringValue(raw['created_at']),
      attemptsAllowed: _intValue(raw['attempts_allowed']) ?? 1,
      totalMarks: _numValue(raw['total_marks']),
      semesterId: semester.semesterId,
      semesterLabel: semester.displayLabel,
      mySubmissions: submissions,
    );
  }

  _AssignmentLoadResult _extractAssignments(Map<String, dynamic> payload) {
    final root = _asMap(payload['data']).isNotEmpty
        ? _asMap(payload['data'])
        : payload;
    final academic = _asMap(root['academic']);
    final currentSemester = _intValue(academic['current_semester']);
    final semesters = <_AssignmentSemester>[];

    for (final item in _asList(root['semesters'])) {
      final row = _asMap(item);
      final semesterId = _intValue(row['semester_id']) ??
          _intValue(row['semester_number']) ??
          _intValue(row['semester']) ??
          0;
      final semesterNumber = _intValue(row['semester_number']) ??
          _intValue(row['semester']) ??
          (semesterId > 0 ? semesterId : null);
      final displayLabel = _stringValue(row['semester_display']).isNotEmpty
          ? _stringValue(row['semester_display'])
          : semesterNumber != null && semesterNumber > 0
              ? 'Sem $semesterNumber'
              : 'General';

      final semester = _AssignmentSemester(
        semesterId: semesterId,
        semesterNumber: semesterNumber,
        displayLabel: displayLabel,
        assignments: const [],
      );

      final assignments = _asList(row['assignments'])
          .map((raw) => _normalizeAssignment(_asMap(raw), semester))
          .where((assignment) => assignment.title.isNotEmpty)
          .toList()
        ..sort(_assignmentDateSort);

      semesters.add(
        semester.copyWith(assignments: assignments),
      );
    }

    semesters.sort((a, b) {
      final aNo = a.semesterNumber ?? 0;
      final bNo = b.semesterNumber ?? 0;
      return bNo.compareTo(aNo);
    });

    return _AssignmentLoadResult(
      semesters: semesters,
      currentSemester: currentSemester,
    );
  }

  Future<void> _loadAssignments({required bool showLoader}) async {
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
      if (showLoader) _loading = true;
      _errorMessage = null;
    });

    try {
      final result = await _getJson(
        endpoint: '${AppConfig.baseUrl}/api/assignments/student',
        token: token,
      );

      final statusCode = result['statusCode'] as int;
      final payload = result['data'] as Map<String, dynamic>;
      final success = payload['success'];

      if (statusCode < 200 || statusCode >= 300 || success == false) {
        throw Exception(
          _stringValue(payload['message']).isNotEmpty
              ? _stringValue(payload['message'])
              : 'Failed to load assignments.',
        );
      }

      final extracted = _extractAssignments(payload);
      final hydratedSemesters = await _hydrateAssignmentsWithSubmissions(
        extracted.semesters,
        token,
      );
      if (!mounted) return;

      setState(() {
        _semesters = hydratedSemesters;
        _currentSemester = extracted.currentSemester;
        _loading = false;
      });

      _syncFilters();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _syncFilters() {
    final semesterExists =
        _semesterFilterOptions.any((item) => item.key == _selectedSemesterKey);
    final subjectExists =
        _subjectFilterOptions.any((item) => item.key == _selectedSubjectKey);

    if ((!semesterExists || !subjectExists) && mounted) {
      setState(() {
        if (!semesterExists) {
          _selectedSemesterKey = _semesterFilterOptions.isNotEmpty
              ? _semesterFilterOptions.first.key
              : 'all';
        }
        if (!subjectExists) {
          _selectedSubjectKey = 'all';
        }
      });
    }
  }

  List<_AssignmentFilterOption> get _semesterFilterOptions {
    final items = <_AssignmentFilterOption>[
      const _AssignmentFilterOption(
        key: 'all',
        label: 'All Sem',
      ),
    ];

    for (final semester in _semesters) {
      if (semester.assignments.isEmpty) continue;
      items.add(
        _AssignmentFilterOption(
          key: 'semester-${semester.semesterId}',
          label: semester.displayLabel,
          semesterId: semester.semesterId,
        ),
      );
    }

    return items;
  }

  List<_StudentAssignment> get _allAssignments {
    final items = <_StudentAssignment>[];
    for (final semester in _semesters) {
      items.addAll(semester.assignments);
    }
    items.sort(_assignmentDateSort);
    return items;
  }

  List<_StudentAssignment> get _semesterFilteredAssignments {
    if (_selectedSemesterKey == 'all') return _allAssignments;

    final active = _semesterFilterOptions.firstWhere(
      (item) => item.key == _selectedSemesterKey,
      orElse: () => const _AssignmentFilterOption(key: 'all', label: 'All Sem'),
    );

    return _allAssignments
        .where((item) => item.semesterId == active.semesterId)
        .toList()
      ..sort(_assignmentDateSort);
  }

  List<_AssignmentFilterOption> get _subjectFilterOptions {
    final labels = <String, String>{};

    for (final assignment in _semesterFilteredAssignments) {
      if (assignment.subjectKey.isEmpty) continue;
      labels[assignment.subjectKey] = assignment.subjectDisplay;
    }

    final items = <_AssignmentFilterOption>[
      const _AssignmentFilterOption(
        key: 'all',
        label: 'All Sub',
      ),
    ];

    final sorted = labels.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (final entry in sorted) {
      items.add(
        _AssignmentFilterOption(
          key: entry.key,
          label: entry.value,
        ),
      );
    }

    return items;
  }

  List<_StudentAssignment> get _visibleAssignments {
    var items = _semesterFilteredAssignments;
    if (_selectedSubjectKey != 'all') {
      items = items
          .where((item) => item.subjectKey == _selectedSubjectKey)
          .toList();
    }
    items.sort(_assignmentDateSort);
    return items;
  }

  int _assignmentDateSort(_StudentAssignment a, _StudentAssignment b) {
    final aTime = DateTime.tryParse(a.dueAt.isNotEmpty ? a.dueAt : a.createdAt)
            ?.millisecondsSinceEpoch ??
        0;
    final bTime = DateTime.tryParse(b.dueAt.isNotEmpty ? b.dueAt : b.createdAt)
            ?.millisecondsSinceEpoch ??
        0;
    return bTime.compareTo(aTime);
  }

  Future<List<_AssignmentSubmission>> _fetchMySubmissions(
    String assignmentId,
    String token,
  ) async {
    final result = await _getJson(
      endpoint:
          '${AppConfig.baseUrl}/api/assignments/${Uri.encodeComponent(assignmentId)}/my-submissions',
      token: token,
    );

    final statusCode = result['statusCode'] as int;
    final payload = result['data'] as Map<String, dynamic>;
    if (statusCode < 200 || statusCode >= 300) {
      throw Exception(
        _stringValue(payload['message']).isNotEmpty
            ? _stringValue(payload['message'])
            : 'Failed to load submissions.',
      );
    }

    return _asList(payload['data'])
        .map((item) => _normalizeSubmission(_asMap(item)))
        .toList();
  }

  Future<_AssignmentSheetState> _loadAssignmentSheetState(
    _StudentAssignment assignment,
  ) async {
    final token = await _readToken();
    if (token.isEmpty) {
      return _AssignmentSheetState(
        attemptsAllowed: assignment.attemptsAllowed,
        submissions: assignment.mySubmissions,
        errorMessage: 'Session missing. Please login again.',
      );
    }

    try {
      final submissions = await _fetchMySubmissions(assignment.id, token);
      return _AssignmentSheetState(
        attemptsAllowed: assignment.attemptsAllowed,
        submissions: submissions,
      );
    } catch (error) {
      return _AssignmentSheetState(
        attemptsAllowed: assignment.attemptsAllowed,
        submissions: assignment.mySubmissions,
        errorMessage: error.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<List<_AssignmentSemester>> _hydrateAssignmentsWithSubmissions(
    List<_AssignmentSemester> semesters,
    String token,
  ) async {
    final hydrated = <_AssignmentSemester>[];

    for (final semester in semesters) {
      final assignments = <_StudentAssignment>[];

      for (final assignment in semester.assignments) {
        try {
          final submissions = await _fetchMySubmissions(assignment.id, token);
          assignments.add(assignment.copyWith(mySubmissions: submissions));
        } catch (_) {
          assignments.add(assignment);
        }
      }

      hydrated.add(semester.copyWith(assignments: assignments));
    }

    return hydrated;
  }

  Future<void> _submitAssignment({
    required _StudentAssignment assignment,
    required String notes,
    required String link,
    required PlatformFile? selectedFile,
  }) async {
    final token = await _readToken();
    if (token.isEmpty) {
      throw Exception('Session missing. Please login again.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '${AppConfig.baseUrl}/api/assignments/${Uri.encodeComponent(assignment.id)}/submissions',
      ),
    );
    request.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    request.headers[HttpHeaders.acceptHeader] = 'application/json';
    request.fields['status'] = 'submitted';

    if (notes.trim().isNotEmpty) {
      request.fields['text_content'] = notes.trim();
    }
    if (link.trim().isNotEmpty) {
      request.fields['submission_link'] = link.trim();
    }
    if (selectedFile != null) {
      if ((selectedFile.path ?? '').isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            selectedFile.path!,
            filename: selectedFile.name,
          ),
        );
      } else if (selectedFile.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            selectedFile.bytes!,
            filename: selectedFile.name,
          ),
        );
      }
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
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
        _stringValue(payload['message']).isNotEmpty
            ? _stringValue(payload['message'])
            : 'Submission failed.',
      );
    }
  }

  Future<void> _openPreviousSubmission(_StudentAssignment assignment) async {
    if (assignment.uuid.isEmpty) return;

    final uri = Uri.parse(
      '${AppConfig.baseUrl}/assignments/${Uri.encodeComponent(assignment.uuid)}/documents',
    );
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open previous submission.')),
      );
    }
  }

  void _openAssignmentSheet(_StudentAssignment assignment) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return _AssignmentDetailSheet(
          hostContext: context,
          assignment: assignment,
          loadState: () => _loadAssignmentSheetState(assignment),
          onOpenPrevious: () => _openPreviousSubmission(assignment),
          onSubmit: (notes, link, selectedFile) async {
            await _submitAssignment(
              assignment: assignment,
              notes: notes,
              link: link,
              selectedFile: selectedFile,
            );
            if (!mounted) return;
            await _loadAssignments(showLoader: false);
          },
        );
      },
    );
  }

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value.isEmpty ? 'N/A' : value;

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  }

  String _formatDateTime(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value.isEmpty ? 'N/A' : value;

    final hour =
        parsed.hour > 12 ? parsed.hour - 12 : (parsed.hour == 0 ? 12 : parsed.hour);
    final minute = parsed.minute.toString().padLeft(2, '0');
    final suffix = parsed.hour >= 12 ? 'PM' : 'AM';
    return '${_formatDate(value)}, $hour:$minute $suffix';
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
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.assignments.withOpacity(0.18),
                ),
              ),
              child: const Icon(
                Icons.assignment_outlined,
                size: 16,
                color: AppColors.assignments,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Assignments',
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
          'Semester-wise assignments with submission access and attempts.',
          style: TextStyle(
            color: textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSemesterDropdown() {
    final options = _semesterFilterOptions;
    if (options.isEmpty) return const SizedBox.shrink();

    return Expanded(
      child: SizedBox(
        height: 36,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: options.any((item) => item.key == _selectedSemesterKey)
                ? _selectedSemesterKey
                : options.first.key,
            isExpanded: true,
            isDense: true,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.primary,
              size: 18,
            ),
            dropdownColor: AppColors.surface(context),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
            selectedItemBuilder: (context) {
              return options.map((item) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList();
            },
            items: options
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.key,
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedSemesterKey = value;
                _selectedSubjectKey = 'all';
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectDropdown() {
    final options = _subjectFilterOptions;
    if (options.isEmpty) return const SizedBox.shrink();

    return Expanded(
      child: SizedBox(
        height: 36,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: options.any((item) => item.key == _selectedSubjectKey)
                ? _selectedSubjectKey
                : options.first.key,
            isExpanded: true,
            isDense: true,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.primary,
              size: 18,
            ),
            dropdownColor: AppColors.surface(context),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
            selectedItemBuilder: (context) {
              return options.map((item) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList();
            },
            items: options
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.key,
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedSubjectKey = value;
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCountBadge() {
    final count = _visibleAssignments.length;
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = AppColors.borderSoft(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface3(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        '$count assignment${count == 1 ? '' : 's'}',
        style: TextStyle(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderSoft(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 90,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.surface3(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.surface3(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 220,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.surface3(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    final message = _errorMessage ??
        (_selectedSemesterKey != 'all'
            ? 'No assignments are available for this semester right now.'
            : _selectedSubjectKey != 'all'
                ? 'No assignments are available for this subject right now.'
                : 'Assignments are not available right now.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 30),
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
              Icons.assignment_outlined,
              color: Color(0xFF6A717C),
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No assignments',
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
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentList() {
    final assignments = _visibleAssignments;

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: assignments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final assignment = assignments[index];
        return _AssignmentCard(
          assignment: assignment,
          dueDateLabel: _formatDateTime(
            assignment.dueAt.isNotEmpty ? assignment.dueAt : assignment.createdAt,
          ),
          onTap: () => _openAssignmentSheet(assignment),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.dashboardMutedColor(context);
    const sectionSpacing = 16.0;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          color: muted,
          onRefresh: () => _loadAssignments(showLoader: false),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildCountBadge(),
                      const SizedBox(width: 10),
                      _buildSemesterDropdown(),
                      const SizedBox(width: 10),
                      _buildSubjectDropdown(),
                    ],
                  ),
                  const SizedBox(height: sectionSpacing),
                  if (_loading)
                    _buildLoadingState()
                  else if (_visibleAssignments.isEmpty)
                    _buildEmptyState()
                  else
                    _buildAssignmentList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssignmentCard extends StatelessWidget {
  final _StudentAssignment assignment;
  final String dueDateLabel;
  final VoidCallback onTap;

  const _AssignmentCard({
    required this.assignment,
    required this.dueDateLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final inkColor = AppColors.ink(context);
    final submissionCount = assignment.submissionCount;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: inkColor.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.assignment_outlined,
                      size: 18,
                      color: AppColors.assignments,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      assignment.title,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        height: 1.28,
                      ),
                    ),
                  ),
                ],
              ),
              if (assignment.subjectDisplay.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  assignment.subjectDisplay,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _AssignmentAvatar(
                    name: assignment.assignedByName,
                    imageUrl: assignment.assignedByImageSafe,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      assignment.assignedByName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 12.8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              if (assignment.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  assignment.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '${assignment.usedAttempts}/${assignment.attemptsAllowed} attempts${assignment.marksLabel.isNotEmpty ? ' • ${assignment.marksLabel}' : ''}',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              Divider(
                height: 1,
                thickness: 1,
                color: borderColor,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                          color: textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dueDateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textSecondary,
                              fontSize: 11.8,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: onTap,
                    icon: Icon(
                      submissionCount > 0
                          ? Icons.folder_open_outlined
                          : Icons.upload_outlined,
                      size: 16,
                    ),
                    label: Text(submissionCount > 0 ? 'Submissions' : 'Submit'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignmentDetailSheet extends StatefulWidget {
  final BuildContext? hostContext;
  final _StudentAssignment assignment;
  final Future<_AssignmentSheetState> Function() loadState;
  final Future<void> Function() onOpenPrevious;
  final Future<void> Function(
    String notes,
    String link,
    PlatformFile? selectedFile,
  ) onSubmit;

  const _AssignmentDetailSheet({
    this.hostContext,
    required this.assignment,
    required this.loadState,
    required this.onOpenPrevious,
    required this.onSubmit,
  });

  @override
  State<_AssignmentDetailSheet> createState() => _AssignmentDetailSheetState();
}

class _AssignmentDetailSheetState extends State<_AssignmentDetailSheet> {
  late final Future<_AssignmentSheetState> _sheetStateFuture;
  late final TextEditingController _notesController;
  late final TextEditingController _linkController;
  PlatformFile? _selectedFile;
  bool _submitting = false;
  OverlayEntry? _feedbackEntry;
  bool _persistFeedbackOnDispose = false;

  @override
  void initState() {
    super.initState();
    _sheetStateFuture = widget.loadState();
    _notesController = TextEditingController();
    _linkController = TextEditingController();
  }

  @override
  void dispose() {
    if (!_persistFeedbackOnDispose) {
      _removeFeedback();
    }
    _notesController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _removeFeedback() {
    if (_feedbackEntry?.mounted == true) {
      _feedbackEntry!.remove();
    }
    _feedbackEntry = null;
  }

  void _showFeedback(
    String message, {
    bool isError = false,
    bool persistAfterDispose = false,
  }) {
    _removeFeedback();
    _persistFeedbackOnDispose = persistAfterDispose;

    final hostContext = widget.hostContext ?? context;
    final overlay = Overlay.of(hostContext, rootOverlay: true);
    if (overlay == null) return;

    final mediaQuery = MediaQuery.of(hostContext);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: mediaQuery.padding.top + 16,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isError ? const Color(0xFFB42318) : const Color(0xFF166534),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isError
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _feedbackEntry = entry;
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (entry.mounted) {
        entry.remove();
      }
      if (identical(_feedbackEntry, entry)) {
        _feedbackEntry = null;
      }
    });
  }

  Future<void> _handleSubmit() async {
    final notes = _notesController.text.trim();
    final link = _linkController.text.trim();
    if (notes.isEmpty && link.isEmpty && _selectedFile == null) {
      _showFeedback(
        'Add notes, a submission link, or choose a file first.',
        isError: true,
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      await widget.onSubmit(notes, link, _selectedFile);
      if (!mounted) return;
      _showFeedback(
        'Assignment submitted successfully.',
        persistAfterDispose: true,
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _showFeedback(
        error.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
    );

    if (!mounted || result == null || result.files.isEmpty) return;

    setState(() {
      _selectedFile = result.files.single;
    });
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index += 1;
    }
    final display = value >= 10 || index == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$display ${units[index]}';
  }

  @override
  Widget build(BuildContext context) {
    final assignment = widget.assignment;
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = AppColors.borderSoft(context);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.88,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
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
              Text(
                assignment.title,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (assignment.subjectDisplay.isNotEmpty)
                    _AssignmentMetaChip(
                      icon: Icons.menu_book_outlined,
                      label: assignment.subjectDisplay,
                    ),
                  _AssignmentMetaChip(
                    icon: Icons.calendar_today_outlined,
                    label: _formatSheetDate(
                      assignment.dueAt.isNotEmpty
                          ? assignment.dueAt
                          : assignment.createdAt,
                    ),
                  ),
                  if (assignment.semesterLabel.isNotEmpty)
                    _AssignmentMetaChip(
                      icon: Icons.school_outlined,
                      label: assignment.semesterLabel,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<_AssignmentSheetState>(
                  future: _sheetStateFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final sheetState = snapshot.data!;
                    final remainingAttempts = sheetState.remainingAttempts;

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            decoration: BoxDecoration(
                              color: AppColors.surface3(context),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                _AssignmentAvatar(
                                  name: assignment.assignedByName,
                                  imageUrl: assignment.assignedByImageSafe,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    assignment.assignedByName,
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            decoration: BoxDecoration(
                              color: AppColors.surface3(context),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(
                              assignment.description.isNotEmpty
                                  ? assignment.description
                                  : 'No description available for this assignment.',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.55,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface3(context),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Text(
                                    '$remainingAttempts remaining out of ${sheetState.attemptsAllowed}',
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              if (sheetState.submissions.isNotEmpty &&
                                  assignment.uuid.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                TextButton.icon(
                                  onPressed: widget.onOpenPrevious,
                                  icon: const Icon(
                                    Icons.open_in_new_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Previous'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (sheetState.errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              sheetState.errorMessage!,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (remainingAttempts > 0) ...[
                            const SizedBox(height: 18),
                            TextField(
                              controller: _linkController,
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                labelText: 'Submission Link',
                                hintText: 'https://example.com/your-work',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                              decoration: BoxDecoration(
                                color: AppColors.surface3(context),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _selectedFile == null
                                              ? 'No file selected'
                                              : _selectedFile!.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: textPrimary,
                                            fontSize: 12.8,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (_selectedFile != null)
                                        IconButton(
                                          onPressed: () {
                                            setState(() {
                                              _selectedFile = null;
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                    ],
                                  ),
                                  if (_selectedFile != null &&
                                      _formatFileSize(_selectedFile!.size)
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatFileSize(_selectedFile!.size),
                                      style: TextStyle(
                                        color: textSecondary,
                                        fontSize: 11.8,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: _pickFile,
                                    icon: const Icon(
                                      Icons.attach_file_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      _selectedFile == null
                                          ? 'Select File'
                                          : 'Change File',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _notesController,
                              maxLines: 5,
                              decoration: InputDecoration(
                                labelText: 'Notes',
                                hintText: 'Write your submission notes here',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: _submitting ? null : _handleSubmit,
                                child: Text(_submitting ? 'Submitting...' : 'Submit'),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 18),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.surface3(context),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor),
                              ),
                              child: Text(
                                'You have used all attempts. You can still open your previous submission.',
                                style: TextStyle(
                                  color: textSecondary,
                                  fontSize: 12.8,
                                  fontWeight: FontWeight.w600,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSheetDate(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value.isEmpty ? 'N/A' : value;

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour =
        parsed.hour > 12 ? parsed.hour - 12 : (parsed.hour == 0 ? 12 : parsed.hour);
    final minute = parsed.minute.toString().padLeft(2, '0');
    final suffix = parsed.hour >= 12 ? 'PM' : 'AM';

    return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}, $hour:$minute $suffix';
  }
}

class _AssignmentMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AssignmentMetaChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface3(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderSoft(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppColors.textSecondary(context),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentAvatar extends StatelessWidget {
  final String name;
  final String imageUrl;
  final double size;

  const _AssignmentAvatar({
    required this.name,
    this.imageUrl = '',
    this.size = 34,
  });

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? 'S' : name.trim().substring(0, 1).toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            AppColors.dashboardAvatarStart,
            AppColors.dashboardAvatarEnd,
          ],
        ),
      ),
      alignment: Alignment.center,
      child: ClipOval(
        child: imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _AssignmentAvatarFallback(
                  letter: letter,
                  size: size,
                ),
              )
            : _AssignmentAvatarFallback(
                letter: letter,
                size: size,
              ),
      ),
    );
  }
}

class _AssignmentAvatarFallback extends StatelessWidget {
  final String letter;
  final double size;

  const _AssignmentAvatarFallback({
    required this.letter,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: AppColors.dashboardAvatarText,
            fontSize: size <= 30 ? 11 : 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _AssignmentLoadResult {
  final List<_AssignmentSemester> semesters;
  final int? currentSemester;

  const _AssignmentLoadResult({
    required this.semesters,
    required this.currentSemester,
  });
}

class _AssignmentSemester {
  final int semesterId;
  final int? semesterNumber;
  final String displayLabel;
  final List<_StudentAssignment> assignments;

  const _AssignmentSemester({
    required this.semesterId,
    required this.semesterNumber,
    required this.displayLabel,
    required this.assignments,
  });

  _AssignmentSemester copyWith({
    List<_StudentAssignment>? assignments,
  }) {
    return _AssignmentSemester(
      semesterId: semesterId,
      semesterNumber: semesterNumber,
      displayLabel: displayLabel,
      assignments: assignments ?? this.assignments,
    );
  }
}

class _StudentAssignment {
  final String id;
  final String uuid;
  final String title;
  final String description;
  final String subjectName;
  final String subjectCode;
  final String subjectKey;
  final String assignedByName;
  final String assignedByImage;
  final String dueAt;
  final String createdAt;
  final int attemptsAllowed;
  final num? totalMarks;
  final int semesterId;
  final String semesterLabel;
  final List<_AssignmentSubmission> mySubmissions;

  const _StudentAssignment({
    required this.id,
    required this.uuid,
    required this.title,
    required this.description,
    required this.subjectName,
    required this.subjectCode,
    required this.subjectKey,
    required this.assignedByName,
    required this.assignedByImage,
    required this.dueAt,
    required this.createdAt,
    required this.attemptsAllowed,
    required this.totalMarks,
    required this.semesterId,
    required this.semesterLabel,
    required this.mySubmissions,
  });

  _StudentAssignment copyWith({
    List<_AssignmentSubmission>? mySubmissions,
  }) {
    return _StudentAssignment(
      id: id,
      uuid: uuid,
      title: title,
      description: description,
      subjectName: subjectName,
      subjectCode: subjectCode,
      subjectKey: subjectKey,
      assignedByName: assignedByName,
      assignedByImage: assignedByImage,
      dueAt: dueAt,
      createdAt: createdAt,
      attemptsAllowed: attemptsAllowed,
      totalMarks: totalMarks,
      semesterId: semesterId,
      semesterLabel: semesterLabel,
      mySubmissions: mySubmissions ?? this.mySubmissions,
    );
  }

  String get subjectDisplay {
    if (subjectName.isEmpty) return subjectCode;
    if (subjectCode.isEmpty) return subjectName;
    return '$subjectName ($subjectCode)';
  }

  String get assignedByImageSafe => assignedByImage.trim();

  int get submissionCount => mySubmissions.length;

  int get usedAttempts {
    if (mySubmissions.isEmpty) return 0;
    return mySubmissions
        .map((item) => item.attemptNumber)
        .fold<int>(0, (max, current) => current > max ? current : max);
  }

  String get marksLabel {
    for (final submission in mySubmissions) {
      final marks = submission.finalMarks ?? submission.marksObtained;
      if (marks == null) continue;
      if (totalMarks != null) {
        return 'Marks: $marks / $totalMarks';
      }
      return 'Marks: $marks';
    }
    return 'Not graded';
  }
}

class _AssignmentSubmission {
  final int attemptNumber;
  final num? finalMarks;
  final num? marksObtained;

  const _AssignmentSubmission({
    required this.attemptNumber,
    required this.finalMarks,
    required this.marksObtained,
  });
}

class _AssignmentFilterOption {
  final String key;
  final String label;
  final int? semesterId;

  const _AssignmentFilterOption({
    required this.key,
    required this.label,
    this.semesterId,
  });
}

class _AssignmentSheetState {
  final int attemptsAllowed;
  final List<_AssignmentSubmission> submissions;
  final String? errorMessage;

  const _AssignmentSheetState({
    required this.attemptsAllowed,
    required this.submissions,
    this.errorMessage,
  });

  int get usedAttempts {
    if (submissions.isEmpty) return 0;
    return submissions
        .map((item) => item.attemptNumber)
        .fold<int>(0, (max, current) => current > max ? current : max);
  }

  int get remainingAttempts {
    final remaining = attemptsAllowed - usedAttempts;
    return remaining < 0 ? 0 : remaining;
  }
}
