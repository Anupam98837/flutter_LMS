import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hallienzlms/config/appConfig.dart';
import 'package:hallienzlms/theme/app_colors.dart';

class MyStudyMaterialsPage extends StatefulWidget {
  const MyStudyMaterialsPage({super.key});

  @override
  State<MyStudyMaterialsPage> createState() => _MyStudyMaterialsPageState();
}

class _MyStudyMaterialsPageState extends State<MyStudyMaterialsPage> {
  bool _loading = true;
  String? _errorMessage;
  List<_MaterialSemester> _semesters = const <_MaterialSemester>[];
  int? _currentSemester;
  String _selectedSemesterKey = 'all';
  String _selectedSubjectKey = 'all';

  @override
  void initState() {
    super.initState();
    _loadMaterials(showLoader: true);
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

  _MaterialAttachment _normalizeAttachment(Map<String, dynamic> raw) {
    return _MaterialAttachment(
      name: _stringValue(raw['name']).isNotEmpty
          ? _stringValue(raw['name'])
          : _stringValue(raw['file_name']).isNotEmpty
              ? _stringValue(raw['file_name'])
              : 'Attachment',
      url: _stringValue(raw['url']).isNotEmpty
          ? _stringValue(raw['url'])
          : _stringValue(raw['path']),
      sizeBytes: _intValue(raw['size']) ?? _intValue(raw['size_bytes']),
    );
  }

  _StudyMaterial _normalizeMaterial(
    Map<String, dynamic> raw,
    _MaterialSemester semester,
  ) {
    final subject = _asMap(raw['subject']);
    final uploader = _asMap(raw['uploaded_by']);
    final attachments = _asList(raw['attachments'])
        .map((item) => _normalizeAttachment(_asMap(item)))
        .where((item) => item.url.isNotEmpty || item.name.isNotEmpty)
        .toList();

    final subjectName = _stringValue(subject['name']).isNotEmpty
        ? _stringValue(subject['name'])
        : _stringValue(raw['subject_name']);
    final subjectCode = _stringValue(subject['code']).isNotEmpty
        ? _stringValue(subject['code'])
        : _stringValue(raw['subject_code']);

    return _StudyMaterial(
      id: _stringValue(raw['id']),
      title: _stringValue(raw['title']).isNotEmpty
          ? _stringValue(raw['title'])
          : 'Study Material',
      description: _plainText(raw['short_description']).isNotEmpty
          ? _plainText(raw['short_description'])
          : _plainText(raw['content_html']).isNotEmpty
              ? _plainText(raw['content_html'])
              : _plainText(raw['description']),
      createdAt: _stringValue(raw['created_at']),
      subjectKey: _stringValue(subject['id']).isNotEmpty
          ? _stringValue(subject['id'])
          : subjectCode.isNotEmpty
              ? subjectCode
              : subjectName,
      subjectName: subjectName,
      subjectCode: subjectCode,
      uploadedByName: _stringValue(raw['uploaded_by_name']).isNotEmpty
          ? _stringValue(raw['uploaded_by_name'])
          : _stringValue(uploader['name']).isNotEmpty
              ? _stringValue(uploader['name'])
              : 'System',
      uploadedByImage: _normalizeRemoteUrl(
        _stringValue(raw['uploaded_by_image']).isNotEmpty
            ? _stringValue(raw['uploaded_by_image'])
            : _stringValue(uploader['image']),
      ),
      semesterId: semester.semesterId,
      semesterLabel: semester.displayLabel,
      attachments: attachments,
    );
  }

  _MaterialLoadResult _extractMaterials(Map<String, dynamic> payload) {
    final root = _asMap(payload['data']).isNotEmpty
        ? _asMap(payload['data'])
        : payload;
    final academic = _asMap(root['academic']);
    final currentSemester = _intValue(academic['current_semester']);
    final semesters = <_MaterialSemester>[];

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
              ? 'Semester $semesterNumber'
              : 'General';

      final semester = _MaterialSemester(
        semesterId: semesterId,
        semesterNumber: semesterNumber,
        displayLabel: displayLabel,
        materials: const [],
      );

      final materials = _asList(row['materials'])
          .map((raw) => _normalizeMaterial(_asMap(raw), semester))
          .where((material) => material.title.isNotEmpty)
          .toList()
        ..sort(_materialDateSort);

      semesters.add(
        semester.copyWith(materials: materials),
      );
    }

    semesters.sort((a, b) {
      final aNo = a.semesterNumber ?? 0;
      final bNo = b.semesterNumber ?? 0;
      return bNo.compareTo(aNo);
    });

    return _MaterialLoadResult(
      semesters: semesters,
      currentSemester: currentSemester,
    );
  }

  Future<void> _loadMaterials({required bool showLoader}) async {
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
        endpoint: '${AppConfig.baseUrl}/api/student/study-materials',
        token: token,
      );

