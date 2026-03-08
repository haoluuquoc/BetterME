import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../../services/auth_service.dart';
import '../../app/routes/app_routes.dart';

/// Màn hình nhắc cập nhật kiểu alarm (vàng đen) - hiện khi bấm "Để sau"
class UpdateAlarmScreen extends StatefulWidget {
  const UpdateAlarmScreen({super.key});

  @override
  State<UpdateAlarmScreen> createState() => _UpdateAlarmScreenState();
}

class _UpdateAlarmScreenState extends State<UpdateAlarmScreen> {
  String _newVersion = '';
  String _notes = '';
  String _downloadUrl = '';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadUpdateInfo();
    // Cancel notification
    NotificationService().cancelNotification(200);
  }

  Future<void> _loadUpdateInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _newVersion = prefs.getString('pending_update_version') ?? '';
        _notes = prefs.getString('pending_update_notes') ?? '';
        _downloadUrl = prefs.getString('pending_update_url') ?? '';
      });
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Icon
              const Icon(Icons.system_update, color: Colors.amber, size: 64),
              const SizedBox(height: 16),

              // Subtitle
              Text(
                'Nhắc nhở cập nhật',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 12),

              // Tiêu đề chính
              Text(
                'Phiên bản $_newVersion đã sẵn sàng',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              if (_notes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _notes,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const Spacer(flex: 3),

              // Nút "Để sau" - cam
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _onDismiss,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Để sau',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Nút "Cập nhật ngay"
              GestureDetector(
                onTap: _onUpdateNow,
                child: const Text(
                  'Cập nhật ngay',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  /// Để sau: đóng màn hình, quay lại app
  void _onDismiss() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pending_update_alarm', false);
    
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop('dismiss');
      } else {
        // Launched from notification → go to app
        final authService = AuthService();
        if (authService.isLoggedIn) {
          Navigator.pushReplacementNamed(context, Routes.home);
        } else {
          Navigator.pushReplacementNamed(context, Routes.login);
        }
      }
    }
  }

  /// Cập nhật ngay: mở Settings tab (nơi có chức năng download)
  void _onUpdateNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pending_update_alarm', false);
    
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop('update');
      } else {
        final authService = AuthService();
        if (authService.isLoggedIn) {
          Navigator.pushReplacementNamed(context, Routes.home);
        } else {
          Navigator.pushReplacementNamed(context, Routes.login);
        }
      }
    }
  }
}
