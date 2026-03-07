import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/theme_provider.dart';
import '../../app/routes/app_routes.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';

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
  final _authService = AuthService();
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadBiometricState();
  }
  
  Future<void> _loadBiometricState() async {
    final available = await _authService.isBiometricAvailable();
    final enabled = await _authService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
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
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Đăng nhập bằng Face ID / Vân tay'),
              subtitle: Text(_biometricEnabled ? 'Đang bật' : 'Đang tắt'),
              value: _biometricEnabled,
              onChanged: (value) async {
                await _authService.setBiometricEnabled(value);
                setState(() => _biometricEnabled = value);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value
                          ? '✅ Đã bật đăng nhập sinh trắc học'
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
            trailing: Text('1.0.0', style: TextStyle(color: Colors.grey[500])),
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Nhà phát triển'),
            trailing: Text('BetterME Team', style: TextStyle(color: Colors.grey[500])),
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
            child: Text('BetterME v1.0.0',
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
    setState(() {
      _hoTen = prefs.getString('profile_name') ?? '';
      _namSinh = prefs.getString('profile_birth_year') ?? '';
      _gioiTinh = prefs.getString('profile_gender') ?? 'Nam';
      _soDienThoai = prefs.getString('profile_phone') ?? '';
      _chieuCao = prefs.getString('profile_height') ?? '';
      _canNang = prefs.getString('profile_weight') ?? '';
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
