import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/theme/app_colors.dart';
import '../../app/routes/app_routes.dart';
import '../../services/auth_service.dart';

/// Settings Content - dùng trong HomeScreen tab Cài đặt
class SettingsContent extends StatefulWidget {
  const SettingsContent({super.key});

  @override
  State<SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<SettingsContent> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        children: [
          // ====== TÀI KHOẢN ======
          _buildSectionHeader('Tài khoản'),
          ListTile(
            title: const Text('Thông tin cá nhân'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openProfilePage(context),
          ),
          const Divider(),

          // ====== THÔNG BÁO ======
          _buildSectionHeader('Thông báo'),
          ListTile(
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
            title: const Text('Phiên bản'),
            trailing: Text('1.0.0', style: TextStyle(color: Colors.grey[500])),
          ),
          ListTile(
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
