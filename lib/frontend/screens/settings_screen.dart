import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/theme_provider.dart';
import '../../app/routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/notification_service.dart';
import '../../services/health_service.dart';

/// Settings Content - dùng trong HomeScreen tab Cài đặt
class SettingsContent extends StatefulWidget {
  const SettingsContent({super.key});

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  String? _userEmail;
  String? _avatarPath;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String? _biometricLinkedEmail;
  final _authService = AuthService();
  
  // Version info (dynamic from package_info_plus)
  String _currentVersion = '1.0.0';
  int _currentBuildNumber = 1;
  
  // Update check state
  bool _hasNewVersion = false;
  String _newVersionString = '';
  String _newVersionNotes = '';
  String _newVersionUrl = '';
  String _newVersionCode = '';
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadBiometricState();
    _loadPackageInfo();
    _checkForNewVersionSilent();
  }
  
  Future<void> _loadBiometricState() async {
    final available = await _authService.isBiometricAvailable();
    final enabled = await _authService.isBiometricEnabled();
    String? linkedEmail;
    if (enabled) {
      linkedEmail = await _authService.getBiometricLinkedEmail();
    }
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
        _biometricLinkedEmail = linkedEmail;
      });
    }
  }
  
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _authService.currentUser;
    
    setState(() {
      _userEmail = user?.email ?? prefs.getString('user_email');
      _avatarPath = prefs.getString('user_avatar_path');
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        children: [
          // ====== AVATAR VÀ EMAIL ======
          _buildUserHeader(context),
          const Divider(),
          
          // ====== GIAO DIỆN ======
          _buildSectionHeader('Giao diện'),
          
          // Dark Mode Toggle
          SwitchListTile(
            title: const Text('Chế độ tối'),
            subtitle: Text(themeProvider.isDarkMode ? 'Đang bật' : 'Đang tắt'),
            value: themeProvider.isDarkMode,
            onChanged: (value) => themeProvider.toggleThemeMode(),
            secondary: Icon(
              themeProvider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          
          // Color Picker
          ListTile(
            leading: Icon(Icons.palette, color: Theme.of(context).colorScheme.primary),
            title: const Text('Màu chủ đạo'),
            subtitle: Text(themeProvider.currentColorTheme.name),
            trailing: _buildColorDot(themeProvider.currentColorTheme.primary, 24),
            onTap: () => _showColorPicker(context, themeProvider),
          ),
          const Divider(),

          // ====== TÀI KHOẢN ======
          _buildSectionHeader('Tài khoản'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Thông tin cá nhân'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openProfilePage(context),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Đổi mật khẩu'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              if (_authService.isEmailPasswordUser) {
                _showChangePasswordDialog(context);
              } else {
                final provider = _authService.currentProvider == 'google.com' ? 'Google' : 'Apple';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Tài khoản đăng nhập bằng $provider không thể đổi mật khẩu tại đây.\nVui lòng đổi mật khẩu trong tài khoản $provider của bạn.'),
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            },
          ),
          // Sinh trắc học (Face ID / Vân tay)
          if (_biometricAvailable)
            SwitchListTile(
              secondary: Icon(
                Icons.face_unlock_rounded,
                color: _biometricEnabled ? AppColors.primary : null,
              ),
              title: const Text('Đăng nhập bằng Face ID / Vân tay'),
              subtitle: Text(
                _biometricEnabled 
                    ? 'Đang bật${_biometricLinkedEmail != null ? ' • $_biometricLinkedEmail' : ''}'
                    : 'Đang tắt',
              ),
              value: _biometricEnabled,
              onChanged: (value) async {
                await _authService.setBiometricEnabled(value);
                String? email;
                if (value) {
                  email = await _authService.getBiometricLinkedEmail();
                }
                setState(() {
                  _biometricEnabled = value;
                  _biometricLinkedEmail = email;
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value
                          ? '✅ Đã bật đăng nhập sinh trắc học${email != null ? ' cho $email' : ''}'
                          : 'Đã tắt đăng nhập sinh trắc học'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          if (!_authService.isEmailPasswordUser)
            ListTile(
              leading: Icon(Icons.info_outline, color: Colors.grey[400]),
              title: Text(
                'Tài khoản đăng nhập bằng ${_authService.currentProvider == "google.com" ? "Google" : "Apple"}',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
          const Divider(),

          // ====== THÔNG BÁO ======
          _buildSectionHeader('Thông báo'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Cài đặt thông báo'),
            subtitle: const Text('Đang phát triển'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng đang phát triển')),
              );
            },
          ),
          const Divider(),

          // ====== VỀ ỨNG DỤNG ======
          _buildSectionHeader('Về ứng dụng'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Phiên bản'),
            trailing: Text(_currentVersion, style: TextStyle(color: Colors.grey[500])),
            onLongPress: () => _initUpdateConfig(context),
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Nhà phát triển'),
            trailing: Text('BetterME Team', style: TextStyle(color: Colors.grey[500])),
          ),
          if (!kIsWeb && Platform.isAndroid)
            ListTile(
              leading: Stack(
                children: [
                  const Icon(Icons.system_update),
                  if (_hasNewVersion)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                _hasNewVersion ? 'Có bản cập nhật mới!' : 'Cập nhật ứng dụng',
                style: _hasNewVersion 
                    ? const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)
                    : null,
              ),
              subtitle: Text(
                _hasNewVersion 
                    ? 'Phiên bản $_newVersionString đã sẵn sàng'
                    : 'Kiểm tra phiên bản mới',
              ),
              trailing: _hasNewVersion
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('MỚI', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: () {
                if (_hasNewVersion) {
                  // Đã biết có bản mới → đi thẳng dialog cập nhật
                  _showNewVersionDialog(context, _newVersionString, _newVersionNotes, _newVersionUrl, _newVersionCode);
                } else {
                  _showUpdateOptions(context);
                }
              },
            ),
          const Divider(),

          // ====== ĐĂNG XUẤT ======
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () => _showLogoutDialog(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Đăng xuất'),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text('BetterME v$_currentVersion',
              style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
  
  /// Header với avatar và email
  Widget _buildUserHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Avatar
          GestureDetector(
            onTap: () => _showAvatarOptions(context),
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  backgroundImage: _avatarPath != null && !kIsWeb
                      ? FileImage(File(_avatarPath!))
                      : null,
                  child: _avatarPath == null
                      ? Icon(
                          Icons.person,
                          size: 40,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Email và tên
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xin chào!',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _userEmail ?? 'Chưa đăng nhập',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// Hiện options chọn avatar
  void _showAvatarOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chọn từ thư viện'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Chụp ảnh'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_avatarPath != null) 
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text('Xóa ảnh', style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _pickImage(ImageSource source) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tính năng này chưa hỗ trợ trên web')),
      );
      return;
    }
    
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      
      if (pickedFile != null) {
        // Lưu ảnh vào app directory
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedImage = await File(pickedFile.path).copy('${appDir.path}/$fileName');
        
        // Xóa ảnh cũ nếu có
        if (_avatarPath != null) {
          try {
            await File(_avatarPath!).delete();
          } catch (_) {}
        }
        
        // Lưu path vào SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_avatar_path', savedImage.path);
        
        setState(() {
          _avatarPath = savedImage.path;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật ảnh đại diện')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    }
  }
  
  Future<void> _removeAvatar() async {
    if (_avatarPath != null) {
      try {
        await File(_avatarPath!).delete();
      } catch (_) {}
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_avatar_path');
    
    setState(() {
      _avatarPath = null;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã xóa ảnh đại diện')),
    );
  }
  
  /// Hiện color picker với các chấm màu
  void _showColorPicker(BuildContext context, ThemeProvider themeProvider) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chọn màu chủ đạo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              // Các chấm màu giống như hình
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: availableColorThemes.map((colorTheme) {
                  final isSelected = themeProvider.currentColorTheme.id == colorTheme.id;
                  return GestureDetector(
                    onTap: () {
                      themeProvider.setColorTheme(colorTheme);
                      Navigator.pop(ctx);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? colorTheme.primary : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: _buildColorDot(colorTheme.primary, isSelected ? 32 : 28),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Tạo chấm màu tròn
  Widget _buildColorDot(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
  
  /// Dialog đổi mật khẩu
  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool isLoading = false;
    bool showCurrentPassword = false;
    bool showNewPassword = false;
    bool showConfirmPassword = false;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('Đổi mật khẩu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPasswordCtrl,
                  obscureText: !showCurrentPassword,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu hiện tại',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(showCurrentPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDState(() => showCurrentPassword = !showCurrentPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPasswordCtrl,
                  obscureText: !showNewPassword,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu mới',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(showNewPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDState(() => showNewPassword = !showNewPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordCtrl,
                  obscureText: !showConfirmPassword,
                  decoration: InputDecoration(
                    labelText: 'Xác nhận mật khẩu mới',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(showConfirmPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setDState(() => showConfirmPassword = !showConfirmPassword),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                // Validate
                if (newPasswordCtrl.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mật khẩu mới phải có ít nhất 6 ký tự')),
                  );
                  return;
                }
                if (newPasswordCtrl.text != confirmPasswordCtrl.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mật khẩu xác nhận không khớp')),
                  );
                  return;
                }
                
                setDState(() => isLoading = true);
                
                try {
                  final authService = AuthService();
                  await authService.changePassword(
                    currentPasswordCtrl.text,
                    newPasswordCtrl.text,
                  );
                  
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đổi mật khẩu thành công!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } catch (e) {
                  setDState(() => isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Lỗi: ${e.toString()}'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Đổi mật khẩu'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _openProfilePage(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const ProfilePage(),
    ));
  }

  // ====== DEVELOPER: INIT UPDATE CONFIG ======

  void _initUpdateConfig(BuildContext context) async {
    // Kiểm tra document đã tồn tại chưa
    final existing = await FirestoreService().checkForUpdate();
    if (existing != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ app_config/latest_update đã tồn tại (v${existing['version']}). Không ghi đè.'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Developer: Init Update'),
        content: Text('Tạo document app_config/latest_update trên Firestore?\n\nPhiên bản: $_currentVersion+$_currentBuildNumber\n\nĐây là chức năng nhà phát triển.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tạo')),
        ],
      ),
    );
    if (confirm != true) return;

    await FirestoreService().initUpdateConfig(
      version: _currentVersion,
      buildNumber: _currentBuildNumber,
      downloadUrl: '',
      notes: 'Phiên bản $_currentVersion',
      code: '',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Đã tạo app_config/latest_update trên Firestore')),
      );
    }
  }

  // ====== OTA UPDATE ======

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _currentVersion = info.version;
          _currentBuildNumber = int.tryParse(info.buildNumber) ?? 1;
        });
      }
    } catch (e) {
      debugPrint('PackageInfo error: $e');
    }
  }
  
  /// Kiểm tra bản mới âm thầm khi vào Settings
  void _checkForNewVersionSilent() async {
    if (kIsWeb || !Platform.isAndroid) return;
    
    try {
      final updateInfo = await FirestoreService().checkForUpdate();
      if (updateInfo == null || !mounted) return;
      
      final serverBuild = updateInfo['buildNumber'] as int? ?? 0;
      final serverVersion = updateInfo['version'] as String? ?? '';
      final downloadUrl = updateInfo['downloadUrl'] as String? ?? '';
      final notes = updateInfo['notes'] as String? ?? '';
      final code = updateInfo['code'] as String? ?? '';
      
      if (serverBuild > _currentBuildNumber) {
        setState(() {
          _hasNewVersion = true;
          _newVersionString = serverVersion;
          _newVersionNotes = notes;
          _newVersionUrl = downloadUrl;
          _newVersionCode = code;
        });
      }
    } catch (e) {
      debugPrint('Silent update check error: $e');
    }
  }

  void _showUpdateOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Cập nhật ứng dụng',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('Phiên bản hiện tại: $_currentVersion',
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.cloud_download, color: Colors.blue),
              title: const Text('Kiểm tra tự động'),
              subtitle: const Text('Kiểm tra phiên bản mới trên server'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.blue.withOpacity(0.05),
              onTap: () {
                Navigator.pop(ctx);
                _checkFirestoreUpdate(context);
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.orange),
              title: const Text('Nhập link tải'),
              subtitle: const Text('Dán link APK để tải và cài đặt'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              tileColor: Colors.orange.withOpacity(0.05),
              onTap: () {
                Navigator.pop(ctx);
                _showDirectUrlDialog(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _checkFirestoreUpdate(BuildContext context) async {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Đang kiểm tra...'),
          ],
        ),
      ),
    );

    final updateInfo = await FirestoreService().checkForUpdate();

    if (!mounted) return;
    Navigator.pop(context);

    if (updateInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể kiểm tra. Chưa có thông tin cập nhật trên server.')),
      );
      return;
    }

    final serverBuild = updateInfo['buildNumber'] as int? ?? 0;
    final serverVersion = updateInfo['version'] as String? ?? '';
    final downloadUrl = updateInfo['downloadUrl'] as String? ?? '';
    final notes = updateInfo['notes'] as String? ?? '';
    final requiredCode = updateInfo['code'] as String? ?? '';

    if (serverBuild <= _currentBuildNumber) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đang dùng phiên bản mới nhất ($_currentVersion)')),
      );
      return;
    }

    if (downloadUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có link tải. Vui lòng thử lại sau.')),
      );
      return;
    }

    if (!mounted) return;
    _showNewVersionDialog(context, serverVersion, notes, downloadUrl, requiredCode);
  }

  void _showDirectUrlDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('update_apk_url') ?? '';
    final urlController = TextEditingController(text: savedUrl);

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhập link APK'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dán link file APK vào đây:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'http://192.168.x.x:8888/betterme.apk',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            Text(
              'Link từ Google Drive, máy tính cùng Wi-Fi, hoặc bất kỳ URL nào',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Tải & Cài đặt'),
            onPressed: () {
              final url = urlController.text.trim();
              Navigator.pop(ctx);
              if (url.isNotEmpty) {
                prefs.setString('update_apk_url', url);
                _downloadAndInstallApk(context, url);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showNewVersionDialog(
    BuildContext context,
    String newVersion,
    String notes,
    String downloadUrl,
    String requiredCode,
  ) {
    final codeController = TextEditingController();
    final needCode = requiredCode.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.system_update, color: Colors.blue),
                const SizedBox(width: 8),
                Text('Phiên bản $newVersion'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đang dùng: $_currentVersion',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('Nội dung cập nhật:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(notes, style: const TextStyle(fontSize: 13)),
                    ),
                  ],
                  if (needCode) ...[
                    const SizedBox(height: 16),
                    const Text('Nhập mã cập nhật:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    const Text('(Mã được gửi qua email hoặc nhóm chat)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Nhập mã...',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontSize: 16, letterSpacing: 2, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  // Lên lịch nhắc nhở cập nhật sau 20 giây (màn hình vàng đen)
                  NotificationService().scheduleUpdateAlarm(
                    version: newVersion,
                    notes: notes,
                    downloadUrl: downloadUrl,
                  );
                },
                child: const Text('Để sau'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Cập nhật ngay'),
                onPressed: () {
                  if (needCode) {
                    final entered = codeController.text.trim().toUpperCase();
                    if (entered != requiredCode.toUpperCase()) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('❌ Mã không đúng. Vui lòng kiểm tra lại.')),
                      );
                      return;
                    }
                  }
                  Navigator.pop(ctx);
                  if (downloadUrl.isNotEmpty) {
                    _downloadAndInstallApk(context, downloadUrl);
                  } else {
                    // Chưa có link → mở dialog nhập link thủ công
                    _showDirectUrlDialog(context);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _downloadAndInstallApk(BuildContext context, String url) async {
    // Validate URL
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.host.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL không hợp lệ')),
        );
      }
      return;
    }

    // Show progress dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text('Đang tải APK...\n${uri.host}')),
            ],
          ),
        ),
      ),
    );

    try {
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        httpClient.close();
        if (mounted) {
          Navigator.pop(context); // close progress dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi tải: HTTP ${response.statusCode}')),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/betterme_update.apk');
      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.close();
      httpClient.close();

      if (mounted) {
        Navigator.pop(context); // close progress dialog
      }

      // Install APK
      final installed = await NotificationService().installApk(file.path);
      if (!installed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở file cài đặt. Kiểm tra quyền.')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService().signOut();
              Navigator.pushNamedAndRemoveUntil(context, Routes.login, (r) => false);
            },
            child: const Text('Đăng xuất', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

/// Trang thông tin cá nhân - mở khi bấm Tài khoản
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String _hoTen = '';
  String _namSinh = '';
  String _gioiTinh = 'Nam';
  String _soDienThoai = '';
  String _chieuCao = '';
  String _canNang = '';
  String _noiSong = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    // Load local trước cho nhanh
    final prefs = await SharedPreferences.getInstance();
    final hs = HealthService();
    
    String chieuCao = prefs.getString('profile_height') ?? '';
    String canNang = prefs.getString('profile_weight') ?? '';
    
    // Đồng bộ từ HealthService nếu profile_height/profile_weight trống
    if (chieuCao.isEmpty) {
      final h = await hs.getHeight();
      if (h != null) chieuCao = h.toStringAsFixed(0);
    }
    if (canNang.isEmpty) {
      final w = await hs.getLatestWeight();
      if (w != null) canNang = w.toStringAsFixed(1);
    }
    
    setState(() {
      _hoTen = prefs.getString('profile_name') ?? '';
      _namSinh = prefs.getString('profile_birth_year') ?? '';
      _gioiTinh = prefs.getString('profile_gender') ?? 'Nam';
      _soDienThoai = prefs.getString('profile_phone') ?? '';
      _chieuCao = chieuCao;
      _canNang = canNang;
      _noiSong = prefs.getString('profile_location') ?? '';
    });
    
    // Sync từ Firestore nếu local trống
    if (_hoTen.isEmpty) {
      final cloud = await FirestoreService().loadProfile();
      if (cloud != null && mounted) {
        setState(() {
          _hoTen = cloud['name'] as String? ?? '';
          _namSinh = cloud['birthYear'] as String? ?? '';
          _gioiTinh = cloud['gender'] as String? ?? 'Nam';
          _soDienThoai = cloud['phone'] as String? ?? '';
          _chieuCao = cloud['height'] as String? ?? '';
          _canNang = cloud['weight'] as String? ?? '';
          _noiSong = cloud['location'] as String? ?? '';
        });
        // Lưu local
        await prefs.setString('profile_name', _hoTen);
        await prefs.setString('profile_birth_year', _namSinh);
        await prefs.setString('profile_gender', _gioiTinh);
        await prefs.setString('profile_phone', _soDienThoai);
        await prefs.setString('profile_height', _chieuCao);
        await prefs.setString('profile_weight', _canNang);
        await prefs.setString('profile_location', _noiSong);
        // Đồng bộ sang HealthService
        final hVal = double.tryParse(_chieuCao);
        final wVal = double.tryParse(_canNang);
        if (hVal != null && hVal > 0) await hs.saveHeight(hVal);
        if (wVal != null && wVal > 0) await hs.saveWeight(wVal);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông tin cá nhân'),
        actions: [
          IconButton(
            onPressed: _showEditDialog,
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: ListView(
        children: [
          _infoTile('Họ tên', _hoTen),
          _infoTile('Năm sinh', _namSinh),
          _infoTile('Giới tính', _gioiTinh),
          _infoTile('Số điện thoại', _soDienThoai),
          _infoTile('Chiều cao', _chieuCao.isEmpty ? '' : '$_chieuCao cm'),
          _infoTile('Cân nặng', _canNang.isEmpty ? '' : '$_canNang kg'),
          _infoTile('Nơi sinh sống', _noiSong),
        ],
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return ListTile(
      title: Text(label),
      trailing: Text(
        value.isEmpty ? 'Chưa cập nhật' : value,
        style: TextStyle(color: value.isEmpty ? Colors.grey : null),
      ),
    );
  }

  void _showEditDialog() {
    final hoTenCtrl = TextEditingController(text: _hoTen);
    final namSinhCtrl = TextEditingController(text: _namSinh);
    final sdtCtrl = TextEditingController(text: _soDienThoai);
    final chieuCaoCtrl = TextEditingController(text: _chieuCao);
    final canNangCtrl = TextEditingController(text: _canNang);
    final noiSongCtrl = TextEditingController(text: _noiSong);
    String gioiTinh = _gioiTinh;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('Chỉnh sửa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: hoTenCtrl, decoration: const InputDecoration(labelText: 'Họ tên', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: namSinhCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Năm sinh', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: gioiTinh,
                  decoration: const InputDecoration(labelText: 'Giới tính', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Nam', child: Text('Nam')),
                    DropdownMenuItem(value: 'Nữ', child: Text('Nữ')),
                    DropdownMenuItem(value: 'Khác', child: Text('Khác')),
                  ],
                  onChanged: (v) => setDState(() => gioiTinh = v!),
                ),
                const SizedBox(height: 10),
                TextField(controller: sdtCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: chieuCaoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Chiều cao (cm)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: canNangCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cân nặng (kg)', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: noiSongCtrl, decoration: const InputDecoration(labelText: 'Nơi sinh sống', border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('profile_name', hoTenCtrl.text);
                await prefs.setString('profile_birth_year', namSinhCtrl.text);
                await prefs.setString('profile_gender', gioiTinh);
                await prefs.setString('profile_phone', sdtCtrl.text);
                await prefs.setString('profile_height', chieuCaoCtrl.text);
                await prefs.setString('profile_weight', canNangCtrl.text);
                await prefs.setString('profile_location', noiSongCtrl.text);
                
                // Đồng bộ chiều cao và cân nặng sang HealthService
                final hs = HealthService();
                final hVal = double.tryParse(chieuCaoCtrl.text);
                final wVal = double.tryParse(canNangCtrl.text);
                if (hVal != null && hVal > 0) await hs.saveHeight(hVal);
                if (wVal != null && wVal > 0) await hs.saveWeight(wVal);
                
                // Đồng bộ lên Firestore
                FirestoreService().saveProfile({
                  'name': hoTenCtrl.text,
                  'birthYear': namSinhCtrl.text,
                  'gender': gioiTinh,
                  'phone': sdtCtrl.text,
                  'height': chieuCaoCtrl.text,
                  'weight': canNangCtrl.text,
                  'location': noiSongCtrl.text,
                });
                setState(() {
                  _hoTen = hoTenCtrl.text;
                  _namSinh = namSinhCtrl.text;
                  _gioiTinh = gioiTinh;
                  _soDienThoai = sdtCtrl.text;
                  _chieuCao = chieuCaoCtrl.text;
                  _canNang = canNangCtrl.text;
                  _noiSong = noiSongCtrl.text;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã lưu thông tin')),
                );
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}
