import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:msitlms/config/appConfig.dart';
import 'package:msitlms/theme/app_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class MyNoticesPage extends StatefulWidget {
  const MyNoticesPage({super.key});

  @override
  State<MyNoticesPage> createState() => _MyNoticesPageState();
}

enum _NoticeFilterKind { all, general, semester }

class _MyNoticesPageState extends State<MyNoticesPage> {
  bool _loading = true;
  String? _errorMessage;
  int? _currentSemester;
  List<_NoticeSemester> _semesters = const <_NoticeSemester>[];

  String _selectedFilterKey = 'all';
  DateTimeRange? _selectedDateRange;

  @override
  void initState() {
    super.initState();
    _loadNotices(showLoader: true);
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

  String _normalizeUrl(String value) {
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return '${AppConfig.baseUrl}$value';
    }
    return '${AppConfig.baseUrl}/$value';
  }

  _NoticeAttachment _normalizeAttachment(Map<String, dynamic> row) {
    return _NoticeAttachment(
      name: _stringValue(row['name']).isNotEmpty
          ? _stringValue(row['name'])
          : 'Attachment',
      url: _normalizeUrl(
        _stringValue(row['url']).isNotEmpty
            ? _stringValue(row['url'])
            : _stringValue(row['path']),
      ),
      sizeBytes: _intValue(row['size']) ?? _intValue(row['file_size']),
    );
  }

  _StudentNotice _normalizeNotice({
    required Map<String, dynamic> row,
    required int semesterId,
    required int? semesterNumber,
  }) {
    final attachments = _asList(row['attachments'])
        .map((item) => _normalizeAttachment(_asMap(item)))
        .where((item) => item.name.isNotEmpty || item.url.isNotEmpty)
        .toList();

    return _StudentNotice(
      title: _stringValue(row['title']).isNotEmpty
          ? _stringValue(row['title'])
          : 'Untitled Notice',
      priority: _stringValue(row['priority']).isNotEmpty
          ? _stringValue(row['priority'])
          : 'normal',
      description: _plainText(row['short_description']).isNotEmpty
          ? _plainText(row['short_description'])
          : _plainText(row['body']).isNotEmpty
              ? _plainText(row['body'])
              : _plainText(row['body_html']),
      body: _plainText(row['body_html']).isNotEmpty
          ? _plainText(row['body_html'])
          : _plainText(row['body']),
      publishAt: _stringValue(row['publish_at']).isNotEmpty
          ? _stringValue(row['publish_at'])
          : _stringValue(row['created_at']),
      subjectId: _stringValue(row['subject_id']),
      semesterId: semesterId,
      semesterNumber: semesterNumber,
      attachments: attachments,
    );
  }