      final statusCode = result['statusCode'] as int;
      final payload = result['data'] as Map<String, dynamic>;
      final success = payload['success'];

      if (statusCode < 200 || statusCode >= 300 || success == false) {
        throw Exception(
          _stringValue(payload['message']).isNotEmpty
              ? _stringValue(payload['message'])
              : 'Failed to load study materials.',
        );
      }

      final extracted = _extractMaterials(payload);
      if (!mounted) return;

      setState(() {
        _semesters = extracted.semesters;
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
    final semesterExists = _semesterFilterOptions
        .any((item) => item.key == _selectedSemesterKey);
    final subjectExists =
        _subjectFilterOptions.any((item) => item.key == _selectedSubjectKey);

    if (!semesterExists || !subjectExists) {
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

  List<_StudyMaterial> get _allMaterials {
    final items = <_StudyMaterial>[];
    for (final semester in _semesters) {
      items.addAll(semester.materials);
    }
    items.sort(_materialDateSort);
    return items;
  }

  List<_MaterialFilterOption> get _semesterFilterOptions {
    final items = <_MaterialFilterOption>[
      const _MaterialFilterOption(
        key: 'all',
        label: 'All Sem',
      ),
    ];

    for (final semester in _semesters) {
      if (semester.materials.isEmpty) continue;
      items.add(
        _MaterialFilterOption(
          key: 'semester-${semester.semesterId}',
          label: semester.displayLabel,
          semesterId: semester.semesterId,
        ),
      );
    }

    return items;
  }

  List<_StudyMaterial> get _semesterFilteredMaterials {
    if (_selectedSemesterKey == 'all') return _allMaterials;

    final active = _semesterFilterOptions.firstWhere(
      (item) => item.key == _selectedSemesterKey,
      orElse: () => const _MaterialFilterOption(key: 'all', label: 'All Sem'),
    );

    final items = _allMaterials
        .where((item) => item.semesterId == active.semesterId)
        .toList()
      ..sort(_materialDateSort);
    return items;
  }

  List<_MaterialFilterOption> get _subjectFilterOptions {
    final labels = <String, String>{};

    for (final material in _semesterFilteredMaterials) {
      final key = material.subjectKey;
      if (key.isEmpty) continue;
      labels[key] = material.subjectDisplay;
    }

    final items = <_MaterialFilterOption>[
      const _MaterialFilterOption(
        key: 'all',
        label: 'All Sub',
      ),
    ];

    final sorted = labels.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    for (final entry in sorted) {
      items.add(
        _MaterialFilterOption(
          key: entry.key,
          label: entry.value,
        ),
      );
    }

    return items;
  }

  List<_StudyMaterial> get _visibleMaterials {
    final base = _semesterFilteredMaterials;
    if (_selectedSubjectKey == 'all') return base;
    return base
        .where((item) => item.subjectKey == _selectedSubjectKey)
        .toList()
      ..sort(_materialDateSort);
  }

  int _materialDateSort(_StudyMaterial a, _StudyMaterial b) {
    final aTime = DateTime.tryParse(a.createdAt)?.millisecondsSinceEpoch ?? 0;
    final bTime = DateTime.tryParse(b.createdAt)?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  }

  Uri? _attachmentUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;

    final baseUri = Uri.tryParse(AppConfig.baseUrl);
    return baseUri?.resolveUri(parsed);
  }

  String _normalizeRemoteUrl(String rawUrl) {
    final uri = _attachmentUri(rawUrl);
    return uri?.toString() ?? '';
  }

  Future<void> _showOverlayNotice({
    required BuildContext overlayContext,
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

  Future<void> _handleAttachmentAction(
    BuildContext overlayContext,
    _MaterialAttachment attachment, {
    required bool download,
  }) async {
    final uri = _attachmentUri(attachment.url);
    if (uri == null) {
      await _showOverlayNotice(
        overlayContext: overlayContext,
        title: attachment.name,
        message: 'Attachment link is not available right now.',
      );
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      await _showOverlayNotice(
        overlayContext: overlayContext,
        title: download ? 'Download failed' : 'Open failed',
        message: download
            ? 'We could not start the attachment download in the browser.'
            : 'We could not open the attachment in the browser.',
      );
    }
  }

  void _openMaterialDetailSheet(
    BuildContext overlayContext,
    _StudyMaterial material,
  ) {
    final surfaceColor = AppColors.surface(overlayContext);
    final textPrimary = AppColors.textPrimary(overlayContext);
    final textSecondary = AppColors.textSecondary(overlayContext);
    final borderColor = AppColors.borderSoft(overlayContext);

    showModalBottomSheet<void>(
      context: overlayContext,
      isScrollControlled: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.86,
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
                    material.title,
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
                      _StudyMetaChip(
                        icon: Icons.calendar_today_outlined,
                        label: _formatDateTime(material.createdAt),
                      ),
                      if (material.subjectDisplay.isNotEmpty)
                        _StudyMetaChip(
                          icon: Icons.menu_book_outlined,
                          label: material.subjectDisplay,
                        ),
                      if (material.semesterLabel.isNotEmpty)
                        _StudyMetaChip(
                          icon: Icons.school_outlined,
                          label: material.semesterLabel,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (material.uploadedByName.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              decoration: BoxDecoration(
                                color: AppColors.surface3(sheetContext),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                children: [
                                  _StudyAvatar(
                                    name: material.uploadedByName,
                                    imageUrl: material.uploadByImageSafe,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      material.uploadedByName,
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
                              color: AppColors.surface3(sheetContext),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(
                              material.description.isNotEmpty
                                  ? material.description
                                  : 'No description available for this study material.',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.55,
                              ),
                            ),
                          ),
                          if (material.attachments.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Text(
                              'Attachments',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.surface3(sheetContext).withOpacity(0.5),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: borderColor.withOpacity(0.75)),
                              ),
                              child: Column(
                                children: [
                                  for (int i = 0; i < material.attachments.length; i++) ...[
                                    _StudyAttachmentTile(
                                      attachment: material.attachments[i],
                                      onTap: () => _handleAttachmentAction(
                                        sheetContext,
                                        material.attachments[i],
                                        download: false,
                                      ),
                                      onDownload: () => _handleAttachmentAction(
                                        sheetContext,
                                        material.attachments[i],
                                        download: true,
                                      ),
                                    ),
                                    if (i != material.attachments.length - 1)
                                      const SizedBox(height: 8),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
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
                  color: AppColors.materials.withOpacity(0.18),
                ),
              ),
              child: const Icon(
                Icons.article_outlined,
                size: 16,
                color: AppColors.materials,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Study Materials',
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
          'Semester-wise materials and attachments for your course.',
          style: TextStyle(
            color: textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildInlineDropdown({
    required List<_MaterialFilterOption> options,
    required String selectedKey,
    required ValueChanged<String> onChanged,
    double? maxWidth,
  }) {
    if (options.isEmpty) return const SizedBox.shrink();

    Widget child = SizedBox(
      height: 36,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.any((item) => item.key == selectedKey)
              ? selectedKey
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
            onChanged(value);
          },
        ),
      ),
    );

    if (maxWidth != null) {
      child = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      );
    }

    return child;
  }

  Widget _buildCountBadge() {
    final count = _visibleMaterials.length;
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
        '$count material${count == 1 ? '' : 's'}',
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
                width: 180,
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
        (_selectedSubjectKey != 'all'
            ? 'No study materials are available for this subject right now.'
            : _selectedSemesterKey != 'all'
                ? 'No study materials are available for this semester right now.'
                : 'Study materials are not available right now.');

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
              Icons.article_outlined,
              color: Color(0xFF6A717C),
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No study materials',
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

  Widget _buildMaterialList() {
    final materials = _visibleMaterials;

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: materials.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final material = materials[index];
        return _StudyMaterialCard(
          material: material,
          dateLabel: _formatDateTime(material.createdAt),
          onTap: () => _openMaterialDetailSheet(context, material),
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
          onRefresh: () => _loadMaterials(showLoader: false),
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
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInlineDropdown(
                          options: _semesterFilterOptions,
                          selectedKey: _selectedSemesterKey,
                          onChanged: (value) {
                            setState(() {
                              _selectedSemesterKey = value;
                              _selectedSubjectKey = 'all';
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInlineDropdown(
                          options: _subjectFilterOptions,
                          selectedKey: _selectedSubjectKey,
                          onChanged: (value) {
                            setState(() {
                              _selectedSubjectKey = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: sectionSpacing),
                  if (_loading)
                    _buildLoadingState()
                  else if (_visibleMaterials.isEmpty)
                    _buildEmptyState()
                  else
                    _buildMaterialList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudyMaterialCard extends StatelessWidget {
  final _StudyMaterial material;
  final String dateLabel;
  final VoidCallback onTap;

  const _StudyMaterialCard({
    required this.material,
    required this.dateLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final inkColor = AppColors.ink(context);

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
                      Icons.article_outlined,
                      size: 18,
                      color: AppColors.materials,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      material.title,
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
              if (material.subjectDisplay.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  material.subjectDisplay,
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
                  _StudyAvatar(
                    name: material.uploadedByName,
                    imageUrl: material.uploadByImageSafe,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      material.uploadedByName,
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
              if (material.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  material.description,
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
              if (material.attachments.isNotEmpty) ...[
                const SizedBox(height: 14),
                _StudyAttachmentPreviewCard(
                  attachment: material.attachments.first,
                  extraCount: material.attachments.length - 1,
                ),
              ],
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
                            dateLabel,
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
                    icon: const Icon(
                      Icons.remove_red_eye_outlined,
                      size: 16,
                    ),
                    label: const Text('View Details'),
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

class _StudyMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StudyMetaChip({
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

class _StudyAttachmentPreviewCard extends StatelessWidget {
  final _MaterialAttachment attachment;
  final int extraCount;

  const _StudyAttachmentPreviewCard({
    required this.attachment,
    required this.extraCount,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface3(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _fileIcon(attachment.name),
              size: 18,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  extraCount > 0
                      ? '${attachment.sizeBytes == null ? 'Attachment' : _formatBytes(attachment.sizeBytes!)} • +$extraCount more'
                      : (attachment.sizeBytes == null
                          ? 'Attachment'
                          : _formatBytes(attachment.sizeBytes!)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StudyAttachmentTile extends StatelessWidget {
  final _MaterialAttachment attachment;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  _StudyAttachmentTile({
    required this.attachment,
    required this.onTap,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.borderSoft(context);
    final tileColor = AppColors.surface(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: tileColor.withOpacity(0.92),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor.withOpacity(0.65)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _fileIcon(attachment.name),
                  size: 20,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.name,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      attachment.sizeBytes == null
                          ? 'Attachment'
                          : _formatBytes(attachment.sizeBytes!),
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDownload ?? onTap,
                tooltip: 'Download',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  minimumSize: const Size(36, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(color: borderColor),
                ),
                icon: Icon(
                  Icons.download_rounded,
                  size: 18,
                  color: textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudyAvatar extends StatelessWidget {
  final String name;
  final String imageUrl;
  final double size;

  const _StudyAvatar({
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
                errorBuilder: (_, __, ___) => _StudyAvatarFallback(
                  letter: letter,
                  size: size,
                ),
              )
            : _StudyAvatarFallback(
                letter: letter,
                size: size,
              ),
      ),
    );
  }
}

class _StudyAvatarFallback extends StatelessWidget {
  final String letter;
  final double size;

  const _StudyAvatarFallback({
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

class _MaterialLoadResult {
  final List<_MaterialSemester> semesters;
  final int? currentSemester;

  const _MaterialLoadResult({
    required this.semesters,
    required this.currentSemester,
  });
}

class _MaterialSemester {
  final int semesterId;
  final int? semesterNumber;
  final String displayLabel;
  final List<_StudyMaterial> materials;

  const _MaterialSemester({
    required this.semesterId,
    required this.semesterNumber,
    required this.displayLabel,
    required this.materials,
  });

  _MaterialSemester copyWith({
    List<_StudyMaterial>? materials,
  }) {
    return _MaterialSemester(
      semesterId: semesterId,
      semesterNumber: semesterNumber,
      displayLabel: displayLabel,
      materials: materials ?? this.materials,
    );
  }
}

class _StudyMaterial {
  final String id;
  final String title;
  final String description;
  final String createdAt;
  final String subjectKey;
  final String subjectName;
  final String subjectCode;
  final String uploadedByName;
  final String uploadedByImage;
  final int semesterId;
  final String semesterLabel;
  final List<_MaterialAttachment> attachments;

  const _StudyMaterial({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.subjectKey,
    required this.subjectName,
    required this.subjectCode,
    required this.uploadedByName,
    required this.uploadedByImage,
    required this.semesterId,
    required this.semesterLabel,
    required this.attachments,
  });

  String get subjectDisplay {
    if (subjectName.isEmpty) return subjectCode;
    if (subjectCode.isEmpty) return subjectName;
    return '$subjectName ($subjectCode)';
  }

  String get uploadByImageSafe => uploadedByImage.trim();
}

class _MaterialAttachment {
  final String name;
  final String url;
  final int? sizeBytes;

  const _MaterialAttachment({
    required this.name,
    required this.url,
    required this.sizeBytes,
  });
}

class _MaterialFilterOption {
  final String key;
  final String label;
  final int? semesterId;

  const _MaterialFilterOption({
    required this.key,
    required this.label,
    this.semesterId,
  });
}

String _formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 Bytes';
  const units = ['Bytes', 'KB', 'MB', 'GB'];
  int index = 0;
  double value = bytes.toDouble();

  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index += 1;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : decimals)} ${units[index]}';
}

IconData _fileIcon(String name) {
  final ext = name.split('.').last.toLowerCase();
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
      return Icons.image_outlined;
    case 'doc':
    case 'docx':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
      return Icons.table_chart_outlined;
    case 'ppt':
    case 'pptx':
      return Icons.slideshow_outlined;
    case 'zip':
    case 'rar':
      return Icons.folder_zip_outlined;
    case 'mp4':
    case 'mov':
      return Icons.video_file_outlined;
    default:
      return Icons.attach_file_outlined;
  }
}
