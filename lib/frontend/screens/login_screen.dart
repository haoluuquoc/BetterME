import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

/// Login Screen - Giao diện đăng nhập premium với watercolor blue theme
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _savePassword = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String? _biometricLinkedEmail;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  // Watercolor Blue theme colors
  static const Color _bgDark = Color(0xFF0A1628);
  static const Color _bgCard = Color(0xFF112240);
  static const Color _bgCardLight = Color(0xFF1A3358);
  static const Color _accentPurple = Color(0xFF3A9BD5); // Ocean blue (primary accent)
  static const Color _accentPink = Color(0xFF5BB5E8);   // Sky blue (secondary accent)
  static const Color _accentBlue = Color(0xFF2980B9);   // Deep water blue
  static const Color _textPrimary = Color(0xFFF1F5F9);
  static const Color _textSecondary = Color(0xFF94A3B8);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFF1E4976);
  static const Color _inputBg = Color(0xFF0E1F3A);

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _checkBiometric();
    _initAnimations();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _checkBiometric() async {
    try {
      // Wrap entire biometric check with timeout to prevent UI hanging
      // when Firestore cloud fallback is slow
      await Future(() async {
        final available = await _authService.isBiometricAvailable();
        if (!available || !mounted) {
          if (mounted) setState(() => _biometricAvailable = false);
          return;
        }

        // Use local-only check first for speed; cloud fallback has its own timeout
        final enabled = await _authService.isBiometricEnabled();
        String? linkedEmail;
        if (enabled) {
          linkedEmail = await _authService.getBiometricLinkedEmail();
        }

        if (!mounted) return;
        setState(() {
          _biometricAvailable = available;
          _biometricEnabled = enabled;
          _biometricLinkedEmail = linkedEmail;
        });

        if (available && enabled) {
          final prefs = await SharedPreferences.getInstance();
          final justLoggedOut = prefs.getBool('just_logged_out') ?? false;
          if (!justLoggedOut) {
            _loginWithBiometric();
          }
          await prefs.remove('just_logged_out');
        }
      }).timeout(const Duration(seconds: 5));
    } catch (e) {
      // Timeout or error — just show login form normally
      debugPrint('Biometric check skipped: $e');
      if (mounted) {
        setState(() {
          _biometricAvailable = false;
          _biometricEnabled = false;
        });
      }
    }
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('save_password') ?? false;
    if (saved) {
      setState(() {
        _savePassword = true;
        _emailController.text = prefs.getString('saved_email') ?? '';
        _passwordController.text = prefs.getString('saved_password') ?? '';
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final result = await _authService.loginWithEmail(
      email: email,
      password: password,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result.isSuccess) {
      final prefs = await SharedPreferences.getInstance();
      if (_savePassword) {
        await prefs.setBool('save_password', true);
        await prefs.setString('saved_email', email);
        await prefs.setString('saved_password', password);
      } else {
        await prefs.setBool('save_password', false);
        await prefs.remove('saved_email');
        await prefs.remove('saved_password');
      }

      unawaited(
        _syncBiometricCredentialsAfterLogin(email: email, password: password),
      );
      Navigator.pushReplacementNamed(context, Routes.home);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Đăng nhập thất bại'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _syncBiometricCredentialsAfterLogin({
    required String email,
    required String password,
  }) async {
    try {
      final biometricEnabled = await _authService.isBiometricEnabled();
      if (!biometricEnabled) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('biometric_saved_email', email);
      await prefs.setString('biometric_saved_password', password);

      await FirestoreService()
          .saveBiometricCredentials(email: email, password: password)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      debugPrint('saveBiometricCredentials timed out');
    } catch (e) {
      debugPrint('saveBiometricCredentials error: $e');
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    final result = await _authService.signInWithGoogle();
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.pushReplacementNamed(context, Routes.home);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Đăng nhập thất bại'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _loginWithBiometric() async {
    setState(() => _isLoading = true);
    final result = await _authService.loginWithBiometric();
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.pushReplacementNamed(context, Routes.home);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Xác thực thất bại'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _forgotPassword() async {
    final emailController =
        TextEditingController(text: _emailController.text.trim());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Quên mật khẩu',
            style: TextStyle(color: _textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nhập email để nhận link đặt lại mật khẩu:',
                style: TextStyle(color: _textSecondary)),
            const SizedBox(height: 4),
            Text(
              '(Chỉ áp dụng cho tài khoản đăng ký bằng email và mật khẩu)',
              style: TextStyle(
                  fontSize: 12,
                  color: _textMuted,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: _textPrimary),
              decoration: InputDecoration(
                labelText: 'Email',
                labelStyle: const TextStyle(color: _textSecondary),
                prefixIcon:
                    const Icon(Icons.email_outlined, color: _accentPurple),
                filled: true,
                fillColor: _inputBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: _accentPurple, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                const Text('Hủy', style: TextStyle(color: _textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vui lòng nhập email'),
                    backgroundColor: AppColors.warning,
                  ),
                );
                return;
              }

              Navigator.pop(ctx);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đang gửi email...')),
              );

              final result =
                  await _authService.sendPasswordResetEmail(email);

              if (!mounted) return;

              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message ?? ''),
                  backgroundColor:
                      result.isSuccess ? AppColors.success : AppColors.error,
                  duration: const Duration(seconds: 4),
                ),
              );
            },
            child: const Text('Gửi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Stack(
        children: [
          // Background gradient effects
          _buildBackgroundEffects(),

          // Main content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 48),

                      // Logo & App name
                      _buildLogo(),

                      const SizedBox(height: 40),

                      // Login card
                      _buildLoginCard(),

                      const SizedBox(height: 24),

                      // Forgot password
                      Center(
                        child: TextButton(
                          onPressed: _forgotPassword,
                          child: const Text(
                            'Quên mật khẩu?',
                            style: TextStyle(
                              color: _accentPurple,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Sign In button
                      _buildSignInButton(),

                      const SizedBox(height: 16),

                      // Sign up link
                      _buildSignUpLink(),

                      const SizedBox(height: 16),

                      // Divider
                      _buildDivider(),

                      const SizedBox(height: 16),

                      // Google sign in
                      _buildGoogleButton(),

                      const SizedBox(height: 16),

                      // Biometric
                      if (_biometricAvailable) ...[
                        _buildBiometricSection(),
                        const SizedBox(height: 16),
                      ],

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundEffects() {
    return Stack(
      children: [
        // Top-right ocean blue glow
        Positioned(
          top: -80,
          right: -60,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 250 * _pulseAnimation.value,
                height: 250 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _accentPurple.withOpacity(0.25),
                      _accentPurple.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Bottom-left sky blue glow
        Positioned(
          bottom: -100,
          left: -80,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 300 * _pulseAnimation.value,
                height: 300 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _accentPink.withOpacity(0.15),
                      _accentPink.withOpacity(0.03),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Center-left deep blue glow
        Positioned(
          top: MediaQuery.of(context).size.height * 0.4,
          left: -40,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  _accentBlue.withOpacity(0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        // Animated icon container
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _accentPurple.withOpacity(0.8 + 0.2 * _pulseAnimation.value),
                    _accentPink.withOpacity(0.6 + 0.2 * _pulseAnimation.value),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accentPurple.withOpacity(0.4 * _pulseAnimation.value),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.water_drop_rounded,
                size: 40,
                color: Colors.white,
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_accentPurple, _accentPink],
          ).createShader(bounds),
          child: const Text(
            'BETTERME',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Chào mừng trở lại!',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 14,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgCard.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _borderColor.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Email field
            _buildTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'example@email.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng nhập email';
                }
                if (!value.contains('@')) {
                  return 'Email không hợp lệ';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password field
            _buildTextField(
              controller: _passwordController,
              label: 'Mật khẩu',
              hint: '••••••••',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _textMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng nhập mật khẩu';
                }
                if (value.length < 6) {
                  return 'Mật khẩu phải có ít nhất 6 ký tự';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Save password checkbox
            Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _savePassword,
                    onChanged: (v) => setState(() => _savePassword = v!),
                    activeColor: _accentPurple,
                    checkColor: Colors.white,
                    side: const BorderSide(color: _textMuted, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Lưu mật khẩu',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: _textPrimary, fontSize: 15),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: _textSecondary, fontSize: 14),
        hintStyle: TextStyle(color: _textMuted.withOpacity(0.6), fontSize: 14),
        prefixIcon: Container(
          margin: const EdgeInsets.only(left: 12, right: 8),
          child: Icon(icon, color: _accentPurple, size: 20),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 44),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: _inputBg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _borderColor.withOpacity(0.6), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accentPurple, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
    );
  }

  Widget _buildSignInButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_accentPurple, _accentPink],
        ),
        boxShadow: [
          BoxShadow(
            color: _accentPurple.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text(
                'Đăng nhập',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
      ),
    );
  }

  Widget _buildSignUpLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Chưa có tài khoản? ',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 14,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, Routes.register),
          child: const Text(
            'Đăng ký ngay',
            style: TextStyle(
              color: _accentPurple,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  _borderColor.withOpacity(0.6),
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'HOẶC',
            style: TextStyle(
              color: _textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _borderColor.withOpacity(0.6),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor, width: 1),
        color: _bgCardLight.withOpacity(0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _signInWithGoogle,
          borderRadius: BorderRadius.circular(16),
          splashColor: _accentPurple.withOpacity(0.1),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Google "G" icon
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    'G',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      foreground: Paint()
                        ..shader = const LinearGradient(
                          colors: [
                            Color(0xFF4285F4),
                            Color(0xFF34A853),
                            Color(0xFFFBBC05),
                            Color(0xFFEA4335),
                          ],
                        ).createShader(
                            const Rect.fromLTWH(0, 0, 16, 16)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Tiếp tục với Google',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBiometricSection() {
    return Column(
      children: [
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _isLoading ? null : _loginWithBiometric,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _biometricEnabled
                        ? [
                            _accentPurple.withOpacity(0.15),
                            _accentBlue.withOpacity(0.1),
                          ]
                        : [
                            _bgCardLight.withOpacity(0.5),
                            _bgCard.withOpacity(0.5),
                          ],
                  ),
                  border: Border.all(
                    color: _biometricEnabled
                        ? _accentPurple.withOpacity(
                            0.3 + 0.2 * _pulseAnimation.value)
                        : _borderColor.withOpacity(0.5),
                    width: _biometricEnabled ? 1.5 : 1,
                  ),
                  boxShadow: _biometricEnabled
                      ? [
                          BoxShadow(
                            color: _accentPurple.withOpacity(
                                0.15 * _pulseAnimation.value),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    // Face ID custom icon
                    _buildFaceIdIcon(),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFaceIdIcon() {
    final bool isEnabled = _biometricEnabled;
    final Color iconColor = isEnabled ? _accentPurple : _textMuted;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: isEnabled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _accentPurple.withOpacity(0.2),
                  _accentBlue.withOpacity(0.15),
                ],
              )
            : null,
        color: isEnabled ? null : _bgCardLight.withOpacity(0.8),
        border: Border.all(
          color: isEnabled
              ? _accentPurple.withOpacity(0.4)
              : _borderColor.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: CustomPaint(
        painter: _FaceIdPainter(
          color: iconColor,
          progress: isEnabled ? _pulseAnimation.value : 0.9,
        ),
      ),
    );
  }
}

/// Custom painter for a polished Face ID icon
class _FaceIdPainter extends CustomPainter {
  final Color color;
  final double progress;

  _FaceIdPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final margin = w * 0.2;
    final cornerLen = w * 0.18;

    // Top-left corner
    canvas.drawLine(
      Offset(margin, margin + cornerLen),
      Offset(margin, margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, margin),
      Offset(margin + cornerLen, margin),
      paint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(w - margin - cornerLen, margin),
      Offset(w - margin, margin),
      paint,
    );
    canvas.drawLine(
      Offset(w - margin, margin),
      Offset(w - margin, margin + cornerLen),
      paint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(margin, h - margin - cornerLen),
      Offset(margin, h - margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, h - margin),
      Offset(margin + cornerLen, h - margin),
      paint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(w - margin, h - margin - cornerLen),
      Offset(w - margin, h - margin),
      paint,
    );
    canvas.drawLine(
      Offset(w - margin - cornerLen, h - margin),
      Offset(w - margin, h - margin),
      paint,
    );

    // Face features
    final facePaint = Paint()
      ..color = color.withOpacity(0.7 + 0.3 * progress)
      ..style = PaintingStyle.fill;

    // Eyes
    final eyeY = h * 0.4;
    final eyeRadius = w * 0.04;
    canvas.drawCircle(Offset(w * 0.38, eyeY), eyeRadius, facePaint);
    canvas.drawCircle(Offset(w * 0.62, eyeY), eyeRadius, facePaint);

    // Nose (small vertical line)
    final nosePaint = Paint()
      ..color = color.withOpacity(0.5 + 0.3 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.5, h * 0.44),
      Offset(w * 0.5, h * 0.52),
      nosePaint,
    );

    // Smile
    final smilePaint = Paint()
      ..color = color.withOpacity(0.6 + 0.4 * progress)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final smilePath = Path();
    smilePath.moveTo(w * 0.36, h * 0.58);
    smilePath.quadraticBezierTo(w * 0.5, h * 0.66, w * 0.64, h * 0.58);
    canvas.drawPath(smilePath, smilePaint);
  }

  @override
  bool shouldRepaint(_FaceIdPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
