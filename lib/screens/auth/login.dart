import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hallienzlms/config/appConfig.dart';
import 'package:hallienzlms/screens/structure.dart';
import 'package:hallienzlms/theme/app_colors.dart';

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

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _keepLoggedIn = false;
  bool _submitting = false;
  bool _checkingSavedSession = false;
  bool _showPassword = false;

  String? _identifierError;
  String? _passwordError;
  String? _successUserName;

  InlineNotice? _notice;

  @override
  void initState() {
    super.initState();
    _identifierController.text = widget.initialIdentifier?.trim() ?? '';
    _passwordController.text = widget.initialPassword ?? '';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoLoginFromSavedToken();
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
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

  bool _validateInputs() {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    String? identifierError;
    String? passwordError;

    if (identifier.isEmpty) {
      identifierError = 'Please enter your email address.';
    }

    if (password.isEmpty) {
      passwordError = 'Please enter your password.';
    } else if (password.length < 6) {
      passwordError = 'Password must be at least 6 characters.';
    }

    final String? firstError = identifierError ?? passwordError;

    setState(() {
      _identifierError = identifierError;
      _passwordError = passwordError;
      if (firstError != null) {
        _notice = InlineNotice(
          message: firstError,
          type: NoticeType.error,
        );
      }
    });

    return firstError == null;
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
                  'HallienzLMS/1.0 (Flutter iOS/Android)',
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
                  'HallienzLMS/1.0 (Flutter iOS/Android)',
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
      return 'Secure connection failed on iPhone. The SSL certificate for msitlms.tecnixs.com may need server-side fixing.';
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
        '${AppConfig.baseUrl}/api/auth/check',
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
            (userMap['role'] ?? savedRole ?? 'student')
                .toString()
                .trim()
                .toLowerCase();

        await _saveAuth(
          token: token,
          role: resolvedRole.isEmpty ? 'student' : resolvedRole,
          keepLoggedIn: true,
        );

        redirectUserName = (userMap['name'] ?? 'User').toString();
      } else {
        await _clearAuth();
        _setNotice(
          _extractMessage(
            data,
            fallback: 'Your session expired. Please log in again.',
          ),
          NoticeType.error,
        );
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

  Future<void> _submitLogin() async {
    FocusScope.of(context).unfocus();
    _clearNotice();

    if (!_validateInputs()) return;

    setState(() {
      _submitting = true;
      _successUserName = null;
    });

    String? redirectUserName;

    try {
      final result = await _postJson(
        '${AppConfig.baseUrl}/api/auth/login',
        {
          'email': _identifierController.text.trim(),
          'password': _passwordController.text,
          'remember': _keepLoggedIn,
        },
      );

      final int statusCode = result['statusCode'] as int;
      final Map<String, dynamic> data =
          result['data'] as Map<String, dynamic>;

      if (kDebugMode) {
        debugPrint('Login statusCode: $statusCode');
        debugPrint('Login response: $data');
      }

      if (statusCode == 422) {
        setState(() {
          _passwordError = 'invalid';
        });
        _setNotice(
          _extractMessage(
            data,
            fallback: 'Incorrect email or password. Please try again.',
          ),
          NoticeType.error,
        );
        return;
      }

      if (statusCode < 200 || statusCode >= 300) {
        setState(() {
          _passwordError = 'invalid';
        });
        _setNotice(
          _extractMessage(
            data,
            fallback: 'Unable to log in.',
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

      _passwordController.clear();
      redirectUserName = (userMap['name'] ?? 'User').toString();
    } on TimeoutException {
      _setNotice('Request timed out while logging in.', NoticeType.error);
    } on SocketException catch (e, st) {
      debugPrint('SocketException: $e');
      debugPrintStack(stackTrace: st);
      _setNotice(_humanizeNetworkError(e), NoticeType.error);
    } on HandshakeException catch (e, st) {
      debugPrint('HandshakeException: $e');
      debugPrintStack(stackTrace: st);
      _setNotice(_humanizeNetworkError(e), NoticeType.error);
    } on HttpException catch (e, st) {
      debugPrint('HttpException: $e');
      debugPrintStack(stackTrace: st);
      _setNotice(_humanizeNetworkError(e), NoticeType.error);
    } catch (e, st) {
      debugPrint('Login error: $e');
      debugPrintStack(stackTrace: st);
      _setNotice(_humanizeNetworkError(e), NoticeType.error);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }

    if (redirectUserName != null && mounted) {
      setState(() {
        _notice = null;
        _identifierError = null;
        _passwordError = null;
        _successUserName = redirectUserName;
      });
    }
  }

  void _continueAfterSuccess() {
    final userName = _successUserName;
    if (userName == null) return;

    setState(() {
      _successUserName = null;
    });

    _goToStructure(userName: userName);
  }

  String _noticeTitle(NoticeType type) {
    switch (type) {
      case NoticeType.success:
        return 'Success';
      case NoticeType.error:
        return 'Authentication Failed';
      case NoticeType.warning:
        return 'Action Required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isBlocking = _submitting || _checkingSavedSession;

    return Scaffold(
      backgroundColor: AppColors.lightBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.lightBackground,
                    AppColors.lightSurface3,
                    AppColors.lightSurface,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -90,
            left: -50,
            child: _softGlow(
              color: AppColors.primarySoft,
              size: 220,
            ),
          ),
          Positioned(
            top: 170,
            right: -60,
            child: _softGlow(
              color: AppColors.dangerSurface,
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
                      const SizedBox(height: 28),
                      Text(
                        'Welcome back',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.lightTextPrimary,
                          fontSize: 29,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.1,
                          height: 1.04,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Enter your credentials to access your\naccount.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.lightTextSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (_notice != null) ...[
                        _buildInlineNotice(),
                        const SizedBox(height: 18),
                      ],
                      _buildInputField(
                        controller: _identifierController,
                        hint: 'alex.m@example.com',
                        icon: FontAwesomeIcons.envelope,
                        onChanged: (_) {
                          if (_identifierError != null || _notice != null) {
                            setState(() {
                              _identifierError = null;
                            });
                            _clearNotice();
                          }
                        },
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        controller: _passwordController,
                        hint: '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                        icon: FontAwesomeIcons.lock,
                        obscureText: !_showPassword,
                        hasError: _passwordError != null,
                        onFieldSubmitted: (_) => _submitLogin(),
                        textInputAction: TextInputAction.done,
                        suffix: IconButton(
                          onPressed: () {
                            setState(() {
                              _showPassword = !_showPassword;
                            });
                          },
                          icon: FaIcon(
                            _showPassword
                                ? FontAwesomeIcons.eye
                                : FontAwesomeIcons.eyeSlash,
                            size: 20,
                            color: AppColors.lightTextSecondary,
                          ),
                        ),
                        onChanged: (_) {
                          if (_passwordError != null || _notice != null) {
                            setState(() {
                              _passwordError = null;
                            });
                            _clearNotice();
                          }
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
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
                                color: _keepLoggedIn
                                    ? AppColors.primaryGlow
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _keepLoggedIn
                                      ? AppColors.primaryGlow
                                      : AppColors.lightBorderSoft,
                                ),
                                boxShadow: _keepLoggedIn
                                    ? [
                                        BoxShadow(
                                          color: AppColors.primaryGlow
                                              .withOpacity(0.24),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: _keepLoggedIn
                                    ? Colors.white
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Keep me signed in',
                              style: TextStyle(
                                color: AppColors.lightTextSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: widget.onForgotPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.accentText,
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: isBlocking ? null : _submitLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                AppColors.primary.withOpacity(0.45),
                            elevation: 0,
                            shadowColor:
                                AppColors.primary.withOpacity(0.28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Sign In',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(
                                Icons.chevron_right_rounded,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),
                      RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                          children: [
                            TextSpan(
                              text: "Don't have an account? ",
                              style: TextStyle(
                                color: AppColors.lightTextSecondary,
                              ),
                            ),
                            TextSpan(
                              text: 'Create one',
                              style: TextStyle(
                                color: AppColors.accentText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isBlocking) _buildLoadingOverlay(),
          if (_successUserName != null) _buildSuccessOverlay(),
        ],
      ),
    );
  }

  Widget _buildBrandBlock() {
    return Column(
      children: [
        Container(
          width: 94,
          height: 94,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.lightBorderSoft),
            boxShadow: [
              BoxShadow(
                color: AppColors.lightInk.withOpacity(0.05),
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
          'Hallienz LMS',
          style: TextStyle(
            color: AppColors.lightTextSecondary.withOpacity(0.82),
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildInlineNotice() {
    final InlineNotice notice = _notice!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.dangerSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.dangerBorder,
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
                color: AppColors.dangerStrong,
                width: 1.4,
              ),
            ),
            child: const Center(
              child: FaIcon(
                FontAwesomeIcons.exclamation,
                size: 14,
                color: AppColors.dangerStrong,
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
                    style: const TextStyle(
                      color: AppColors.dangerStrong,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notice.message,
                    style: const TextStyle(
                      color: AppColors.dangerText,
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
            child: const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(
                Icons.close_rounded,
                size: 24,
                color: AppColors.dangerText,
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
    final Color borderColor = hasError
        ? AppColors.primarySoftBorder
        : AppColors.lightBorderSoft;
    final Color iconColor =
        hasError ? AppColors.dangerStrong : AppColors.lightTextSecondary;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.lightInk.withOpacity(0.05),
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
        style: const TextStyle(
          color: AppColors.lightTextPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: AppColors.lightTextSecondary.withOpacity(0.92),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: Colors.white,
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
              color: hasError ? AppColors.primarySoftBorder : AppColors.primary,
              width: 1.3,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.primarySoftBorder,
              width: 1.1,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(
              color: AppColors.primarySoftBorder,
              width: 1.3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 11, sigmaY: 11),
            child: Container(
              color: Colors.white.withOpacity(0.55),
            ),
          ),
          Center(
            child: Container(
              width: 224,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.lightInk.withOpacity(0.10),
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
                      color: AppColors.primarySoft,
                      border: Border.all(
                        color: AppColors.primarySoftBorder,
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
                  const Text(
                    'Signing you in...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.lightTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _checkingSavedSession
                        ? 'Restoring your last session'
                        : 'Verifying credentials',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.lightTextSecondary,
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

  Widget _buildSuccessOverlay() {
    return Positioned.fill(
      child: Stack(
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              color: Colors.white.withOpacity(0.60),
            ),
          ),
          Center(
            child: Container(
              width: 680,
              constraints: const BoxConstraints(maxWidth: 420),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGlow.withOpacity(0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.success,
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Signed in${_successUserName == null ? '' : ' — Welcome back.'}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.lightTextPrimary,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      height: 1.22,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your authentication was successful.\nRedirecting you to your dashboard.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.lightTextSecondary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _continueAfterSuccess,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _LoginBackdropPainter(progress: _controller.value),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _LoginBackdropPainter extends CustomPainter {
  final double progress;

  const _LoginBackdropPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress * math.pi * 2;

    _drawOrbitalRing(
      canvas,
      center: Offset(size.width * 0.18, size.height * 0.18),
      radius: 42 + (math.sin(t) * 4),
      strokeColor: AppColors.primary.withOpacity(0.10),
      fillColor: AppColors.primarySoft.withOpacity(0.16),
    );

    _drawOrbitalRing(
      canvas,
      center: Offset(size.width * 0.84, size.height * 0.23),
      radius: 32 + (math.cos(t + 0.8) * 4),
      strokeColor: AppColors.info.withOpacity(0.10),
      fillColor: AppColors.lightSurface3.withOpacity(0.30),
    );

    _drawCapsule(
      canvas,
      center: Offset(size.width * 0.12, size.height * 0.56),
      width: 72,
      height: 24,
      angle: -0.55 + (math.sin(t + 0.7) * 0.05),
      color: AppColors.primary.withOpacity(0.08),
    );

    _drawCapsule(
      canvas,
      center: Offset(size.width * 0.88, size.height * 0.64),
      width: 68,
      height: 22,
      angle: 0.55 + (math.cos(t + 1.1) * 0.05),
      color: AppColors.accent.withOpacity(0.09),
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
      color: AppColors.primarySoft.withOpacity(0.22),
      borderColor: AppColors.primary.withOpacity(0.09),
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
      color: AppColors.lightSurface3.withOpacity(0.34),
      borderColor: AppColors.info.withOpacity(0.10),
      radius: 16,
      angle: 0.22,
    );

    _drawArcCluster(
      canvas,
      center: Offset(size.width * 0.82, size.height * 0.43),
      color: AppColors.primary.withOpacity(0.10),
      secondaryColor: AppColors.info.withOpacity(0.08),
      phase: t,
    );

    _drawArcCluster(
      canvas,
      center: Offset(size.width * 0.18, size.height * 0.36),
      color: AppColors.secondary.withOpacity(0.09),
      secondaryColor: AppColors.primarySoftBorder.withOpacity(0.20),
      phase: t + 1.8,
    );

    _drawDots(
      canvas,
      center: Offset(size.width * 0.73, size.height * 0.16),
      color: AppColors.primary.withOpacity(0.16),
      phase: t + 0.3,
    );
    _drawDots(
      canvas,
      center: Offset(size.width * 0.27, size.height * 0.86),
      color: AppColors.info.withOpacity(0.14),
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
