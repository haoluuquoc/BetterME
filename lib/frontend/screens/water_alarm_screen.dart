import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../../app/routes/app_routes.dart';
import '../../services/auth_service.dart';

/// Màn hình báo thức uống nước - Full screen kiểu báo thức
class WaterAlarmScreen extends StatefulWidget {
  final bool isSnooze;
  
  const WaterAlarmScreen({super.key, this.isSnooze = false});

  @override
  State<WaterAlarmScreen> createState() => _WaterAlarmScreenState();
}

class _WaterAlarmScreenState extends State<WaterAlarmScreen> {
  static const _platform = MethodChannel('com.betterme.betterme/app');
  
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Clear tất cả flags để không hiện lại lần nữa
    NotificationService.pendingPayload = null;
    NotificationService().cancelNotification(0);
    _clearPendingFlag();
  }
  
  Future<void> _clearPendingFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pending_water_dialog', false);
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
              
              // Subtitle
              Text(
                widget.isSnooze ? 'Nhắc lại' : 'Nhắc nhở',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 12),
              
              // Tiêu đề chính
              const Text(
                'Đã đến giờ uống nước',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              
              const Spacer(flex: 3),
              
              // Nút "Để sau" - nút cam lớn
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _onSnooze,
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
              
              // Nút "Uống ngay"
              GestureDetector(
                onTap: _onDrinkNow,
                child: const Text(
                  'Uống ngay',
                  style: TextStyle(
                    color: Colors.white,
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
  
  /// Để sau: lên lịch snooze + đóng alarm screen
  void _onSnooze() async {
    // Block alarm cho đến khi có alarm mới (dùng SharedPreferences)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('block_alarm_screen', true);
    await prefs.setBool('pending_water_dialog', false);
    
    // Lên lịch snooze (Android: 20s, iOS: 60s vì iOS yêu cầu tối thiểu 60s)
    await NotificationService().scheduleSnooze();
    
    // Hiện notification với thời gian đúng theo platform
    final snoozeText = Platform.isIOS ? '1 phút' : '20 giây';
    await NotificationService().showSimpleNotification(
      title: 'Nhắc nhở uống nước',
      body: 'Sẽ nhắc lại sau $snoozeText',
      payload: 'water_reminder',
    );
    
    if (!kIsWeb && Platform.isAndroid) {
      // Android: đưa app về background để user thấy home/lock screen
      try {
        await _platform.invokeMethod('moveToBackground');
      } catch (e) {
        SystemNavigator.pop();
      }
    } else {
      // iOS: không thể moveToBackground, đóng alarm screen quay về app
      // Notification snooze đã được schedule, sẽ hiện lại sau 1 phút
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop('snooze');
        } else {
          // Từ cold launch → vào home
          try {
            final authService = AuthService();
            if (authService.isLoggedIn) {
              Navigator.pushReplacementNamed(context, Routes.home);
            } else {
              Navigator.pushReplacementNamed(context, Routes.login);
            }
          } catch (e) {
            Navigator.pushReplacementNamed(context, Routes.splash);
          }
        }
      }
    }
  }
  
  /// Uống ngay: hủy snooze + vào tab uống nước
  void _onDrinkNow() async {
    // Block alarm cho đến khi có alarm mới (dùng SharedPreferences)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('block_alarm_screen', true);
    await prefs.setBool('pending_water_dialog', false);
    
    NotificationService().cancelSnooze();
    NotificationService().cancelNotification(0);
    
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop('drink');
    } else {
      // Từ lock screen → vào app tab uống nước
      try {
        final authService = AuthService();
        if (authService.isLoggedIn) {
          Navigator.pushReplacementNamed(context, Routes.home);
        } else {
          Navigator.pushReplacementNamed(context, Routes.login);
        }
      } catch (e) {
        Navigator.pushReplacementNamed(context, Routes.splash);
      }
    }
  }
}
