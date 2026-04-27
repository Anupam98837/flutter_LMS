import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:msitlms/config/appConfig.dart';
import 'package:msitlms/theme/app_colors.dart';

class MyResultsPage extends StatefulWidget {
  const MyResultsPage({super.key});

  @override
  State<MyResultsPage> createState() => _MyResultsPageState();
}

class _MyResultsPageState extends State<MyResultsPage> {
  bool _loading = true;
  String? _errorMessage;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<_StudentResultItem> _items = const <_StudentResultItem>[];
  _ResultModuleFilter _moduleFilter = _ResultModuleFilter.all;
  int _page = 1;
  int _perPage = 20;
  int _totalPages = 1;
  int _totalCount = 0;
  bool _hasMore = false;
  String _searchQuery = '';
  Map<String, dynamic>? _emailStatusCache;

  @override
  void initState() {
    super.initState();
    _loadResults(showLoader: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
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

  double _doubleValue(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
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

  String _formatDateTime(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return raw.isEmpty ? 'N/A' : raw;

    const months = <int, String>{
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
    };

    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month]} ${date.day}, ${date.year} • $hour:$minute $period';
  }

  _StudentResultItem _normalizeItem(Map<String, dynamic> raw) {
    final game = _asMap(raw['game']);
    final result = _asMap(raw['result']);

    return _StudentResultItem(
      module: _stringValue(raw['module']),
      title: _stringValue(game['title']).isNotEmpty
          ? _stringValue(game['title'])
          : 'Result',
      attempt: _intValue(result['attempt_no']),
      score: _doubleValue(result['score']),
      submittedAt: _stringValue(
        result['result_created_at'],
      ).isNotEmpty
          ? _stringValue(result['result_created_at'])
          : _stringValue(result['created_at']),
      resultUuid: _stringValue(result['uuid']),
    );
  }

  Future<void> _loadResults({required bool showLoader}) async {
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

    final params = <String, String>{
      'page': '$_page',
      'per_page': '$_perPage',
    };
    if (_searchQuery.trim().isNotEmpty) {
      params['q'] = _searchQuery.trim();
    }
    if (_moduleFilter.apiValue.isNotEmpty) {
      params['type'] = _moduleFilter.apiValue;
    }

    final uri = Uri.parse(
      '${AppConfig.baseUrl}/api/student-results/my',
    ).replace(queryParameters: params);

    try {
      final result = await _getJson(
        endpoint: uri.toString(),
        token: token,
      );
      final statusCode = result['statusCode'] as int;
      final payload = result['data'] as Map<String, dynamic>;
      final success = payload['success'];

      if (statusCode < 200 || statusCode >= 300 || success == false) {
        throw Exception(
          _stringValue(payload['message']).isNotEmpty
              ? _stringValue(payload['message'])
              : 'Failed to load results.',
        );
      }

      final items = _asList(payload['data'])
          .map((item) => _normalizeItem(_asMap(item)))
          .toList();
      final pagination = _asMap(payload['pagination']);

      if (!mounted) return;
      setState(() {
        _items = items;
        _totalCount = _intValue(pagination['total'], fallback: items.length);
        final totalPages = _intValue(
          pagination['total_pages'],
          fallback: 1,
        );
        _totalPages = totalPages < 1 ? 1 : totalPages;
        _hasMore = pagination['has_more'] == true;
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

  Future<Map<String, dynamic>> _fetchEmailStatus({
    bool force = false,
  }) async {
    if (!force && _emailStatusCache != null) return _emailStatusCache!;

    final token = await _readToken();
    if (token.isEmpty) {
      throw Exception('Session missing. Please login again.');
    }

    final result = await _getJson(
      endpoint: '${AppConfig.baseUrl}/api/my-email-status',
      token: token,
    );
    final payload = result['data'] as Map<String, dynamic>;
    _emailStatusCache = payload;
    return payload;
  }

  String _viewUrlFor(_StudentResultItem item) {
    if (item.resultUuid.isEmpty) return '';
    switch (item.module.toLowerCase()) {
      case 'door_game':
        return '${AppConfig.baseUrl}/decision-making-test/results/${Uri.encodeComponent(item.resultUuid)}/view';
      case 'quizz':
        return '${AppConfig.baseUrl}/exam/results/${Uri.encodeComponent(item.resultUuid)}/view';
      case 'bubble_game':
        return '${AppConfig.baseUrl}/test/results/${Uri.encodeComponent(item.resultUuid)}/view';
      case 'path_game':
        return '${AppConfig.baseUrl}/path-game/results/${Uri.encodeComponent(item.resultUuid)}/view';
      default:
        return '';
    }
  }

  Future<void> _openVerifiedResult(_StudentResultItem item) async {
    final url = _viewUrlFor(item);
    if (url.isEmpty) {
      _showSnack('Unable to open result.', isError: true);
      return;
    }

    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      _showSnack('Unable to open result.', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFB42318) : const Color(0xFF166534),
      ),
    );
  }

  Future<void> _handleViewResult(_StudentResultItem item) async {
    await _openVerifiedResult(item);
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
                  color: AppColors.result.withOpacity(0.18),
                ),
              ),
              child: const Icon(
                Icons.workspace_premium_outlined,
                size: 16,
                color: AppColors.result,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'My Results',
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
              onPressed: _loading ? null : () => _loadResults(showLoader: true),
              icon: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: AppColors.result,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Check your quiz and game results here',
          style: TextStyle(
            color: textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCountBadge() {
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = AppColors.borderSoft(context);
    final count = _totalCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface3(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        '$count result${count == 1 ? '' : 's'}',
        style: TextStyle(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) {
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          setState(() {
            _searchQuery = value.trim();
            _page = 1;
          });
          _loadResults(showLoader: false);
        });
      },
      decoration: const InputDecoration(
        hintText: 'Search game / test...',
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
      itemBuilder: (_, __) => Container(
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
              width: 100,
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
              width: 190,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.surface3(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    final message = _errorMessage ??
        (_searchQuery.isNotEmpty
            ? 'Try changing the search text.'
            : 'No published results found right now.');

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
              Icons.workspace_premium_outlined,
              color: Color(0xFF6A717C),
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No results',
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

  Widget _buildPager() {
    if (_totalPages <= 1 && !_hasMore) {
      return const SizedBox.shrink();
    }

    final canGoBack = _page > 1;
    final canGoNext = _page < _totalPages || _hasMore;
    final textSecondary = AppColors.textSecondary(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Page $_page of $_totalPages',
          style: TextStyle(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: canGoBack
                    ? () {
                        setState(() {
                          _page -= 1;
                        });
                        _loadResults(showLoader: true);
                      }
                    : null,
                child: const Text('Prev'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: canGoNext
                    ? () {
                        setState(() {
                          _page += 1;
                        });
                        _loadResults(showLoader: true);
                      }
                    : null,
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultCard(_StudentResultItem item) {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final inkColor = AppColors.ink(context);
    final accent = item.filter.color;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: item.resultUuid.isEmpty ? null : () => _handleViewResult(item),
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
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      item.filter.icon,
                      size: 18,
                      color: accent,
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
                  _ResultChip(
                    icon: item.filter.icon,
                    label: item.filter.label,
                  ),
                  _ResultChip(
                    icon: Icons.repeat_rounded,
                    label: '#${item.attempt}',
                  ),
                  _ResultChip(
                    icon: Icons.stars_rounded,
                    label: item.scoreLabel,
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                            _formatDateTime(item.submittedAt),
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
                    onPressed: item.resultUuid.isEmpty
                        ? null
                        : () => _handleViewResult(item),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text('View Result'),
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

  @override
  Widget build(BuildContext context) {
    const sectionSpacing = 16.0;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      appBar: AppBar(
        backgroundColor: AppColors.surface(context),
        foregroundColor: AppColors.textPrimary(context),
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'My Results',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: AppColors.result,
          onRefresh: () => _loadResults(showLoader: false),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildCountBadge(),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSearchField(),
                const SizedBox(height: sectionSpacing),
                if (_loading)
                  _buildLoadingState()
                else if (_items.isEmpty)
                  _buildEmptyState()
                else
                  ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, index) => _buildResultCard(_items[index]),
                  ),
                if (!_loading) ...[
                  const SizedBox(height: 16),
                  _buildPager(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultEmailGateDialog extends StatefulWidget {
  final _StudentResultItem item;
  final String existingEmail;
  final ValueChanged<String> onVerified;

  const _ResultEmailGateDialog({
    required this.item,
    required this.existingEmail,
    required this.onVerified,
  });

  @override
  State<_ResultEmailGateDialog> createState() => _ResultEmailGateDialogState();
}

class _ResultEmailGateDialogState extends State<_ResultEmailGateDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  Timer? _countdownTimer;

  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _sendingResult = false;
  bool _otpStepVisible = false;
  bool _verified = false;
  String? _emailError;
  String? _otpError;
  String? _resultError;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.existingEmail;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<String> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('token') ?? prefs.getString('student_token') ?? '')
        .trim();
  }

  Future<Map<String, dynamic>> _postJson(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final token = await _readToken();
    if (token.isEmpty) {
      throw Exception('Session missing. Please login again.');
    }

    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse('${AppConfig.baseUrl}$endpoint'),
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.userAgentHeader: 'MSITLMS/1.0 (Flutter iOS/Android)',
        },
        body: jsonEncode(body),
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

      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          payload['success'] == false) {
        throw Exception(
          payload['message']?.toString() ?? 'Request failed.',
        );
      }

      return payload;
    } finally {
      client.close();
    }
  }

  void _startCooldown(int seconds) {
    _countdownTimer?.cancel();
    setState(() {
      _cooldown = seconds;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() {
          _cooldown = 0;
        });
      } else {
        setState(() {
          _cooldown -= 1;
        });
      }
    });
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim();

    setState(() {
      _emailError = null;
      _otpError = null;
      _resultError = null;
    });

    final emailPattern = RegExp(r'^\S+@\S+\.\S+$');
    if (!emailPattern.hasMatch(email)) {
      setState(() {
        _emailError = 'Please enter a valid email address.';
      });
      return;
    }

    setState(() {
      _sendingOtp = true;
    });

    try {
      await _postJson(
        '/api/student-results/send-email-otp',
        <String, dynamic>{'email': email},
      );
      if (!mounted) return;
      setState(() {
        _otpStepVisible = true;
        _otpController.clear();
      });
      _startCooldown(120);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _emailError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _sendingOtp = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();
    if (otp.length != 6) return;

    setState(() {
      _verifyingOtp = true;
      _otpError = null;
    });

    try {
      await _postJson(
        '/api/student-results/verify-email-otp',
        <String, dynamic>{
          'email': email,
          'otp': otp,
        },
      );
      if (!mounted) return;
      widget.onVerified(email);
      setState(() {
        _verified = true;
        _otpStepVisible = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _otpError = error.toString().replaceFirst('Exception: ', '');
        _otpController.clear();
      });
    } finally {
      if (mounted) {
        setState(() {
          _verifyingOtp = false;
        });
      }
    }
  }

  Future<void> _sendResultLink() async {
    final email = _emailController.text.trim();
    final viewUrl = _viewUrlFor(widget.item);
    if (viewUrl.isEmpty) {
      setState(() {
        _resultError = 'Unable to prepare result link.';
      });
      return;
    }

    setState(() {
      _sendingResult = true;
      _resultError = null;
    });

    try {
      await _postJson(
        '/api/student-results/send-result-email',
        <String, dynamic>{
          'result_uuid': widget.item.resultUuid,
          'module': widget.item.module,
          'view_url': viewUrl,
          'email': email,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _resultError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _sendingResult = false;
        });
      }
    }
  }

  String _viewUrlFor(_StudentResultItem item) {
    if (item.resultUuid.isEmpty) return '';
    switch (item.module.toLowerCase()) {
      case 'door_game':
        return '${AppConfig.baseUrl}/decision-making-test/results/${Uri.encodeComponent(item.resultUuid)}/view';
      case 'quizz':
        return '${AppConfig.baseUrl}/exam/results/${Uri.encodeComponent(item.resultUuid)}/view';
      case 'bubble_game':
        return '${AppConfig.baseUrl}/test/results/${Uri.encodeComponent(item.resultUuid)}/view';
      case 'path_game':
        return '${AppConfig.baseUrl}/path-game/results/${Uri.encodeComponent(item.resultUuid)}/view';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);

    return Dialog(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.result.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.mark_email_read_outlined,
                    color: AppColors.result,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Verify your email',
              style: TextStyle(
                color: textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'To receive your result for ${widget.item.title}, please verify your email first.',
              style: TextStyle(
                color: textSecondary,
                fontSize: 12.8,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            if (!_verified) ...[
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                readOnly: widget.existingEmail.isNotEmpty,
                decoration: InputDecoration(
                  labelText: 'Email',
                  errorText: _emailError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sendingOtp ? null : _sendOtp,
                  icon: Icon(
                    _sendingOtp
                        ? Icons.hourglass_top_rounded
                        : Icons.send_rounded,
                    size: 16,
                  ),
                  label: Text(_sendingOtp ? 'Sending OTP...' : 'Send OTP'),
                ),
              ),
            ],
            if (_otpStepVisible) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _otpController,
                maxLength: 6,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final sanitized = value.replaceAll(RegExp(r'[^0-9]'), '');
                  if (sanitized != value) {
                    _otpController.value = TextEditingValue(
                      text: sanitized,
                      selection: TextSelection.collapsed(
                        offset: sanitized.length,
                      ),
                    );
                  }
                  if (sanitized.length == 6 && !_verifyingOtp) {
                    _verifyOtp();
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Enter 6-digit OTP',
                  errorText: _otpError,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _cooldown > 0
                    ? 'Resend OTP in $_cooldown s'
                    : 'Didn’t receive it? You can resend OTP now.',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: (_cooldown > 0 || _sendingOtp) ? null : _sendOtp,
                  child: const Text('Resend OTP'),
                ),
              ),
            ],
            if (_verified) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.result.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.result.withOpacity(0.22),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppColors.result,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Email verified successfully!',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 12.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_resultError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _resultError!,
                  style: const TextStyle(
                    color: Color(0xFFB42318),
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _sendingResult ? null : _sendResultLink,
                  icon: Icon(
                    _sendingResult
                        ? Icons.hourglass_top_rounded
                        : Icons.link_rounded,
                    size: 16,
                  ),
                  label: Text(
                    _sendingResult
                        ? 'Sending Result...'
                        : 'Send Result Link to my Email',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ResultChip({
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

class _StudentResultItem {
  final String module;
  final String title;
  final int attempt;
  final double score;
  final String submittedAt;
  final String resultUuid;

  const _StudentResultItem({
    required this.module,
    required this.title,
    required this.attempt,
    required this.score,
    required this.submittedAt,
    required this.resultUuid,
  });

  _ResultModuleFilter get filter {
    switch (module.toLowerCase()) {
      case 'door_game':
        return _ResultModuleFilter.doorGame;
      case 'bubble_game':
        return _ResultModuleFilter.bubbleGame;
      case 'path_game':
        return _ResultModuleFilter.pathGame;
      case 'quizz':
        return _ResultModuleFilter.quizz;
      default:
        return _ResultModuleFilter.all;
    }
  }

  String get scoreLabel {
    if (score == score.roundToDouble()) {
      return score.toInt().toString();
    }
    return score.toStringAsFixed(1);
  }
}

enum _ResultModuleFilter {
  quizz(
    label: 'Quizz',
    apiValue: 'quizz',
    icon: Icons.quiz_outlined,
    color: AppColors.quizzes,
  ),
  doorGame(
    label: 'Door',
    apiValue: 'door_game',
    icon: Icons.door_front_door_outlined,
    color: Color(0xFFEF8A2F),
  ),
  bubbleGame(
    label: 'Bubble',
    apiValue: 'bubble_game',
    icon: Icons.bubble_chart_outlined,
    color: Color(0xFF2F9B93),
  ),
  pathGame(
    label: 'Path',
    apiValue: 'path_game',
    icon: Icons.route_outlined,
    color: Color(0xFF6C7FF2),
  ),
  all(
    label: 'All',
    apiValue: '',
    icon: Icons.layers_outlined,
    color: AppColors.result,
  );

  final String label;
  final String apiValue;
  final IconData icon;
  final Color color;

  const _ResultModuleFilter({
    required this.label,
    required this.apiValue,
    required this.icon,
    required this.color,
  });
}
