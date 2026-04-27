import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:msitlms/config/appConfig.dart';
import 'package:msitlms/screens/structure.dart';
import 'package:msitlms/theme/app_colors.dart';

class LoginPage extends StatefulWidget {
  final String? initialIdentifier;
  final String? initialPassword;
  final VoidCallback? onForgotPassword;

  const LoginPage({
    super.key,
    this.initialIdentifier,
    this.initialPassword,
    this.onForgotPassword,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

enum NoticeType { success, error, warning }

class InlineNotice {
  final String message;
  final NoticeType type;

  const InlineNotice({
    required this.message,
    required this.type,
  });
}

class _LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  static const MethodChannel _deepLinkMethodChannel = MethodChannel(
    'msitlms/deep_links',
  );
  static const EventChannel _deepLinkEventChannel = EventChannel(
    'msitlms/deep_links/events',
  );
  static const String _sendLoginOtpApi = '/api/auth/send-login-otp';
  static const String _loginWithOtpApi = '/api/auth/login-with-otp';
  static const String _checkApi = '/api/auth/check';
  static const String _googleRedirectPath = '/api/auth/google/redirect';
  static const int _captchaLength = 6;
  static const int _otpLength = 6;
  static const String _allowedDomain1 = 'msit.edu.in';
  static const String _allowedDomain2 = 'hallienz.com';
  static const String _allowedDomain3 = 'hallienz.org';

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _captchaController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    _otpLength,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(
    _otpLength,
    (_) => FocusNode(),
  );

  final math.Random _random = math.Random();

  bool _keepLoggedIn = false;
  bool _checkingSavedSession = false;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _googleLoading = false;
  bool _otpSent = false;
  bool _captchaSolved = false;
  int _resendSeconds = 0;
  int _otpSendCount = 0;

  String _captchaText = '';
  String? _emailError;
  InlineNotice? _notice;

  Timer? _resendTimer;
  Timer? _autoVerifyTimer;
  StreamSubscription<dynamic>? _deepLinkSubscription;
  String? _lastHandledCallbackUrl;
  bool _handlingGoogleCallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _emailController.text = widget.initialIdentifier?.trim() ?? '';
    _captchaText = _generateCaptchaText();
    _initGoogleCallbackHandling();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleEmailChanged();
      _tryAutoLoginFromSavedToken();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resendTimer?.cancel();
    _autoVerifyTimer?.cancel();
    _deepLinkSubscription?.cancel();
    _emailController.dispose();
    _captchaController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _setNotice(String message, NoticeType type) {
    if (!mounted) return;
    setState(() {
      _notice = InlineNotice(message: message, type: type);
    });
  }

  void _clearNotice() {
    if (!mounted || _notice == null) return;
    setState(() {
      _notice = null;
    });
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
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
  }

  Future<Map<String, dynamic>> _postJson(
    String endpoint,
    Map<String, dynamic> payload,
  ) async {
    final client = http.Client();

    try {
      final response = await client
          .post(
            Uri.parse(endpoint),
            headers: {
              HttpHeaders.acceptHeader: 'application/json',
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.userAgentHeader:
                  'MSITLMS/1.0 (Flutter iOS/Android)',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      return _decodeResponse(response);
    } finally {
      client.close();
    }
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

      return _decodeResponse(response);
    } finally {
      client.close();
    }
  }

  String _extractMessage(
    Map<String, dynamic> data, {
    String fallback = 'Something went wrong.',
  }) {
    if (data['message'] is String &&
        (data['message'] as String).trim().isNotEmpty) {
      return (data['message'] as String).trim();
    }

    if (data['error'] is String &&
        (data['error'] as String).trim().isNotEmpty) {
      return (data['error'] as String).trim();
    }

    if (data['errors'] is Map) {
      final errors = data['errors'] as Map;
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) {
          return value.first.toString();
        }
        if (value != null) {
          return value.toString();
        }
      }
    }

    return fallback;
  }

  String _humanizeNetworkError(Object error) {
    if (error is SocketException) {
      return 'Could not connect to server. Please check internet or server availability.';
    }

    if (error is HandshakeException) {
      return 'Secure connection failed on iPhone. The SSL certificate for the server may need fixing.';
    }

    if (error is HttpException) {
      return 'HTTP error: ${error.message}';
    }

    return 'Unexpected error: $error';
  }

  Future<void> _saveAuth({
    required String token,
    required String role,
    required bool keepLoggedIn,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('role', role);
    await prefs.setBool('keep_logged_in', keepLoggedIn);
  }

  Future<void> _clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    await prefs.remove('keep_logged_in');
  }

  void _goToStructure({String? userName}) {
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => StructurePage(userName: userName),
      ),
      (route) => false,
    );
  }

  Future<void> _tryAutoLoginFromSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final bool keep = prefs.getBool('keep_logged_in') ?? false;
    final String token = prefs.getString('token') ?? '';
    final String savedRole = prefs.getString('role') ?? '';

    if (!keep || token.isEmpty) return;

    if (!mounted) return;
    setState(() {
      _checkingSavedSession = true;
    });

    String? redirectUserName;

    try {
      final result = await _getJson(
        '${AppConfig.baseUrl}$_checkApi',
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
      );

      final int statusCode = result['statusCode'] as int;
      final Map<String, dynamic> data =
          result['data'] as Map<String, dynamic>;

      if (statusCode >= 200 && statusCode < 300 && data['user'] is Map) {
        final Map<String, dynamic> userMap =
            Map<String, dynamic>.from(data['user'] as Map);

        final String resolvedRole =
            (userMap['role'] ?? savedRole)
                .toString()
                .trim()
                .toLowerCase()
                .ifEmpty('student');

        await _saveAuth(
          token: token,
          role: resolvedRole,
          keepLoggedIn: true,
        );

        redirectUserName = (userMap['name'] ?? 'User').toString();
      } else {
        await _clearAuth();
      }
    } on TimeoutException catch (e) {
      debugPrint('Auto-login timeout: $e');
    } catch (e, st) {
      debugPrint('Auto-login error: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      if (mounted) {
        setState(() {
          _checkingSavedSession = false;
        });
      }
    }

    if (redirectUserName != null && mounted) {
      _goToStructure(userName: redirectUserName);
    }
  }

  String _normalizeEmail(String value) => value.trim().toLowerCase();

  bool _validEmail(String value) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(
      _normalizeEmail(value),
    );
  }

  String _getEmailDomain(String value) {
    final email = _normalizeEmail(value);
    final atPos = email.lastIndexOf('@');
    if (atPos == -1) return '';
    return email.substring(atPos + 1);
  }

  bool _hasAllowedDomain(String value) {
    final domain = _getEmailDomain(value);
    return domain == _allowedDomain1 ||
        domain == _allowedDomain2 ||
        domain == _allowedDomain3;
  }

  Future<void> _initGoogleCallbackHandling() async {
    _deepLinkSubscription = _deepLinkEventChannel.receiveBroadcastStream().listen(
      (dynamic link) {
        final uri = Uri.tryParse(link?.toString() ?? '');
        if (uri != null) {
          _handleIncomingGoogleCallback(uri);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Google callback stream error: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (mounted) {
          setState(() {
            _googleLoading = false;
          });
        }
      },
    );

    await _pullPendingGoogleCallback(method: 'getInitialLink');
  }

  Future<void> _pullPendingGoogleCallback({
    String method = 'getLatestLink',
  }) async {
    try {
      final link = await _deepLinkMethodChannel.invokeMethod<String>(method);
      final uri = Uri.tryParse(link ?? '');
      if (uri != null) {
        await _handleIncomingGoogleCallback(uri);
      }
    } catch (error, stackTrace) {
      debugPrint('Pending app link error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _clearPendingGoogleCallback() async {
    try {
      await _deepLinkMethodChannel.invokeMethod<void>('clearLatestLink');
    } catch (error, stackTrace) {
      debugPrint('Clear app link error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _pullPendingGoogleCallback();
    }
  }

  bool _isGoogleCallbackUri(Uri uri) {
    final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
    return uri.scheme == 'msitlms' &&
        uri.host == 'auth' &&
        path == '/callback';
  }

  Future<void> _handleIncomingGoogleCallback(Uri uri) async {
    if (!_isGoogleCallbackUri(uri)) return;

    final callbackUrl = uri.toString();
    if (_handlingGoogleCallback || _lastHandledCallbackUrl == callbackUrl) {
      return;
    }

    final status = (uri.queryParameters['status'] ?? '').trim().toLowerCase();
    if (status.isEmpty) return;

    _handlingGoogleCallback = true;
    _lastHandledCallbackUrl = callbackUrl;

    final token = (uri.queryParameters['token'] ?? '').trim();
    final role =
        (uri.queryParameters['role'] ?? 'student').trim().toLowerCase();
    final keepValue = (uri.queryParameters['keep'] ?? '').trim();
    final keepLoggedIn =
        keepValue == '1' || keepValue.toLowerCase() == 'true';
    final name = (uri.queryParameters['name'] ?? '').trim();
    final message = (uri.queryParameters['message'] ?? '').trim();

    if (mounted) {
      setState(() {
        _googleLoading = false;
      });
    }

    try {
      if (status == 'success') {
        if (token.isEmpty) {
          await _clearPendingGoogleCallback();
          _setNotice(
            message.isNotEmpty ? message : 'Google login failed.',
            NoticeType.error,
          );
          return;
        }

        await _saveAuth(
          token: token,
          role: role.isEmpty ? 'student' : role,
          keepLoggedIn: keepLoggedIn,
        );

        await _clearPendingGoogleCallback();
        _clearNotice();
        _goToStructure(userName: name.isEmpty ? null : name);
        return;
      }

      if (status == 'error') {
        await _clearPendingGoogleCallback();
        _setNotice(
          message.isNotEmpty ? message : 'Google login failed.',
          NoticeType.error,
        );
      }
    } finally {
      _handlingGoogleCallback = false;
    }
  }

  bool _isAllowedInstituteEmail(String value) {
    return _validEmail(value) && _hasAllowedDomain(value);
  }

  String _generateCaptchaText() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(
      _captchaLength,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  void _generateNewCaptcha({bool clearInput = true}) {
    _autoVerifyTimer?.cancel();
    setState(() {
      _captchaText = _generateCaptchaText();
      _captchaSolved = false;
      if (clearInput) {
        _captchaController.clear();
      }
    });
  }

  void _stopOtpCooldown() {
    _resendTimer?.cancel();
    _resendTimer = null;
    if (!mounted) return;
    setState(() {
      _resendSeconds = 0;
    });
  }

  void _startOtpCooldown(int seconds) {
    _resendTimer?.cancel();
    setState(() {
      _resendSeconds = seconds;
    });

    if (seconds <= 0) return;

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() {
          _resendSeconds = 0;
        });
      } else {
        setState(() {
          _resendSeconds -= 1;
        });
      }
    });
  }

  int _delayForCount(int count) {
    const delays = [30, 60, 120, 180, 240, 300];
    final index = math.max(0, math.min(count - 1, delays.length - 1));
    return delays[index];
  }

  String get _currentEmail => _normalizeEmail(_emailController.text);

  bool get _canUnlockCaptcha =>
      _isAllowedInstituteEmail(_currentEmail) &&
      !_sendingOtp &&
      !_verifyingOtp;

  bool get _canSendOtp =>
      _canUnlockCaptcha && _captchaSolved && _resendSeconds <= 0;

  String get _otpValue =>
      _otpControllers.map((controller) => controller.text.trim()).join();

  bool get _canVerifyOtp =>
      _otpSent && !_verifyingOtp && _otpValue.length == _otpLength;

  void _clearOtpBoxes() {
    for (final controller in _otpControllers) {
      controller.clear();
    }
    _autoVerifyTimer?.cancel();
  }

  void _focusOtpBox(int index) {
    if (index < 0 || index >= _otpFocusNodes.length) return;
    final node = _otpFocusNodes[index];
    if (!node.canRequestFocus) return;
    node.requestFocus();
  }

  void _focusFirstEmptyOtpBox() {
    final index = _otpControllers.indexWhere(
      (controller) => controller.text.trim().isEmpty,
    );
    _focusOtpBox(index == -1 ? _otpControllers.length - 1 : index);
  }

  void _resetOtpState({bool hidePanel = true}) {
    _autoVerifyTimer?.cancel();
    _clearOtpBoxes();
    setState(() {
      _otpSent = !hidePanel && _otpSent;
      if (hidePanel) {
        _otpSent = false;
      }
    });
  }

  void _prepareOtpEntryState() {
    _clearOtpBoxes();
    setState(() {
      _otpSent = true;
    });
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) _focusOtpBox(0);
    });
  }

  void _handleEmailChanged() {
    _clearNotice();

    if (_emailError != null) {
      setState(() {
        _emailError = null;
      });
    }

    _otpSendCount = 0;
    _stopOtpCooldown();
    _resetOtpState();
    if (_captchaController.text.isNotEmpty || _captchaSolved) {
      setState(() {
        _captchaController.clear();
        _captchaSolved = false;
      });
    }
  }

  void _validateCaptchaInput(String rawValue) {
    final normalized = rawValue.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (normalized != rawValue) {
      _captchaController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }

    if (!_canUnlockCaptcha) {
      if (_captchaSolved) {
        setState(() {
          _captchaSolved = false;
        });
      }
      return;
    }

    final solved = normalized.isNotEmpty && normalized == _captchaText;
    if (_captchaSolved == solved) return;

    setState(() {
      _captchaSolved = solved;
    });
  }

  Future<void> _sendOtp() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final email = _currentEmail;

    if (!_validEmail(email)) {
      setState(() {
        _emailError = 'Please enter a valid email address.';
      });
      _setNotice('Please enter a valid email.', NoticeType.error);
      return;
    }

    if (!_hasAllowedDomain(email)) {
      setState(() {
        _emailError = 'Your gmail not allowed.';
      });
      _setNotice('Your email is not allowed.', NoticeType.error);
      return;
    }

    if (!_captchaSolved) {
      _setNotice('Please enter the correct captcha first.', NoticeType.error);
      return;
    }

    setState(() {
      _sendingOtp = true;
    });
    _clearNotice();
    _resetOtpState();

    try {
      final result = await _postJson(
        '${AppConfig.baseUrl}$_sendLoginOtpApi',
        {'email': email},
      );

      final int statusCode = result['statusCode'] as int;
      final Map<String, dynamic> data =
          result['data'] as Map<String, dynamic>;

      if (statusCode == 429) {
        final seconds = int.tryParse('${data['seconds_left'] ?? 0}') ?? 0;
        if (seconds > 0) {
          _startOtpCooldown(seconds);
        }
        _setNotice(
          _extractMessage(
            data,
            fallback: 'Please wait before requesting another OTP.',
          ),
          NoticeType.warning,
        );
        return;
      }

      if (statusCode < 200 || statusCode >= 300) {
        _setNotice(
          _extractMessage(data, fallback: 'Failed to send OTP.'),
          NoticeType.error,
        );
        _generateNewCaptcha();
        return;
      }

      _otpSendCount += 1;
      _startOtpCooldown(_delayForCount(_otpSendCount));
      _prepareOtpEntryState();
      _setNotice(
        _extractMessage(data, fallback: 'OTP sent successfully.'),
        NoticeType.success,
      );
    } on TimeoutException {
      _setNotice('Request timed out while sending OTP.', NoticeType.error);
    } on SocketException catch (e, st) {
      debugPrint('Send OTP socket error: $e');
      debugPrintStack(stackTrace: st);
      _setNotice(_humanizeNetworkError(e), NoticeType.error);
    } catch (e, st) {
      debugPrint('Send OTP error: $e');
      debugPrintStack(stackTrace: st);
      _setNotice(_humanizeNetworkError(e), NoticeType.error);
    } finally {
      if (mounted) {
        setState(() {
          _sendingOtp = false;
        });
      }
    }
  }

  Future<void> _loginWithOtp() async {
    if (!_canVerifyOtp) return;

    final email = _currentEmail;
    final otp = _otpValue.replaceAll(RegExp(r'\D'), '');

    setState(() {
      _verifyingOtp = true;
    });
    _clearNotice();

    try {
      final result = await _postJson(
        '${AppConfig.baseUrl}$_loginWithOtpApi',
        {
          'email': email,
          'otp': otp,
        },
      );

      final int statusCode = result['statusCode'] as int;
      final Map<String, dynamic> data =
          result['data'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        final bool shouldResetOtp = data['expired'] == true ||
            statusCode == 404 ||
            statusCode == 429;

        if (shouldResetOtp) {
          _clearOtpBoxes();
          setState(() {
            _otpSent = false;
          });
          _generateNewCaptcha();
        } else {
          _clearOtpBoxes();
          Future.delayed(const Duration(milliseconds: 80), () {
            if (mounted) _focusOtpBox(0);
          });
        }

        _setNotice(
          _extractMessage(
            data,
            fallback: shouldResetOtp
                ? 'OTP expired. Please request a new OTP.'
                : 'OTP verification failed.',
          ),
          NoticeType.error,
        );
        return;
      }

      final String token =
          (data['access_token'] ?? data['token'] ?? '').toString().trim();

      final Map<String, dynamic> userMap = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : <String, dynamic>{};

      final String role =
          (userMap['role'] ?? 'student').toString().trim().toLowerCase();

      if (token.isEmpty) {
        _setNotice('No token received from server.', NoticeType.error);
        return;
      }

      await _saveAuth(
        token: token,
        role: role.isEmpty ? 'student' : role,
        keepLoggedIn: _keepLoggedIn,
      );

      final userName = (userMap['name'] ?? 'User').toString();
      _setNotice('Login successful. Redirecting...', NoticeType.success);

      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _goToStructure(userName: userName);
        }
      });
    } on TimeoutException {
      _setNotice('Request timed out while verifying OTP.', NoticeType.error);
    } on SocketException catch (e, st) {
      debugPrint('Verify OTP socket error: $e');
      debugPrintStack(stackTrace: st);
      _setNotice(_humanizeNetworkError(e), NoticeType.error);
    } catch (e, st) {
      debugPrint('Verify OTP error: $e');
      debugPrintStack(stackTrace: st);
      _setNotice(_humanizeNetworkError(e), NoticeType.error);
    } finally {
      if (mounted) {
        setState(() {
          _verifyingOtp = false;
        });
      }
    }
  }

  void _triggerOtpAutoVerify() {
    _autoVerifyTimer?.cancel();
    if (!_canVerifyOtp) return;
    _autoVerifyTimer = Timer(const Duration(milliseconds: 160), _loginWithOtp);
  }

  Future<void> _launchGoogleSignIn() async {
    final uri = Uri.parse(
      '${AppConfig.baseUrl}$_googleRedirectPath?keep=${_keepLoggedIn ? 1 : 0}&source=app',
    );

    setState(() {
      _googleLoading = true;
    });
    _lastHandledCallbackUrl = null;

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _setNotice(
          'Could not open Google sign-in. Please try again.',
          NoticeType.error,
        );
        if (mounted) {
          setState(() {
            _googleLoading = false;
          });
        }
      }
    } catch (e) {
      _setNotice(
        'Could not open Google sign-in. Please try again.',
        NoticeType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _googleLoading = false;
        });
      }
    }
  }

  String _noticeTitle(NoticeType type) {
    switch (type) {
      case NoticeType.success:
        return 'Success';
      case NoticeType.error:
        return 'Authentication Failed';
      case NoticeType.warning:
        return 'Please Wait';
    }
  }

  String _captchaStatusText() {
    if (_currentEmail.isEmpty) return 'Enter your institute email first.';
    if (!_validEmail(_currentEmail)) return 'Enter a proper email format first.';
    if (!_hasAllowedDomain(_currentEmail)) {
      return 'Your gmail not allowed.';
    }
    if (_captchaSolved) return 'Captcha verified. You can send OTP now.';
    return 'Enter captcha to continue.';
  }

  String _captchaLockText() {
    if (_currentEmail.isEmpty) return 'Locked';
    if (!_validEmail(_currentEmail)) return 'Enter valid email first';
    if (!_hasAllowedDomain(_currentEmail)) return 'Email not allowed';
    return 'Click captcha to refresh';
  }

  String _otpStatusText() {
    if (_verifyingOtp) return 'Verifying OTP and logging you in...';
    if (_sendingOtp) return 'Sending OTP...';
    if (_otpSent) {
      return 'OTP sent successfully. Enter all 6 digits. Login will happen automatically.';
    }
    return 'After OTP is sent, enter the 6 digits. Login will happen automatically.';
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = AppColors.background(context);
    final surfaceColor = AppColors.surface(context);
    final surface3Color = AppColors.surface3(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    backgroundColor,
                    surface3Color,
                    surfaceColor,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -90,
            left: -50,
            child: _softGlow(
              color: AppColors.softFill(context),
              size: 220,
            ),
          ),
          Positioned(
            top: 170,
            right: -60,
            child: _softGlow(
              color: AppColors.dangerFill(context),
              size: 180,
            ),
          ),
          Positioned.fill(
            child: const IgnorePointer(
              child: _PremiumLoginBackdrop(),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _buildBrandBlock(),
                      const SizedBox(height: 24),
                      Text(
                        'Sign in',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.1,
                          height: 1.04,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Use your institute email to receive OTP and continue to your dashboard.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_notice != null) ...[
                        _buildInlineNotice(),
                        const SizedBox(height: 18),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Institute Email',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildInputField(
                        controller: _emailController,
                        hint: 'Enter your institute email',
                        icon: FontAwesomeIcons.envelope,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        hasError: _emailError != null,
                        onChanged: (_) => _handleEmailChanged(),
                        onFieldSubmitted: (_) {
                          if (_canSendOtp) {
                            _sendOtp();
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _emailError ?? _captchaStatusText(),
                          style: TextStyle(
                            color: _emailError != null
                                ? AppColors.dangerAccent(context)
                                : (_captchaSolved
                                      ? AppColors.success
                                      : textSecondary),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildCaptchaCard(),
                      const SizedBox(height: 12),
                      if (_otpSent) ...[
                        _buildOtpPanel(),
                        const SizedBox(height: 16),
                      ],
                      _buildKeepSignedInRow(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_checkingSavedSession) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildBrandBlock() {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final inkColor = AppColors.ink(context);
    final textSecondary = AppColors.textSecondary(context);
    return Column(
      children: [
        Container(
          width: 94,
          height: 94,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: inkColor.withOpacity(0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Image.asset(
            'assets/icons/logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'MSIT LMS',
          style: TextStyle(
            color: textSecondary.withOpacity(0.82),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildInlineNotice() {
    final InlineNotice notice = _notice!;

    late final Color fillColor;
    late final Color borderColor;
    late final Color accentColor;
    late final Color labelColor;

    switch (notice.type) {
      case NoticeType.success:
        fillColor = const Color(0xFFEAF7EF);
        borderColor = const Color(0xFFB7E2C3);
        accentColor = const Color(0xFF15803D);
        labelColor = const Color(0xFF166534);
        break;
      case NoticeType.warning:
        fillColor = const Color(0xFFFFF5E6);
        borderColor = const Color(0xFFF5D8A2);
        accentColor = const Color(0xFFB45309);
        labelColor = const Color(0xFF92400E);
        break;
      case NoticeType.error:
        fillColor = AppColors.dangerFill(context);
        borderColor = AppColors.dangerOutline(context);
        accentColor = AppColors.dangerAccent(context);
        labelColor = AppColors.dangerLabel(context);
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: accentColor,
                width: 1.4,
              ),
            ),
            child: Center(
              child: FaIcon(
                notice.type == NoticeType.success
                    ? FontAwesomeIcons.check
                    : notice.type == NoticeType.warning
                    ? FontAwesomeIcons.clock
                    : FontAwesomeIcons.exclamation,
                size: 14,
                color: accentColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _noticeTitle(notice.type),
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notice.message,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _clearNotice,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(
                Icons.close_rounded,
                size: 24,
                color: labelColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onFieldSubmitted,
    TextInputAction? textInputAction,
    TextInputType? keyboardType,
    Widget? suffix,
    bool obscureText = false,
    bool hasError = false,
  }) {
    final surfaceColor = AppColors.surface(context);
    final borderSoft = AppColors.borderSoft(context);
    final inkColor = AppColors.ink(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final Color borderColor = hasError
        ? AppColors.softBorder(context)
        : borderSoft;
    final Color iconColor =
        hasError ? AppColors.dangerAccent(context) : textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: inkColor.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        onChanged: onChanged,
        onSubmitted: onFieldSubmitted,
        textInputAction: textInputAction,
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: textSecondary.withOpacity(0.92),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: surfaceColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 19,
          ),
          prefixIcon: SizedBox(
            width: 54,
            child: Center(
              child: FaIcon(
                icon,
                size: 18,
                color: iconColor,
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 54,
            minHeight: 54,
          ),
          suffixIcon: suffix,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: borderColor,
              width: 1.1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: hasError
                  ? AppColors.softBorder(context)
                  : AppColors.primary,
              width: 1.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCaptchaCard() {
    final surfaceColor = AppColors.surface(context);
    final surface3Color = AppColors.surface3(context);
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final isLocked = !_canUnlockCaptcha;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: isLocked ? 0.72 : 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface3Color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const FaIcon(
                  FontAwesomeIcons.shieldHalved,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Captcha Verification',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    _captchaLockText(),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildCaptchaPreview(
              surfaceColor,
              borderColor,
              isLocked,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildCaptchaInput(
                    surfaceColor,
                    borderColor,
                    isLocked,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 112,
                  child: _buildOtpSendButton(),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              _captchaSolved
                  ? 'Captcha verified. You can send OTP now.'
                  : _canUnlockCaptcha
                  ? 'Type the captcha correctly to enable Send OTP.'
                  : 'Your gmail not allowed.',
              style: TextStyle(
                color: textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCaptchaPreview(
    Color surfaceColor,
    Color borderColor,
    bool isLocked,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: isLocked
            ? null
            : () {
                _generateNewCaptcha();
                FocusManager.instance.primaryFocus?.unfocus();
              },
        child: Ink(
          height: 50,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _CaptchaNoisePainter(
                      seed: _captchaText.hashCode,
                      color: AppColors.primary.withOpacity(0.14),
                    ),
                  ),
                ),
              ),
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _captchaText.split('').asMap().entries.map((entry) {
                    final index = entry.key;
                    final char = entry.value;
                    final angle = (index.isEven ? -1 : 1) * 0.11;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Transform.rotate(
                        angle: angle,
                        child: Text(
                          char,
                          style: TextStyle(
                            color: index.isEven
                                ? const Color(0xFF6B2528)
                                : AppColors.primary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCaptchaInput(
    Color surfaceColor,
    Color borderColor,
    bool isLocked,
  ) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return TextField(
      controller: _captchaController,
      enabled: !isLocked,
      textCapitalization: TextCapitalization.characters,
      onChanged: _validateCaptchaInput,
      onSubmitted: (_) {
        if (_canSendOtp) {
          _sendOtp();
        }
      },
      style: TextStyle(
        color: textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
      decoration: InputDecoration(
        hintText: 'Enter captcha',
        hintStyle: TextStyle(
          color: textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: borderColor),
        ),
      ),
    );
  }

  Widget _buildOtpSendButton() {
    String label = 'OTP';
    IconData icon = FontAwesomeIcons.paperPlane;

    if (_sendingOtp) {
      label = 'Sending';
      icon = FontAwesomeIcons.spinner;
    } else if (_resendSeconds > 0) {
      label = '${_resendSeconds}s';
      icon = FontAwesomeIcons.clock;
    } else if (_otpSent) {
      label = 'Resend';
      icon = FontAwesomeIcons.rotateRight;
    }

    return SizedBox(
      height: 50,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _canSendOtp ? _sendOtp : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_sendingOtp)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              FaIcon(icon, size: 13),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpPanel() {
    final borderColor = AppColors.borderSoft(context);
    final surface3Color = AppColors.surface3(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface3Color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.solidEnvelope,
                size: 14,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Enter OTP',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface(context),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  _verifyingOtp ? 'Verifying...' : 'Auto login on 6th digit',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int index = 0; index < _otpLength; index++) ...[
                Expanded(child: _buildOtpDigit(index)),
                if (index != _otpLength - 1)
                  SizedBox(width: index == 2 ? 14 : 10),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _otpStatusText(),
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed:
                    (_sendingOtp || _verifyingOtp || _resendSeconds > 0)
                    ? null
                    : _sendOtp,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accentText,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _resendSeconds > 0 ? 'Resend in ${_resendSeconds}s' : 'Resend OTP',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOtpDigit(int index) {
    final controller = _otpControllers[index];
    final focusNode = _otpFocusNodes[index];
    final filled = controller.text.trim().isNotEmpty;
    final textPrimary = AppColors.textPrimary(context);
    final borderColor = AppColors.borderSoft(context);
    final activeBorder = AppColors.primary.withOpacity(0.58);

    return AspectRatio(
      aspectRatio: 1,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: _otpSent && !_verifyingOtp,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: index == _otpLength - 1
            ? TextInputAction.done
            : TextInputAction.next,
        style: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: filled
              ? AppColors.surface(context)
              : AppColors.surface3(context),
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: filled ? activeBorder : borderColor,
              width: filled ? 1.8 : 1.4,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.primary,
              width: 2,
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: borderColor,
              width: 1.3,
            ),
          ),
        ),
        onChanged: (value) {
          var digit = value.replaceAll(RegExp(r'\D'), '');
          if (digit.length > 1) {
            digit = digit.substring(digit.length - 1);
          }
          if (controller.text != digit) {
            controller.value = TextEditingValue(
              text: digit,
              selection: TextSelection.collapsed(offset: digit.length),
            );
          }
          setState(() {});
          if (digit.isNotEmpty && index < _otpLength - 1) {
            _focusOtpBox(index + 1);
          }
          _triggerOtpAutoVerify();
        },
        onTap: () {
          if (_verifyingOtp) return;
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        },
      ),
    );
  }

  Widget _buildKeepSignedInRow() {
    final textSecondary = AppColors.textSecondary(context);
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _keepLoggedIn = !_keepLoggedIn;
                  });
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _keepLoggedIn ? AppColors.primaryGlow : surfaceColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _keepLoggedIn
                          ? AppColors.primaryGlow
                          : borderColor,
                    ),
                    boxShadow: _keepLoggedIn
                        ? [
                            BoxShadow(
                              color: AppColors.primaryGlow.withOpacity(0.24),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: _keepLoggedIn ? Colors.white : Colors.transparent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Keep me signed in',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 42,
          child: OutlinedButton.icon(
            onPressed:
                _checkingSavedSession || _googleLoading ? null : _launchGoogleSignIn,
            style: OutlinedButton.styleFrom(
              backgroundColor: surfaceColor,
              foregroundColor: AppColors.textPrimary(context),
              side: BorderSide(color: borderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const FaIcon(
              FontAwesomeIcons.google,
              size: 14,
              color: Color(0xFFDB4437),
            ),
            label: Text(
              _googleLoading ? 'Opening...' : 'Google',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    final surfaceColor = AppColors.surface(context);
    final inkColor = AppColors.ink(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Positioned.fill(
      child: Stack(
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 11, sigmaY: 11),
            child: Container(
              color: (AppColors.isDark(context)
                      ? AppColors.darkBackground
                      : AppColors.lightSurface2)
                  .withOpacity(0.55),
            ),
          ),
          Center(
            child: Container(
              width: 224,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: inkColor.withOpacity(0.10),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.softFill(context),
                      border: Border.all(
                        color: AppColors.softBorder(context),
                        width: 4,
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: const CircularProgressIndicator(
                      strokeWidth: 5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Checking your session...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Restoring your last session',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _softGlow({
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
              color,
              color.withOpacity(0.18),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptchaNoisePainter extends CustomPainter {
  final int seed;
  final Color color;

  const _CaptchaNoisePainter({
    required this.seed,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < 5; i++) {
      paint.color = color.withOpacity(i.isEven ? 1 : 0.7);
      final path = Path()
        ..moveTo(0, random.nextDouble() * size.height);
      path.cubicTo(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
        size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawPath(path, paint);
    }

    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 14; i++) {
      dotPaint.color = color.withOpacity(i.isEven ? 0.6 : 0.35);
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        1 + (random.nextDouble() * 1.4),
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CaptchaNoisePainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.color != color;
  }
}

class _PremiumLoginBackdrop extends StatefulWidget {
  const _PremiumLoginBackdrop();

  @override
  State<_PremiumLoginBackdrop> createState() => _PremiumLoginBackdropState();
}

class _PremiumLoginBackdropState extends State<_PremiumLoginBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _LoginBackdropPainter(
            progress: _controller.value,
            isDark: isDark,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _LoginBackdropPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  const _LoginBackdropPainter({
    required this.progress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * math.pi * 2;
    final fade = isDark ? 0.28 : 1.0;
    final fillFade = isDark ? 0.18 : 1.0;

    _drawOrbitalRing(
      canvas,
      center: Offset(size.width * 0.18, size.height * 0.18),
      radius: 42 + (math.sin(t) * 4),
      strokeColor: AppColors.primary.withOpacity(0.10 * fade),
      fillColor: AppColors.primarySoft.withOpacity(0.16 * fillFade),
    );

    _drawOrbitalRing(
      canvas,
      center: Offset(size.width * 0.84, size.height * 0.23),
      radius: 32 + (math.cos(t + 0.8) * 4),
      strokeColor: AppColors.info.withOpacity(0.10 * fade),
      fillColor: AppColors.lightSurface3.withOpacity(0.30 * fillFade),
    );

    _drawCapsule(
      canvas,
      center: Offset(size.width * 0.12, size.height * 0.56),
      width: 72,
      height: 24,
      angle: -0.55 + (math.sin(t + 0.7) * 0.05),
      color: AppColors.primary.withOpacity(0.08 * fade),
    );

    _drawCapsule(
      canvas,
      center: Offset(size.width * 0.88, size.height * 0.64),
      width: 68,
      height: 22,
      angle: 0.55 + (math.cos(t + 1.1) * 0.05),
      color: AppColors.accent.withOpacity(0.09 * fade),
    );

    _drawGlassCard(
      canvas,
      rect: Rect.fromCenter(
        center: Offset(
          size.width * 0.17 + (math.sin(t + 1.4) * 6),
          size.height * 0.74 + (math.cos(t + 1.4) * 8),
        ),
        width: 56,
        height: 56,
      ),
      color: AppColors.primarySoft.withOpacity(0.22 * fillFade),
      borderColor: AppColors.primary.withOpacity(0.09 * fade),
      radius: 18,
      angle: -0.18,
    );

    _drawGlassCard(
      canvas,
      rect: Rect.fromCenter(
        center: Offset(
          size.width * 0.84 + (math.cos(t + 2.0) * 7),
          size.height * 0.80 + (math.sin(t + 2.0) * 6),
        ),
        width: 48,
        height: 48,
      ),
      color: AppColors.lightSurface3.withOpacity(0.34 * fillFade),
      borderColor: AppColors.info.withOpacity(0.10 * fade),
      radius: 16,
      angle: 0.22,
    );

    _drawArcCluster(
      canvas,
      center: Offset(size.width * 0.82, size.height * 0.43),
      color: AppColors.primary.withOpacity(0.10 * fade),
      secondaryColor: AppColors.info.withOpacity(0.08 * fade),
      phase: t,
    );

    _drawArcCluster(
      canvas,
      center: Offset(size.width * 0.18, size.height * 0.36),
      color: AppColors.secondary.withOpacity(0.09 * fade),
      secondaryColor: AppColors.primarySoftBorder.withOpacity(0.20 * fillFade),
      phase: t + 1.8,
    );

    _drawDots(
      canvas,
      center: Offset(size.width * 0.73, size.height * 0.16),
      color: AppColors.primary.withOpacity(0.16 * fade),
      phase: t + 0.3,
    );
    _drawDots(
      canvas,
      center: Offset(size.width * 0.27, size.height * 0.86),
      color: AppColors.info.withOpacity(0.14 * fade),
      phase: t + 2.3,
    );
  }

  void _drawOrbitalRing(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color strokeColor,
    required Color fillColor,
  }) {
    final fillPaint = Paint()..color = fillColor;
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, strokePaint);
    canvas.drawCircle(
      center,
      radius * 0.48,
      strokePaint..strokeWidth = 1.0,
    );
  }

  void _drawCapsule(
    Canvas canvas, {
    required Offset center,
    required double width,
    required double height,
    required double angle,
    required Color color,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: width,
      height: height,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(height / 2));
    canvas.drawRRect(rrect, Paint()..color = color);
    canvas.restore();
  }

  void _drawGlassCard(
    Canvas canvas, {
    required Rect rect,
    required Color color,
    required Color borderColor,
    required double radius,
    required double angle,
  }) {
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(angle);
    final shiftedRect = Rect.fromCenter(
      center: Offset.zero,
      width: rect.width,
      height: rect.height,
    );
    final rrect = RRect.fromRectAndRadius(
      shiftedRect,
      Radius.circular(radius),
    );
    canvas.drawRRect(rrect, Paint()..color = color);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.restore();
  }

  void _drawArcCluster(
    Canvas canvas, {
    required Offset center,
    required Color color,
    required Color secondaryColor,
    required double phase,
  }) {
    final arc1 = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final arc2 = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 36 + (math.sin(phase) * 2)),
      0.3,
      1.9,
      false,
      arc1,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 22 + (math.cos(phase) * 1.5)),
      -2.4,
      1.6,
      false,
      arc2,
    );
  }

  void _drawDots(
    Canvas canvas, {
    required Offset center,
    required Color color,
    required double phase,
  }) {
    final paint = Paint()..color = color;
    for (int i = 0; i < 5; i++) {
      final angle = phase + (i * 1.2);
      final point = Offset(
        center.dx + (math.cos(angle) * (10 + i * 4)),
        center.dy + (math.sin(angle) * (8 + i * 3)),
      );
      canvas.drawCircle(point, i.isEven ? 2.1 : 1.4, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LoginBackdropPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
