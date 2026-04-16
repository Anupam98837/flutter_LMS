import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hallienzlms/config/appConfig.dart';
import 'package:hallienzlms/screens/auth/login.dart';
import 'package:hallienzlms/theme/app_colors.dart';

class ProfilePageResult {
  final String? name;
  final String? imageUrl;
  final String? avatarText;

  const ProfilePageResult({
    this.name,
    this.imageUrl,
    this.avatarText,
  });
}

class ProfilePage extends StatefulWidget {
  final String initialName;
  final String? initialImageUrl;
  final String? initialAvatarText;

  const ProfilePage({
    super.key,
    required this.initialName,
    this.initialImageUrl,
    this.initialAvatarText,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _whatsAppController = TextEditingController();
  final _altEmailController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _addressController = TextEditingController();

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _loggingOut = false;
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  int _selectedTab = 0;
  bool _isEditingBasic = false;

  String _profileName = '';
  String _profileEmail = '';
  String _profileRole = 'Student';
  String _profileStatus = 'Active';
  String? _profileImageUrl;
  String? _avatarText;

  Map<String, dynamic>? _profileCache;

  @override
  void initState() {
    super.initState();
    _profileName = widget.initialName.trim().isEmpty
        ? 'Student'
        : widget.initialName.trim();
    _profileImageUrl = widget.initialImageUrl;
    _avatarText = widget.initialAvatarText;
    _loadProfile(showLoader: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _whatsAppController.dispose();
    _altEmailController.dispose();
    _altPhoneController.dispose();
    _addressController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<String> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token')?.trim() ?? '';
  }

  Future<void> _clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    await prefs.remove('keep_logged_in');
  }

  Future<Map<String, dynamic>> _sendRequest({
    required String method,
    required String endpoint,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final client = http.Client();
    try {
      final uri = Uri.parse(endpoint);
      late http.Response response;

      switch (method) {
        case 'POST':
          response = await client.post(uri, headers: headers, body: body);
          break;
        case 'PATCH':
          response = await client.patch(uri, headers: headers, body: body);
          break;
        default:
          response = await client.get(uri, headers: headers);
      }

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

  String _messageFromPayload(
    Map<String, dynamic> payload, {
    String fallback = 'Something went wrong.',
  }) {
    final message = payload['message']?.toString().trim();
    if (message != null && message.isNotEmpty) return message;

    final error = payload['error']?.toString().trim();
    if (error != null && error.isNotEmpty) return error;

    if (payload['errors'] is Map) {
      final errors = payload['errors'] as Map;
      for (final value in errors.values) {
        if (value is List && value.isNotEmpty) {
          return value.first.toString();
        }
        if (value != null) return value.toString();
      }
    }

    return fallback;
  }

  String _formatRole(String rawRole) {
    const roleMap = {
      'super_admin': 'Super Admin',
      'admin': 'Admin',
      'instructor': 'Instructor',
      'faculty': 'Faculty',
      'student': 'Student',
      'author': 'Author',
      'principal': 'Principal',
      'director': 'Director',
      'hod': 'Head of Department',
      'professor': 'Professor',
      'associate_professor': 'Associate Professor',
      'assistant_professor': 'Assistant Professor',
      'lecturer': 'Lecturer',
      'technical_staff': 'Technical Staff',
      'lab_assistant': 'Lab Assistant',
    };

    return roleMap[rawRole.toLowerCase()] ?? rawRole;
  }

  String? _normalizeProfileImageUrl(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return '${AppConfig.baseUrl}$raw';
    return '${AppConfig.baseUrl}/$raw';
  }

  void _applyProfile(Map<String, dynamic> user) {
    _profileCache = Map<String, dynamic>.from(user);
    _profileName =
        (user['name']?.toString().trim().isNotEmpty ?? false)
            ? user['name'].toString().trim()
            : _profileName;
    _profileEmail = user['email']?.toString().trim() ?? '';
    _profileRole = _formatRole(user['role']?.toString().trim() ?? 'Student');
    _profileStatus = user['status']?.toString().trim().isNotEmpty ?? false
        ? user['status'].toString().trim()
        : 'Active';
    _profileImageUrl = _normalizeProfileImageUrl(user['image']?.toString());
    _avatarText = user['avatar_text']?.toString();

    _nameController.text = user['name']?.toString() ?? '';
    _emailController.text = user['email']?.toString() ?? '';
    _phoneController.text = user['phone_number']?.toString() ?? '';
    _whatsAppController.text = user['whatsapp_number']?.toString() ?? '';
    _altEmailController.text = user['alternative_email']?.toString() ?? '';
    _altPhoneController.text =
        user['alternative_phone_number']?.toString() ?? '';
    _addressController.text = user['address']?.toString() ?? '';
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.dangerStrong : AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _loadProfile({required bool showLoader}) async {
    final token = await _readToken();
    if (token.isEmpty) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
      return;
    }

    if (showLoader) {
      setState(() {
        _loading = true;
      });
    } else {
      setState(() {
        _refreshing = true;
      });
    }

    try {
      final result = await _sendRequest(
        method: 'GET',
        endpoint: '${AppConfig.baseUrl}/api/profile',
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
      );

      final statusCode = result['statusCode'] as int;
      final payload = result['data'] as Map<String, dynamic>;

      if (statusCode == 401 || statusCode == 403) {
        await _clearAuth();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
        return;
      }

      if (statusCode < 200 || statusCode >= 300) {
        throw Exception(
          _messageFromPayload(payload, fallback: 'Failed to load profile.'),
        );
      }

      final user = payload['user'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(payload['user'] as Map<String, dynamic>)
          : payload['data'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(payload['data'] as Map<String, dynamic>)
              : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _applyProfile(user);
      });
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
      });
    }
  }

  void _resetBasicDetails() {
    if (_profileCache != null) {
      _applyProfile(_profileCache!);
      setState(() {});
    }
  }

  void _resetPasswordFields() {
    _currentPasswordController.clear();
    _newPasswordController.clear();
    _confirmPasswordController.clear();
    setState(() {});
  }

  Future<void> _saveBasicDetails() async {
    FocusScope.of(context).unfocus();

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final altEmail = _altEmailController.text.trim();

    if (name.isEmpty) {
      _showSnack('Name is required.', error: true);
      return;
    }
    if (email.isEmpty) {
      _showSnack('Email is required.', error: true);
      return;
    }
    if (altEmail.isNotEmpty && !altEmail.contains('@')) {
      _showSnack('Alternative email is invalid.', error: true);
      return;
    }

    final token = await _readToken();
    if (token.isEmpty) return;

    setState(() {
      _savingProfile = true;
    });

    try {
      final result = await _sendRequest(
        method: 'POST',
        endpoint: '${AppConfig.baseUrl}/api/profile',
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'email': email,
          'phone_number': _phoneController.text.trim(),
          'whatsapp_number': _whatsAppController.text.trim(),
          'alternative_email': altEmail,
          'alternative_phone_number': _altPhoneController.text.trim(),
          'address': _addressController.text.trim(),
        }),
      );

      final statusCode = result['statusCode'] as int;
      final payload = result['data'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        throw Exception(
          _messageFromPayload(payload, fallback: 'Failed to update profile.'),
        );
      }

      final user = payload['user'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(payload['user'] as Map<String, dynamic>)
          : payload['data'] is Map<String, dynamic>
              ? Map<String, dynamic>.from(payload['data'] as Map<String, dynamic>)
              : {
                  ...?_profileCache,
                  'name': name,
                  'email': email,
                  'phone_number': _phoneController.text.trim(),
                  'whatsapp_number': _whatsAppController.text.trim(),
                  'alternative_email': altEmail,
                  'alternative_phone_number': _altPhoneController.text.trim(),
                  'address': _addressController.text.trim(),
                };

      if (!mounted) return;
      setState(() {
        _applyProfile(user);
      });
      _showSnack(
        _messageFromPayload(payload, fallback: 'Profile updated successfully.'),
      );
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (!mounted) return;
      setState(() {
        _savingProfile = false;
      });
    }
  }

  Future<void> _updatePassword() async {
    FocusScope.of(context).unfocus();

    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.isEmpty) {
      _showSnack('Current password is required.', error: true);
      return;
    }
    if (newPassword.length < 8) {
      _showSnack('New password must be at least 8 characters.', error: true);
      return;
    }
    if (newPassword != confirmPassword) {
      _showSnack('Password confirmation does not match.', error: true);
      return;
    }

    final token = await _readToken();
    if (token.isEmpty) return;

    setState(() {
      _savingPassword = true;
    });

    try {
      final result = await _sendRequest(
        method: 'PATCH',
        endpoint: '${AppConfig.baseUrl}/api/profile/password',
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
          'new_password_confirmation': confirmPassword,
        }),
      );

      final statusCode = result['statusCode'] as int;
      final payload = result['data'] as Map<String, dynamic>;

      if (statusCode < 200 || statusCode >= 300) {
        throw Exception(
          _messageFromPayload(payload, fallback: 'Failed to update password.'),
        );
      }

      _resetPasswordFields();
      _showSnack(
        _messageFromPayload(payload, fallback: 'Password updated successfully.'),
      );
    } catch (error) {
      _showSnack(error.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (!mounted) return;
      setState(() {
        _savingPassword = false;
      });
    }
  }

