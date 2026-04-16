import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hallienzlms/config/appConfig.dart';
import 'package:hallienzlms/screens/modules/exam/exam.dart';
import 'package:hallienzlms/theme/app_colors.dart';

class MyQuizzPage extends StatefulWidget {
  final VoidCallback? onBackToDashboard;

  const MyQuizzPage({
    super.key,
    this.onBackToDashboard,
  });

  @override
  State<MyQuizzPage> createState() => _MyQuizzPageState();
}

class _MyQuizzPageState extends State<MyQuizzPage> {
  bool _loading = true;
  String? _errorMessage;
  List<_QuizItem> _allItems = const <_QuizItem>[];

  String _searchQuery = '';
  _QuizStatusFilter _statusFilter = _QuizStatusFilter.all;
  _QuizSortKind _sortKind = _QuizSortKind.newest;

  @override
  void initState() {
    super.initState();
    _loadQuizItems(showLoader: true);
  }

  Future<String> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('token') ?? prefs.getString('student_token') ?? '')
        .trim();
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

  int _intValue(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool? _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final raw = _stringValue(value).toLowerCase();
    if (raw == 'true' || raw == 'yes' || raw == '1') return true;
    if (raw == 'false' || raw == 'no' || raw == '0') return false;
    return null;
  }

  String _stripHtml(String value) {
    return value
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

  DateTime? _parseDate(dynamic value) {
    final raw = _stringValue(value);
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'N/A';
    final month = <int, String>{
      1: 'Jan',
      2: 'Feb',
      3: 'Mar',
      4: 'Apr',
      5: 'May',
      6: 'Jun',
      7: 'Jul',
      8: 'Aug',
      9: 'Sep',
      10: 'Oct',
      11: 'Nov',
      12: 'Dec',
    }[value.month];
    return '${value.day} $month ${value.year}';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'N/A';
    final period = value.hour >= 12 ? 'PM' : 'AM';
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    return '${_formatDate(value)} • $hour:$minute $period';
  }

  List<dynamic> _extractItems(Map<String, dynamic> payload) {
    final root = _asMap(payload['data']).isNotEmpty
        ? _asMap(payload['data'])
        : payload;

    final candidates = <dynamic>[
      root['items'],
      root['quizzes'],
      root['games'],
      root['records'],
      root['rows'],
      payload['items'],
      payload['quizzes'],
      payload['games'],
      payload['data'],
    ];

    for (final candidate in candidates) {
      if (candidate is List) return candidate;
    }

    return const [];
  }

  _QuizItem _normalizeItem(
    Map<String, dynamic> row,
    _QuizItemType type,
  ) {
    final assignedAt = _parseDate(
      row['assigned_at'] ?? row['created_at'] ?? row['publish_at'],
    );
    final description = _stripHtml(
      _stringValue(
        row['instructions_html'] ??
            row['instructions'] ??
            row['description_html'] ??
            row['description'] ??
            row['excerpt'] ??
            row['note'],
      ),
    );
    final title = _stringValue(row['title']).isNotEmpty
        ? _stringValue(row['title'])
        : _stringValue(row['name']).isNotEmpty
            ? _stringValue(row['name'])
            : 'Untitled ${type.label}';

    final durationMinutes = _intValue(
      row['total_time'] ??
          row['total_time_minutes'] ??
          row['duration'] ??
          row['time_limit_minutes'],
    );
    final timeLimitSeconds = _intValue(
      row['time_limit_sec'] ?? row['time_limit'],
    );
    final resolvedDuration = durationMinutes > 0
        ? durationMinutes
        : timeLimitSeconds > 0
            ? (timeLimitSeconds / 60).ceil()
            : 0;

    final allowedAttempts = _intValue(
      row['max_attempts_allowed'] ??
          row['max_attempts'] ??
          row['max_attempt'] ??
          row['total_attempts_allowed'] ??
          row['attempts_allowed'] ??
          row['allowed_attempts'],
      fallback: 1,
    );

    final usedAttempts = _intValue(
      row['attempt_total_count'] ??
          row['my_attempts'] ??
          row['attempts_used'] ??
          row['attempts_taken'] ??
          row['attempt_count'] ??
          row['latest_attempt_no'] ??
          row['used_attempts'] ??
          _asMap(row['result'])['attempt_no'],
    );

    final canAttempt = _boolValue(row['can_attempt']);
    final maxReached = _boolValue(row['max_attempt_reached']) == true;
    final myStatus = _QuizStatusX.fromRaw(
      _stringValue(row['my_status']).isNotEmpty
          ? _stringValue(row['my_status'])
          : _stringValue(row['myStatus']),
      usedAttempts: usedAttempts,
      canAttempt: canAttempt,
      maxReached: maxReached,
    );

    return _QuizItem(
      uuid: _stringValue(row['uuid']).isNotEmpty
          ? _stringValue(row['uuid'])
          : _stringValue(row['id']),
      type: type,
      title: title,
      description: description,
      instructionsHtml: _stringValue(row['instructions_html']),
      assignedAt: assignedAt,
      status: _stringValue(row['status']).isNotEmpty
          ? _stringValue(row['status'])
          : 'active',
      myStatus: myStatus,
      durationMinutes: resolvedDuration,
      usedAttempts: usedAttempts,
      allowedAttempts: allowedAttempts <= 0 ? 1 : allowedAttempts,
      remainingAttempts: _intValue(
        row['remaining_attempts'],
        fallback: (allowedAttempts <= 0 ? 1 : allowedAttempts) - usedAttempts,
      ),
      canAttempt: canAttempt,
      maxAttemptReached: maxReached,
    );
  }

  Future<List<_QuizItem>> _fetchItemsForType(
    _QuizItemType type,
    String token,
  ) async {
    final result = await _getJson(
      endpoint: '${AppConfig.baseUrl}${type.endpoint}?page=1&per_page=1000',
      token: token,
    );

    final statusCode = result['statusCode'] as int;
    final payload = result['data'] as Map<String, dynamic>;

    if (statusCode == 401 || statusCode == 403) {
      throw Exception('Session expired. Please login again.');
    }

    if (statusCode < 200 || statusCode >= 300) {
      throw Exception(
        _stringValue(payload['message']).isNotEmpty
            ? _stringValue(payload['message'])
            : 'Failed to load ${type.label.toLowerCase()} items.',
      );
    }

    return _extractItems(payload)
        .map((item) => _normalizeItem(_asMap(item), type))
        .where((item) => item.uuid.isNotEmpty)
        .toList();
  }

  Future<void> _loadQuizItems({required bool showLoader}) async {
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
      final results = await Future.wait(
        _QuizItemType.values.map((type) async {
          try {
            return (
              items: await _fetchItemsForType(type, token),
              success: true,
            );
          } catch (_) {
            return (items: <_QuizItem>[], success: false);
          }
        }),
      );

      final merged = results.expand((result) => result.items).toList()
        ..sort((a, b) => b.sortDate.compareTo(a.sortDate));
      final hasAnySuccess = results.any((result) => result.success);

      if (!hasAnySuccess) {
        throw Exception('Failed to load exams.');
      }

      if (!mounted) return;
      setState(() {
        _allItems = merged;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<_QuizItem> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _allItems.where((item) {
      final matchesStatus = switch (_statusFilter) {
        _QuizStatusFilter.all => true,
        _QuizStatusFilter.fresh => item.myStatus == _QuizProgressStatus.fresh,
        _QuizStatusFilter.inProgress =>
          item.myStatus == _QuizProgressStatus.inProgress,
        _QuizStatusFilter.finished =>
          item.myStatus == _QuizProgressStatus.finished,
      };

      final matchesQuery = query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          item.type.label.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query);

      return matchesStatus && matchesQuery;
    }).toList();

    switch (_sortKind) {
      case _QuizSortKind.newest:
        filtered.sort((a, b) => b.sortDate.compareTo(a.sortDate));
        break;
      case _QuizSortKind.oldest:
        filtered.sort((a, b) => a.sortDate.compareTo(b.sortDate));
        break;
      case _QuizSortKind.attempts:
        filtered.sort((a, b) => b.usedAttempts.compareTo(a.usedAttempts));
        break;
      case _QuizSortKind.title:
        filtered.sort((a, b) => a.title.compareTo(b.title));
        break;
    }

    return filtered;
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              error ? AppColors.dangerStrong : AppColors.success,
        ),
      );
  }

  Future<void> _openInstructions(_QuizItem item) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) {
        final textPrimary = AppColors.textPrimary(context);
        final textSecondary = AppColors.textSecondary(context);
        final border = AppColors.borderSoft(context);
        final fill = AppColors.surface2(context);

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 54,
                    height: 5,
                    decoration: BoxDecoration(
                      color: border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  item.title,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${item.type.label} • ${_formatDateTime(item.assignedAt)}',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                  ),
                  child: Text(
                    item.description.isNotEmpty
                        ? item.description
                        : 'No instructions available for this item.',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
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

  Future<void> _startItem(_QuizItem item) async {
    if (item.uuid.isEmpty) {
      _showSnack('Unable to open this item.', error: true);
      return;
    }

    if (!item.canStart) {
      _showSnack('This item is not available right now.', error: true);
      return;
    }

    if (item.type == _QuizItemType.quiz) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExamPage(
            quizKey: item.uuid,
            isDark: AppColors.isDark(context),
            onExamFinished: widget.onBackToDashboard == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onBackToDashboard?.call();
                  },
          ),
        ),
      );

      if (mounted) {
        unawaited(_loadQuizItems(showLoader: false));
      }
      return;
    }

    final uri = Uri.parse(
      '${AppConfig.baseUrl}${item.type.startPath}${Uri.encodeComponent(item.uuid)}',
    );
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched) {
      _showSnack('Unable to open ${item.type.label.toLowerCase()}.', error: true);
    }
  }

  int _countByStatus(_QuizProgressStatus status) {
    return _allItems.where((item) => item.myStatus == status).length;
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _filteredItems;
    final muted = AppColors.dashboardMutedColor(context);
    const sectionSpacing = 16.0;

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => RefreshIndicator(
          color: muted,
          onRefresh: () => _loadQuizItems(showLoader: false),
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 640;
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildQuizCountBadge(visibleItems.length),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _buildStatusDropdown()),
                                const SizedBox(width: 8),
                                Expanded(child: _buildSortDropdownCompact()),
                              ],
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          _buildQuizCountBadge(visibleItems.length),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 170),
                                  child: _buildStatusDropdown(),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 170),
                                  child: _buildSortDropdownCompact(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _buildSearchField(),
                  const SizedBox(height: sectionSpacing),
                  if (_loading)
                    _buildLoadingState()
                  else if (_errorMessage != null)
                    _buildMessageCard(
                      context,
                      title: 'Unable to load quizzes',
                      subtitle: _errorMessage!,
                      icon: Icons.error_outline_rounded,
                      accent: AppColors.dangerStrong,
                      onRetry: () => _loadQuizItems(showLoader: true),
                    )
                  else if (_allItems.isEmpty)
                    _buildMessageCard(
                      context,
                      title: 'No Quizzes Yet',
                      subtitle:
                          'Your quizzes and games will appear here once they are assigned to you.',
                      icon: Icons.quiz_outlined,
                      accent: AppColors.quizzes,
                    )
                  else if (visibleItems.isEmpty)
                    _buildMessageCard(
                      context,
                      title: 'No Matching Quizzes',
                      subtitle:
                          'Try changing the filter or search text.',
                      icon: Icons.filter_alt_off_rounded,
                      accent: AppColors.quizzes,
                    )
                  else
                    _buildQuizList(visibleItems),
                ],
              ),
            ),
          ),
        ),
      ),
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
                Icons.quiz_outlined,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Quizzes',
              style: TextStyle(
                color: textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : () => _loadQuizItems(showLoader: true),
              icon: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'View your assigned quizzes and exam activities here',
          style: TextStyle(
            color: textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildQuizCountBadge(int count) {
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
        '$count quiz${count == 1 ? '' : 'zes'}',
        style: TextStyle(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return SizedBox(
      height: 36,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_QuizStatusFilter>(
          value: _statusFilter,
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
            return _QuizStatusFilter.values.map((item) {
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
          items: _QuizStatusFilter.values.map((item) {
            return DropdownMenuItem<_QuizStatusFilter>(
              value: item,
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
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _statusFilter = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildSortDropdownCompact() {
    return SizedBox(
      height: 36,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_QuizSortKind>(
          value: _sortKind,
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
            return _QuizSortKind.values.map((item) {
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
          items: _QuizSortKind.values.map((item) {
            return DropdownMenuItem<_QuizSortKind>(
              value: item,
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
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _sortKind = value;
            });
          },
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
      decoration: const InputDecoration(
        hintText: 'Search quiz title...',
        prefixIcon: Icon(Icons.search_rounded),
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
      itemBuilder: (_, __) => _buildSkeletonCard(context),
    );
  }

  Widget _buildQuizList(List<_QuizItem> items) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => _buildItemCard(
        context,
        items[index],
      ),
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    _QuizItem item,
  ) {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final inkColor = AppColors.ink(context);
    final statusColor = item.myStatus.color;
    final startLabel = item.myStatus == _QuizProgressStatus.inProgress
        ? 'Continue'
        : item.myStatus == _QuizProgressStatus.finished
            ? 'Retake'
            : 'Start';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: item.hasInstructions ? () => _openInstructions(item) : null,
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
                      Icons.quiz_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title,
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SmallQuizInfoChip(
                    icon: Icons.category_outlined,
                    label: item.type.label,
                  ),
                  _SmallQuizInfoChip(
                    icon: Icons.repeat_rounded,
                    label: '${item.usedAttempts}/${item.allowedAttempts}',
                  ),
                  _QuizStatusChip(
                    label: item.myStatus.label,
                    color: statusColor,
                  ),
                ],
              ),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item.description,
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
                            _formatDate(item.assignedAt),
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
                    onPressed: item.hasInstructions
                        ? () => _openInstructions(item)
                        : null,
                    icon: const Icon(
                      Icons.remove_red_eye_outlined,
                      size: 16,
                    ),
                    label: const Text('View'),
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
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: item.canStart ? () => _startItem(item) : null,
                    icon: const Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                    ),
                    label: Text(startLabel),
                    style: TextButton.styleFrom(
                      foregroundColor: item.canStart
                          ? AppColors.primary
                          : AppColors.textSecondary(context),
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

  Widget _buildMessageCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    VoidCallback? onRetry,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderSoft(context)),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.6,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkeletonCard(BuildContext context) {
    final fill = AppColors.surface(context);
    final border = AppColors.borderSoft(context);
    final shimmer = AppColors.softFill(context);

    Widget line(double width, {double height = 12}) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: shimmer,
          borderRadius: BorderRadius.circular(999),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(180, height: 16),
          const SizedBox(height: 10),
          line(120),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              line(96, height: 42),
              line(96, height: 42),
              line(96, height: 42),
            ],
          ),
          const SizedBox(height: 16),
          line(double.infinity, height: 12),
          const SizedBox(height: 8),
          line(220, height: 12),
        ],
      ),
    );
  }
}

class _SmallQuizInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SmallQuizInfoChip({
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

class _QuizStatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _QuizStatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

enum _QuizItemType {
  quiz('/api/quizz/my', '/exam/', 'Quiz'),
  game('/api/bubble-games/my', '/tests/play?game=', 'Game'),
  door('/api/door-games/my', '/door-tests/play?game=', 'Door'),
  path('/api/path-games/my', '/path-tests/play?game=', 'Path');

  final String endpoint;
  final String startPath;
  final String label;

  const _QuizItemType(this.endpoint, this.startPath, this.label);
}

enum _QuizProgressStatus {
  fresh('New', AppColors.warning),
  inProgress('In Progress', AppColors.primary),
  finished('Finished', AppColors.success);

  final String label;
  final Color color;

  const _QuizProgressStatus(this.label, this.color);
}

extension _QuizStatusX on _QuizProgressStatus {
  static _QuizProgressStatus fromRaw(
    String raw, {
    required int usedAttempts,
    required bool? canAttempt,
    required bool maxReached,
  }) {
    switch (raw.toLowerCase()) {
      case 'completed':
      case 'finished':
      case 'submitted':
        return _QuizProgressStatus.finished;
      case 'in_progress':
      case 'progress':
      case 'running':
        return _QuizProgressStatus.inProgress;
      default:
        if (maxReached || (canAttempt == false && usedAttempts > 0)) {
          return _QuizProgressStatus.finished;
        }
        return _QuizProgressStatus.fresh;
    }
  }
}

enum _QuizStatusFilter {
  all('All'),
  fresh('New'),
  inProgress('In Progress'),
  finished('Finished');

  final String label;

  const _QuizStatusFilter(this.label);
}

enum _QuizSortKind {
  newest('Newest first'),
  oldest('Oldest first'),
  attempts('Attempts used'),
  title('Title');

  final String label;

  const _QuizSortKind(this.label);
}

class _QuizItem {
  final String uuid;
  final _QuizItemType type;
  final String title;
  final String description;
  final String instructionsHtml;
  final DateTime? assignedAt;
  final String status;
  final _QuizProgressStatus myStatus;
  final int durationMinutes;
  final int usedAttempts;
  final int allowedAttempts;
  final int remainingAttempts;
  final bool? canAttempt;
  final bool maxAttemptReached;

  const _QuizItem({
    required this.uuid,
    required this.type,
    required this.title,
    required this.description,
    required this.instructionsHtml,
    required this.assignedAt,
    required this.status,
    required this.myStatus,
    required this.durationMinutes,
    required this.usedAttempts,
    required this.allowedAttempts,
    required this.remainingAttempts,
    required this.canAttempt,
    required this.maxAttemptReached,
  });

  DateTime get sortDate => assignedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  String get durationLabel =>
      durationMinutes > 0 ? '$durationMinutes min' : '—';

  bool get hasInstructions =>
      description.trim().isNotEmpty || instructionsHtml.trim().isNotEmpty;

  bool get canStart {
    if (status.toLowerCase() != 'active') return false;
    if (myStatus == _QuizProgressStatus.inProgress) return true;
    if (maxAttemptReached) return false;
    if (canAttempt == false) return false;
    return remainingAttempts > 0 || usedAttempts < allowedAttempts;
  }
}