  _NoticeLoadResult _extractSemesters(Map<String, dynamic> payload) {
    final root = _asMap(payload['data']).isNotEmpty
        ? _asMap(payload['data'])
        : payload;
    final academic = _asMap(root['academic']);
    final currentSemester = _intValue(academic['current_semester']);

    final semesters = <_NoticeSemester>[];

    if (_asList(root['semesters']).isNotEmpty) {
      for (final item in _asList(root['semesters'])) {
        final row = _asMap(item);
        final semesterId =
            _intValue(row['semester_id']) ?? _intValue(row['semester_number']) ?? 0;
        final semesterNumber =
            _intValue(row['semester_number']) ?? _intValue(row['semester_id']);

        semesters.add(
          _NoticeSemester(
            semesterId: semesterId,
            semesterNumber: semesterNumber,
            title: _stringValue(row['semester_display']).isNotEmpty
                ? _stringValue(row['semester_display'])
                : _semesterTitle(semesterId),
            notices: _asList(row['notices'])
                .map(
                  (notice) => _normalizeNotice(
                    row: _asMap(notice),
                    semesterId: semesterId,
                    semesterNumber: semesterNumber,
                  ),
                )
                .toList(),
          ),
        );
      }
    } else {
      final grouped = <int, List<_StudentNotice>>{};
      final notices = _asList(root['notices']).isNotEmpty
          ? _asList(root['notices'])
          : _asList(root['flatNotices']);

      for (final item in notices) {
        final row = _asMap(item);
        final semesterId = _intValue(row['semester_id']) ?? 0;
        final semesterNumber = semesterId == 0 ? null : semesterId;

        grouped.putIfAbsent(semesterId, () => <_StudentNotice>[]);
        grouped[semesterId]!.add(
          _normalizeNotice(
            row: row,
            semesterId: semesterId,
            semesterNumber: semesterNumber,
          ),
        );
      }

      for (final entry in grouped.entries) {
        semesters.add(
          _NoticeSemester(
            semesterId: entry.key,
            semesterNumber: entry.key == 0 ? null : entry.key,
            title: _semesterTitle(entry.key),
            notices: entry.value,
          ),
        );
      }
    }

    semesters.sort((a, b) {
      final aNo = a.semesterNumber ?? 0;
      final bNo = b.semesterNumber ?? 0;
      if (aNo == 0 && bNo != 0) return 1;
      if (bNo == 0 && aNo != 0) return -1;
      return aNo.compareTo(bNo);
    });

    return _NoticeLoadResult(
      semesters: semesters,
      currentSemester: currentSemester,
    );
  }