  Future<void> _logout() async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text('Log Out'),
            content: const Text('You will be signed out of Hallienz LMS.'),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textPrimary(context),
                  minimumSize: const Size(88, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(104, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                child: const Text('Log Out'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    final token = await _readToken();

    setState(() {
      _loggingOut = true;
    });

    try {
      if (token.isNotEmpty) {
        await _sendRequest(
          method: 'POST',
          endpoint: '${AppConfig.baseUrl}/api/auth/logout',
          headers: {
            HttpHeaders.acceptHeader: 'application/json',
            HttpHeaders.authorizationHeader: 'Bearer $token',
          },
        );
      }
    } catch (_) {
      // Clear local session even if remote logout fails.
    } finally {
      await _clearAuth();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  int get _passwordStrength {
    final password = _newPasswordController.text;
    int score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[A-Za-z]').hasMatch(password)) score++;
    if (RegExp(r'[\d\W_]').hasMatch(password)) score++;
    return score;
  }

  Widget _buildAvatar() {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final inkColor = AppColors.ink(context);
    final fallback = (_avatarText?.trim().isNotEmpty ?? false)
        ? _avatarText!.trim().substring(0, 1).toUpperCase()
        : _profileName.trim().isNotEmpty
            ? _profileName.trim().substring(0, 1).toUpperCase()
            : 'S';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: inkColor.withOpacity(0.05),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: _profileImageUrl != null
                ? Image.network(
                    _profileImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildAvatarFallback(fallback),
                  )
                : _buildAvatarFallback(fallback),
          ),
        ),
        Positioned(
          right: -3,
          bottom: -3,
          child: GestureDetector(
            onTap: () {
              _showSnack('Profile image upload will be connected next.');
            },
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: inkColor.withOpacity(0.07),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 15,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarFallback(String text) {
    return Container(
      color: AppColors.softFill(context),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final isActive = _profileStatus.toLowerCase() == 'active';
    final surfaceColor = AppColors.surface(context);
    final inkColor = AppColors.ink(context);
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: inkColor.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileName,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _profileEmail.isEmpty ? 'No email available' : _profileEmail,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroPill(
                      text: _profileRole,
                      icon: Icons.verified_user_outlined,
                      color: AppColors.primary,
                      background: AppColors.primarySoft,
                    ),
                    _HeroPill(
                      text: isActive ? 'Active' : _profileStatus,
                      icon: isActive
                          ? Icons.check_circle_outline_rounded
                          : Icons.pause_circle_outline_rounded,
                      color: isActive
                          ? const Color(0xFF15803D)
                          : AppColors.warning,
                      background: isActive
                          ? const Color(0xFFEAF7EF)
                          : const Color(0xFFFFF5E6),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    final textPrimary = AppColors.textPrimary(context);
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).pop(
              ProfilePageResult(
                name: _profileName,
                imageUrl: _profileImageUrl,
                avatarText: _avatarText,
              ),
            );
          },
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Profile',
            style: TextStyle(
              color: textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _loggingOut ? null : _logout,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: _loggingOut
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.logout_rounded,
                    size: 20,
                    color: AppColors.primary,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    bool obscureText = false,
  }) {
    final textPrimary = AppColors.textPrimary(context);
    final surfaceColor = AppColors.surface(context);
    final borderColor = AppColors.borderSoft(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: surfaceColor,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 14,
              vertical: maxLines > 1 ? 14 : 13,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final muted = AppColors.dashboardMutedColor(context);
    final borderColor = AppColors.borderSoft(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? '—' : value,
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                if (!isLast)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: borderColor,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Details',
          actionLabel: _isEditingBasic ? 'Cancel' : 'Edit',
          onTap: () {
            setState(() {
              if (_isEditingBasic) {
                _resetBasicDetails();
              }
              _isEditingBasic = !_isEditingBasic;
            });
          },
        ),
        const SizedBox(height: 14),
        if (!_isEditingBasic) ...[
          _buildDetailRow(
            icon: Icons.person_outline_rounded,
            label: 'Full Name',
            value: _profileName,
          ),
          _buildDetailRow(
            icon: Icons.alternate_email_rounded,
            label: 'Email',
            value: _profileEmail,
          ),
          _buildDetailRow(
            icon: Icons.call_outlined,
            label: 'Phone',
            value: _phoneController.text.trim(),
          ),
          _buildDetailRow(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'WhatsApp',
            value: _whatsAppController.text.trim(),
          ),
          _buildDetailRow(
            icon: Icons.mark_email_read_outlined,
            label: 'Alternative Email',
            value: _altEmailController.text.trim(),
          ),
          _buildDetailRow(
            icon: Icons.contact_phone_outlined,
            label: 'Alternative Phone',
            value: _altPhoneController.text.trim(),
          ),
          _buildDetailRow(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: _addressController.text.trim(),
            isLast: true,
          ),
        ] else ...[
          _buildTextField(
            controller: _nameController,
            label: 'Full Name',
            hint: 'Your full name',
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _emailController,
            label: 'Email',
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _phoneController,
            label: 'Phone Number',
            hint: 'Primary phone',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _whatsAppController,
            label: 'WhatsApp Number',
            hint: 'WhatsApp number',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _altEmailController,
            label: 'Alternative Email',
            hint: 'Alternative email',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _altPhoneController,
            label: 'Alternative Phone',
            hint: 'Alternative phone',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 14),
          _buildTextField(
            controller: _addressController,
            label: 'Address',
            hint: 'Street, city, state, ZIP',
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _savingProfile
                  ? null
                  : () async {
                      await _saveBasicDetails();
                      if (!mounted) return;
                      if (!_savingProfile) {
                        setState(() {
                          _isEditingBasic = false;
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: _savingProfile
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save Changes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _passwordVisibilityButton({
    required bool visible,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: AppColors.textSecondary(context),
      ),
    );
  }

  Widget _buildStrengthBar() {
    return Row(
      children: List.generate(3, (index) {
        final isOn = index < _passwordStrength;
        Color color = AppColors.borderSoft(context);
        if (index == 0 && isOn) color = const Color(0xFFEF4444);
        if (index == 1 && isOn) color = const Color(0xFFF59E0B);
        if (index == 2 && isOn) color = const Color(0xFF22C55E);

        return Expanded(
          child: Container(
            height: 6,
            margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSecurityTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          title: 'Security',
          subtitle: 'Change your account password safely.',
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _currentPasswordController,
          label: 'Current Password',
          hint: 'Current password',
          obscureText: !_showCurrentPassword,
          suffixIcon: _passwordVisibilityButton(
            visible: _showCurrentPassword,
            onTap: () {
              setState(() {
                _showCurrentPassword = !_showCurrentPassword;
              });
            },
          ),
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _newPasswordController,
          label: 'New Password',
          hint: 'New password',
          obscureText: !_showNewPassword,
          suffixIcon: _passwordVisibilityButton(
            visible: _showNewPassword,
            onTap: () {
              setState(() {
                _showNewPassword = !_showNewPassword;
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        _buildStrengthBar(),
        const SizedBox(height: 8),
        Text(
          'Minimum 8 characters and should be different from current password.',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _buildTextField(
          controller: _confirmPasswordController,
          label: 'Confirm New Password',
          hint: 'Confirm new password',
          obscureText: !_showConfirmPassword,
          suffixIcon: _passwordVisibilityButton(
            visible: _showConfirmPassword,
            onTap: () {
              setState(() {
                _showConfirmPassword = !_showConfirmPassword;
              });
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _savingPassword ? null : _updatePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _savingPassword
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Update Password',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle({
    required String title,
    required String subtitle,
  }) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    final isCancel = actionLabel.toLowerCase() == 'cancel';
    final textPrimary = AppColors.textPrimary(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            backgroundColor: AppColors.softFill(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCancel ? Icons.close_rounded : Icons.edit_outlined,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedTabs() {
    final surface3Color = AppColors.surface3(context);
    final borderColor = AppColors.borderSoft(context);
    final textSecondary = AppColors.textSecondary(context);
    final surfaceColor = AppColors.surface(context);
    final inkColor = AppColors.ink(context);
    Widget tabItem({
      required int index,
      required String label,
    }) {
      final isSelected = _selectedTab == index;

      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_selectedTab == index) return;
            setState(() {
              _selectedTab = index;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? surfaceColor : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: inkColor.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected
                    ? AppColors.primary
                    : textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: surface3Color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          tabItem(index: 0, label: 'Basic Details'),
          const SizedBox(width: 6),
          tabItem(index: 1, label: 'Security'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final surfaceColor = AppColors.surface(context);
    final inkColor = AppColors.ink(context);
    return Column(
      children: [
        _buildTopBar(),
        const SizedBox(height: 18),
        _buildHeroCard(),
        const SizedBox(height: 16),
        _buildSegmentedTabs(),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Container(
            key: ValueKey<int>(_selectedTab),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: inkColor.withOpacity(0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: _selectedTab == 0 ? _buildBasicTab() : _buildSecurityTab(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(
          ProfilePageResult(
            name: _profileName,
            imageUrl: _profileImageUrl,
            avatarText: _avatarText,
          ),
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background(context),
        body: Stack(
          children: [
            Positioned(
              top: -60,
              left: -80,
              child: _GlowOrb(
                color: AppColors.softFill(context),
                size: 220,
              ),
            ),
            Positioned(
              top: 120,
              right: -80,
              child: _GlowOrb(
                color: AppColors.dashboardGlowEnd(context),
                size: 220,
              ),
            ),
            SafeArea(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: () => _loadProfile(showLoader: false),
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        child: _buildBody(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Color background;

  const _HeroPill({
    required this.text,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowOrb({
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(0.78),
              color.withOpacity(0.26),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
