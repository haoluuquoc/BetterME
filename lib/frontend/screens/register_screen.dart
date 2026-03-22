import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../../services/auth_service.dart';

/// Register Screen - Trang đăng ký tài khoản với watercolor blue theme
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  // Watercolor Blue theme colors (matching login screen)
  static const Color _bgDark = Color(0xFF0A1628);
  static const Color _bgCard = Color(0xFF112240);
  static const Color _bgCardLight = Color(0xFF1A3358);
  static const Color _accentBlue = Color(0xFF3A9BD5);
  static const Color _accentSky = Color(0xFF5BB5E8);
  static const Color _accentDeep = Color(0xFF2980B9);
  static const Color _textPrimary = Color(0xFFF1F5F9);
  static const Color _textSecondary = Color(0xFF94A3B8);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFF1E4976);
  static const Color _inputBg = Color(0xFF0E1F3A);

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
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

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await _authService.registerWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
      displayName: _nameController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đăng ký thành công!'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.pushReplacementNamed(context, Routes.home);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Đăng ký thất bại'),
          backgroundColor: AppColors.error,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Stack(
        children: [
          // Background glow effects
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
                      const SizedBox(height: 16),

                      // Back button
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: _textSecondary, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Logo & Title
                      _buildHeader(),

                      const SizedBox(height: 32),

                      // Register card
                      _buildRegisterCard(),

                      const SizedBox(height: 24),

                      // Register button
                      _buildRegisterButton(),

                      const SizedBox(height: 20),

                      // Login link
                      _buildLoginLink(),

                      const SizedBox(height: 24),

                      // Divider
                      _buildDivider(),

                      const SizedBox(height: 24),

                      // Google sign up
                      _buildGoogleButton(),

                      const SizedBox(height: 40),
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
        // Top-right blue glow
        Positioned(
          top: -60,
          right: -50,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 220 * _pulseAnimation.value,
                height: 220 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _accentBlue.withOpacity(0.2),
                      _accentBlue.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Bottom-left sky glow
        Positioned(
          bottom: -80,
          left: -60,
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                width: 260 * _pulseAnimation.value,
                height: 260 * _pulseAnimation.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _accentSky.withOpacity(0.12),
                      _accentSky.withOpacity(0.03),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Animated water drop icon
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _accentBlue.withOpacity(0.8 + 0.2 * _pulseAnimation.value),
                    _accentSky.withOpacity(0.6 + 0.2 * _pulseAnimation.value),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: _accentBlue.withOpacity(0.4 * _pulseAnimation.value),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.water_drop_rounded,
                size: 36,
                color: Colors.white,
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_accentBlue, _accentSky],
          ).createShader(bounds),
          child: const Text(
            'Tạo tài khoản',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Bắt đầu hành trình thay đổi bản thân',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterCard() {
    return Container(
      padding: const EdgeInsets.all(24),
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
            // Name field
            _buildTextField(
              controller: _nameController,
              label: 'Họ và tên',
              hint: 'Nguyễn Văn A',
              icon: Icons.person_outlined,
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Vui lòng nhập tên';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

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
                if (!value.contains('@') || !value.contains('.')) {
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
              hint: 'Ít nhất 6 ký tự',
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
            const SizedBox(height: 16),

            // Confirm password field
            _buildTextField(
              controller: _confirmPasswordController,
              label: 'Xác nhận mật khẩu',
              hint: 'Nhập lại mật khẩu',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureConfirmPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: _textMuted,
                  size: 20,
                ),
                onPressed: () {
                  setState(() =>
                      _obscureConfirmPassword = !_obscureConfirmPassword);
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng xác nhận mật khẩu';
                }
                if (value != _passwordController.text) {
                  return 'Mật khẩu không khớp';
                }
                return null;
              },
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
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
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
          child: Icon(icon, color: _accentBlue, size: 20),
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
          borderSide: const BorderSide(color: _accentBlue, width: 1.5),
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

  Widget _buildRegisterButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_accentBlue, _accentSky],
        ),
        boxShadow: [
          BoxShadow(
            color: _accentBlue.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _register,
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
                'Đăng ký',
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

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Đã có tài khoản? ',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 14,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Text(
            'Đăng nhập',
            style: TextStyle(
              color: _accentBlue,
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
          splashColor: _accentBlue.withOpacity(0.1),
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
                'Đăng ký với Google',
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
}