  Future<void> _loadNotices({required bool showLoader}) async {
    final token = await _readToken();

    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Session missing. Please login again.';
      });
      return;
    }

    if (showLoader) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _errorMessage = null;
      });
    }

    try {
      final result = await _getJson(
        endpoint: '${AppConfig.baseUrl}/api/student/notices',
        token: token,
      );

      final statusCode = result['statusCode'] as int;
      final payload = result['data'] as Map<String, dynamic>;
      final success = payload['success'];

      if (statusCode < 200 || statusCode >= 300 || success == false) {
        throw Exception(
          _stringValue(payload['message']).isNotEmpty
              ? _stringValue(payload['message'])
              : 'Failed to load notices.',
        );
      }

      final extracted = _extractSemesters(payload);

      if (!mounted) return;

      setState(() {
        _semesters = extracted.semesters;
        _currentSemester = extracted.currentSemester;
        _loading = false;
      });

      _syncFilterWithScope();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _syncFilterWithScope() {
    final options = _filterOptions;
    final exists = options.any((item) => item.key == _selectedFilterKey);
    if (!exists && mounted) {
      setState(() {
        _selectedFilterKey = options.isNotEmpty ? options.first.key : 'all';
      });
    }
  }

  List<_StudentNotice> get _allNotices {
    final notices = <_StudentNotice>[];

    for (final semester in _semesters) {
      notices.addAll(semester.sortedNotices);
    }

    notices.sort(_noticeDateSort);
    return notices;
  }

  List<_NoticeFilterOption> get _filterOptions {
    final items = <_NoticeFilterOption>[
      const _NoticeFilterOption(
        key: 'all',
        label: 'All Notices',
        kind: _NoticeFilterKind.all,
      ),
    ];

    final hasGeneral = _semesters.any((item) => item.semesterId == 0);
    if (hasGeneral) {
      items.add(
        const _NoticeFilterOption(
          key: 'general',
          label: 'General Notices',
          kind: _NoticeFilterKind.general,
        ),
      );
    }

    final semesters = _semesters.where((semester) {
      final semesterNo = semester.semesterNumber ?? 0;
      return semesterNo > 0;
    }).toList();

    semesters.sort((a, b) {
      final aNo = a.semesterNumber ?? 0;
      final bNo = b.semesterNumber ?? 0;
      return bNo.compareTo(aNo);
    });

    for (final semester in semesters) {
      items.add(
        _NoticeFilterOption(
          key: 'semester-${semester.semesterNumber}',
          label: 'Semester ${semester.semesterNumber}',
          kind: _NoticeFilterKind.semester,
          semesterNumber: semester.semesterNumber,
        ),
      );
    }

    return items;
  }

  _NoticeFilterOption get _activeFilterOption {
    final options = _filterOptions;
    for (final item in options) {
      if (item.key == _selectedFilterKey) return item;
    }
    return options.first;
  }

  List<_StudentNotice> get _visibleNotices {
    final base = _allNotices;
    final active = _activeFilterOption;
    late final List<_StudentNotice> filtered;

    switch (active.kind) {
      case _NoticeFilterKind.all:
        filtered = base;
        break;

      case _NoticeFilterKind.general:
        filtered = base.where((item) => item.semesterId == 0).toList()
          ..sort(_noticeDateSort);
        break;

      case _NoticeFilterKind.semester:
        filtered = base
            .where((item) => item.semesterNumber == active.semesterNumber)
            .toList()
          ..sort(_noticeDateSort);
        break;
    }

    if (_selectedDateRange == null) return filtered;

    return filtered.where((item) {
      final publishAt = DateTime.tryParse(item.publishAt)?.toLocal();
      if (publishAt == null) return false;
      final noticeDate = DateTime(publishAt.year, publishAt.month, publishAt.day);
      final rangeStart = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
      );
      final rangeEnd = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
      );
      return !noticeDate.isBefore(rangeStart) && !noticeDate.isAfter(rangeEnd);
    }).toList()
      ..sort(_noticeDateSort);
  }

  Future<void> _pickNoticeDateRange() async {
    final now = DateTime.now();
    final initialRange = _selectedDateRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (picked == null || !mounted) return;
    setState(() {
      _selectedDateRange = picked;
    });
  }

  void _clearNoticeDateRange() {
    if (_selectedDateRange == null) return;
    setState(() {
      _selectedDateRange = null;
    });
  }

  String _formatDateRangeLabel(DateTimeRange range) {
    final start = _formatDate(range.start.toIso8601String());
    final end = _formatDate(range.end.toIso8601String());
    return start == end ? start : '$start - $end';
  }

  Widget _buildDateFilterButton() {
    final textSecondary = AppColors.textSecondary(context);
    final hasDateRange = _selectedDateRange != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _pickNoticeDateRange,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Date',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                hasDateRange
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.calendar_month_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              if (hasDateRange) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _clearNoticeDateRange,
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  int _noticeDateSort(_StudentNotice a, _StudentNotice b) {
    final aTime = DateTime.tryParse(a.publishAt)?.millisecondsSinceEpoch ?? 0;
    final bTime = DateTime.tryParse(b.publishAt)?.millisecondsSinceEpoch ?? 0;
    return bTime.compareTo(aTime);
  }

  String _semesterTitle(int semesterId) {
    return semesterId > 0 ? 'Semester $semesterId' : 'General Notices';
  }

  String _noticeSemesterLabel(_StudentNotice notice) {
    if (notice.semesterId == 0) return 'General';
    if (notice.semesterNumber != null && notice.semesterNumber! > 0) {
      return 'Semester ${notice.semesterNumber}';
    }
    return _semesterTitle(notice.semesterId);
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

  Uri? _attachmentUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;

    final baseUri = Uri.tryParse(AppConfig.baseUrl);
    return baseUri?.resolveUri(parsed);
  }

  Future<void> _handleAttachmentAction(
    BuildContext overlayContext,
    _NoticeAttachment attachment, {
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

  void _openNoticeDetailSheet(BuildContext overlayContext, _StudentNotice notice) {
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
                    notice.title,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _NoticeMetaChip(
                        icon: Icons.calendar_today_outlined,
                        label: _formatDateTime(notice.publishAt),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                            decoration: BoxDecoration(
                              color: AppColors.surface3(sheetContext),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(
                              notice.body.isNotEmpty
                                  ? notice.body
                                  : notice.description.isNotEmpty
                                      ? notice.description
                                      : 'No content available for this notice.',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.55,
                              ),
                            ),
                          ),
                          if (notice.attachments.isNotEmpty) ...[
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
                                  for (int i = 0; i < notice.attachments.length; i++) ...[
                                    _NoticeAttachmentTile(
                                      attachment: notice.attachments[i],
                                      onTap: () => _handleAttachmentAction(
                                        sheetContext,
                                        notice.attachments[i],
                                        download: false,
                                      ),
                                      onDownload: () => _handleAttachmentAction(
                                        sheetContext,
                                        notice.attachments[i],
                                        download: true,
                                      ),
                                    ),
                                    if (i != notice.attachments.length - 1)
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
                  color: AppColors.primary.withOpacity(0.16),
                ),
              ),
              child: const Icon(
                Icons.campaign_outlined,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Notices',
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
          'View your academic notices here',
          style: TextStyle(
            color: textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown() {
  final options = _filterOptions;

  if (options.isEmpty) return const SizedBox.shrink();

  return SizedBox(
    height: 36,
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: options.any((item) => item.key == _selectedFilterKey)
            ? _selectedFilterKey
            : options.first.key,
        isExpanded: true,
        isDense: true,
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: AppColors.primary,
          size: 18,
        ),
        dropdownColor: AppColors.surface(context),
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        selectedItemBuilder: (context) {
          return options.map((item) {
            return Align(
              alignment: Alignment.centerRight,
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                textAlign: TextAlign.right,
                style: TextStyle(
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
            _selectedFilterKey = value;
          });
        },
      ),
    ),
  );
}

  Widget _buildNoticeCountBadge() {
    final count = _visibleNotices.length;
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
        '$count notice${count == 1 ? '' : 's'}',
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
              const SizedBox(height: 16),
              Container(
                width: 120,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surface3(context),
                  borderRadius: BorderRadius.circular(12),
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
    final active = _activeFilterOption;
    final hasDateFilter = _selectedDateRange != null;
    final title = hasDateFilter
        ? 'No notices in ${_formatDateRangeLabel(_selectedDateRange!)}'
        : active.kind == _NoticeFilterKind.general
            ? 'No general notices'
            : active.kind == _NoticeFilterKind.semester
                ? 'No semester notices'
                : 'No notices';

    final message = _errorMessage ??
        (hasDateFilter
            ? 'Try another date or clear the date filter.'
            : active.kind == _NoticeFilterKind.general
                ? 'General notices are not available right now.'
                : active.kind == _NoticeFilterKind.semester
                    ? 'Notices for this semester are not available right now.'
                    : 'Notices are not available right now.');

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
              Icons.campaign_outlined,
              color: Color(0xFF6A717C),
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
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

  Widget _buildNoticeList() {
    final notices = _visibleNotices;

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: notices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) {
        final notice = notices[index];
        return _NoticeCard(
          notice: notice,
          dateLabel: _formatDateTime(notice.publishAt),
          onTap: () => _openNoticeDetailSheet(context, notice),
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
          onRefresh: () => _loadNotices(showLoader: false),
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
                      _buildNoticeCountBadge(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 170),
                              child: _buildFilterDropdown(),
                            ),
                            const SizedBox(width: 8),
                            _buildDateFilterButton(),
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (_selectedDateRange != null) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        _formatDateRangeLabel(_selectedDateRange!),
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: sectionSpacing),

                  if (_loading)
                    _buildLoadingState()
                  else if (_visibleNotices.isEmpty)
                    _buildEmptyState()
                  else
                    _buildNoticeList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final _StudentNotice notice;
  final String dateLabel;
  final VoidCallback onTap;

  const _NoticeCard({
    required this.notice,
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
                      Icons.campaign_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notice.title,
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

              if (notice.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  notice.description,
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

              if (notice.attachments.isNotEmpty) ...[
                const SizedBox(height: 14),
                _NoticeAttachmentPreviewCard(
                  attachment: notice.attachments.first,
                  extraCount: notice.attachments.length - 1,
                ),
              ],

              const SizedBox(height: 14),
              Divider(
                height: 1,
                thickness: 1,
                color: borderColor,
              ),
              const SizedBox(height: 10),

              Align(
                child: Row(
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoticePriorityPill extends StatelessWidget {
  final String priority;

  const _NoticePriorityPill({
    required this.priority,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _priorityAccent(priority);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            priority.toLowerCase() == 'high'
                ? Icons.priority_high_rounded
                : Icons.info_outline_rounded,
            size: 14,
            color: accent,
          ),
          const SizedBox(width: 6),
          Text(
            _priorityLabel(priority),
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeAttachmentPreviewCard extends StatelessWidget {
  final _NoticeAttachment attachment;
  final int extraCount;

  const _NoticeAttachmentPreviewCard({
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

class _SmallInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SmallInfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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

class _NoticePriorityChip extends StatelessWidget {
  final String priority;

  const _NoticePriorityChip({required this.priority});

  @override
  Widget build(BuildContext context) {
    final accent = _priorityAccent(priority);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            priority.toLowerCase() == 'high'
                ? Icons.priority_high_rounded
                : Icons.info_outline_rounded,
            size: 15,
            color: accent,
          ),
          const SizedBox(width: 6),
          Text(
            _priorityLabel(priority),
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _NoticeMetaChip({
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

class _NoticeAttachmentTile extends StatelessWidget {
  final _NoticeAttachment attachment;
  final VoidCallback onTap;
  final VoidCallback? onDownload;

  _NoticeAttachmentTile({
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

// Data Classes
class _NoticeLoadResult {
  final List<_NoticeSemester> semesters;
  final int? currentSemester;

  const _NoticeLoadResult({
    required this.semesters,
    required this.currentSemester,
  });
}

class _NoticeFilterOption {
  final String key;
  final String label;
  final _NoticeFilterKind kind;
  final int? semesterNumber;

  const _NoticeFilterOption({
    required this.key,
    required this.label,
    required this.kind,
    this.semesterNumber,
  });
}

class _NoticeSemester {
  final int semesterId;
  final int? semesterNumber;
  final String title;
  final List<_StudentNotice> notices;

  const _NoticeSemester({
    required this.semesterId,
    required this.semesterNumber,
    required this.title,
    required this.notices,
  });

  List<_StudentNotice> get sortedNotices {
    final items = List<_StudentNotice>.from(notices);
    items.sort((a, b) {
      final aTime = DateTime.tryParse(a.publishAt)?.millisecondsSinceEpoch ?? 0;
      final bTime = DateTime.tryParse(b.publishAt)?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    return items;
  }
}

class _StudentNotice {
  final String title;
  final String priority;
  final String description;
  final String body;
  final String publishAt;
  final String subjectId;
  final int semesterId;
  final int? semesterNumber;
  final List<_NoticeAttachment> attachments;

  const _StudentNotice({
    required this.title,
    required this.priority,
    required this.description,
    required this.body,
    required this.publishAt,
    required this.subjectId,
    required this.semesterId,
    required this.semesterNumber,
    required this.attachments,
  });
}

class _NoticeAttachment {
  final String name;
  final String url;
  final int? sizeBytes;

  const _NoticeAttachment({
    required this.name,
    required this.url,
    required this.sizeBytes,
  });
}

// Helper Functions
String _priorityLabel(String priority) {
  switch (priority.toLowerCase()) {
    case 'high':
      return 'Urgent';
    case 'low':
      return 'Low';
    default:
      return 'Notice';
  }
}

Color _priorityAccent(String priority) {
  switch (priority.toLowerCase()) {
    case 'high':
      return const Color(0xFFEF476F);
    case 'low':
      return const Color(0xFF2F9B93);
    default:
      return const Color(0xFF8B2E3A);
  }
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
    default:
      return Icons.insert_drive_file_outlined;
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';

  const units = ['B', 'KB', 'MB', 'GB'];
  double size = bytes.toDouble();
  int unitIndex = 0;

  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }

  final text = size >= 100 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
  return '$text ${units[unitIndex]}';
}
