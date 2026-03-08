import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

/// Login Screen - Trang đăng nhập với Firebase Auth
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final available = await _authService.isBiometricAvailable();
    final enabled = await _authService.isBiometricEnabled();
    String? linkedEmail;
    if (available && enabled) {
      linkedEmail = await _authService.getBiometricLinkedEmail();
    }
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
        _biometricLinkedEmail = linkedEmail;
      });
      // Chỉ auto-login nếu KHÔNG phải vừa đăng xuất (cold start)
      if (available && enabled) {
        final prefs = await SharedPreferences.getInstance();
        final justLoggedOut = prefs.getBool('just_logged_out') ?? false;
        if (!justLoggedOut) {
          _loginWithBiometric();
        }
        // Xóa flag sau khi kiểm tra
        await prefs.remove('just_logged_out');
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
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await _authService.loginWithEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result.isSuccess) {
      final prefs = await SharedPreferences.getInstance();
      // Lưu mật khẩu nếu được chọn (chỉ để tự điền form lần sau)
      if (_savePassword) {
        await prefs.setBool('save_password', true);
        await prefs.setString('saved_email', _emailController.text.trim());
        await prefs.setString('saved_password', _passwordController.text);
      } else {
        await prefs.setBool('save_password', false);
        await prefs.remove('saved_email');
        await prefs.remove('saved_password');
      }
      
      // Luôn lưu credentials cho biometric nếu biometric đã bật (độc lập với lưu mật khẩu)
      final biometricEnabled = await _authService.isBiometricEnabled();
      if (biometricEnabled) {
        await prefs.setString('biometric_saved_email', _emailController.text.trim());
        await prefs.setString('biometric_saved_password', _passwordController.text);
        await FirestoreService().saveBiometricCredentials(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
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

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);
    final result = await _authService.signInWithApple();
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
    final emailController = TextEditingController(text: _emailController.text.trim());
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quên mật khẩu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nhập email để nhận link đặt lại mật khẩu:'),
            const SizedBox(height: 4),
            Text(
              '(Chỉ áp dụng cho tài khoản đăng ký bằng email và mật khẩu)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
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
              
              // Hiện loading
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đang gửi email...')),
              );
              
              final result = await _authService.sendPasswordResetEmail(email);
              
              if (!mounted) return;
              
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.message ?? ''),
                  backgroundColor: result.isSuccess ? AppColors.success : AppColors.error,
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),

              // Logo
              Icon(
                Icons.water_drop,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Chào mừng trở lại!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Đăng nhập để tiếp tục hành trình của bạn',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 48),

              // Login Form
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Email field
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'example@email.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
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
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu',
                        hintText: '••••••••',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
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

                    const SizedBox(height: 8),

                    // Lưu mật khẩu + Quên mật khẩu
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _savePassword,
                                onChanged: (v) => setState(() => _savePassword = v!),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Text('Lưu mật khẩu', style: TextStyle(fontSize: 13)),
                          ],
                        ),
                        TextButton(
                          onPressed: _forgotPassword,
                          child: const Text('Quên mật khẩu?'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Login button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Đăng nhập',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),


                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Divider
              Row(
                children: [
                  Expanded(child: Divider(color: AppColors.greyLight)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Hoặc đăng nhập với',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(child: Divider(color: AppColors.greyLight)),
                ],
              ),

              const SizedBox(height: 24),

              // Social login buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSocialButton(
                    icon: Icons.g_mobiledata,
                    label: 'Google',
                    onTap: _isLoading ? null : _signInWithGoogle,
                  ),
                  const SizedBox(width: 16),
                  _buildSocialButton(
                    icon: Icons.apple,
                    label: 'Apple',
                    onTap: _isLoading ? null : _signInWithApple,
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Biểu tượng sinh trắc học (nếu thiết bị hỗ trợ)
              if (_biometricAvailable) ...[
                const SizedBox(height: 8),
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _isLoading ? null : _loginWithBiometric,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(16),
                            border: _biometricEnabled 
                                ? Border.all(color: AppColors.primary.withOpacity(0.3), width: 1.5)
                                : null,
                          ),
                          child: Icon(
                            Icons.face_unlock_rounded,
                            size: 56,
                            color: _biometricEnabled ? AppColors.primary : Colors.grey[400],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _biometricEnabled 
                            ? 'Đăng nhập bằng Face ID / Vân tay'
                            : 'Face ID / Vân tay (chưa thiết lập)',
                        style: TextStyle(
                          fontSize: 12, 
                          color: _biometricEnabled ? Colors.grey[700] : Colors.grey[500],
                          fontWeight: _biometricEnabled ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                      if (_biometricLinkedEmail != null && _biometricEnabled) ...[
                        const SizedBox(height: 2),
                        Text(
                          _biometricLinkedEmail!,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (!_biometricEnabled) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Đăng nhập → Cài đặt → Bật Face ID',
                          style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Sign up link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Chưa có tài khoản? ',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pushNamed(context, Routes.register);
                    },
                    child: const Text('Đăng ký ngay'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 24),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }
}
