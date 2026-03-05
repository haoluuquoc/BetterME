import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app/app.dart';
import 'services/notification_service.dart';

/// Kiểm tra Firebase đã được cấu hình cho platform hiện tại chưa
bool get _isFirebaseConfigured {
  if (kIsWeb) return false; // Web chưa config
  if (defaultTargetPlatform == TargetPlatform.android) return true;
  if (defaultTargetPlatform == TargetPlatform.iOS) return true; // iOS đã config Firebase
  return false;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  bool isAlarmLaunch = false;
  bool isSnoozeLaunch = false;
  
  if (!kIsWeb) {
    // Kiểm tra nhanh: app có được launch từ alarm notification không?
    // Chỉ init plugin + check launch details, KHÔNG cần Firebase
    try {
      isAlarmLaunch = await NotificationService().checkAlarmLaunch();
    } catch (e) {
      debugPrint('checkAlarmLaunch error (iOS?): $e');
    }
    
    // Kiểm tra nếu app được launch từ nút "Để sau"
    // Nếu đúng → thoát app ngay, không load UI
    if (NotificationService.pendingPayload == 'water_snooze') {
      isSnoozeLaunch = true;
    }
  }
  
  if (isSnoozeLaunch) {
    // SNOOZE LAUNCH: xử lý snooze rồi thoát (Android) hoặc hiện app (iOS)
    await NotificationService().handleSnoozeLaunchAndExit();
    if (!kIsWeb && Platform.isAndroid) {
      // Android: thoát app ngay, snooze đã được AlarmManager lên lịch
      SystemNavigator.pop();
      return;
    }
    // iOS: không thể thoát app → tiếp tục load Firebase + hiện UI bình thường
    // Snooze notification đã được zonedSchedule lên lịch, sẽ fire đúng giờ
  }
  
  if (!isSnoozeLaunch && isAlarmLaunch) {
    // ALARM LAUNCH: hiện alarm screen NGAY LẬP TỨC, không đợi Firebase
    runApp(const BetterMEApp());
    
    // Init Firebase + NotificationService NGẦM sau khi UI đã hiện
    if (_isFirebaseConfigured) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        debugPrint('Firebase init error: $e');
      }
    }
    try {
      await NotificationService().initialize();
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  } else {
    // Flow bình thường
    if (_isFirebaseConfigured) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } catch (e) {
        debugPrint('Firebase init error: $e');
      }
    }
    
    if (!kIsWeb) {
      try {
        await NotificationService().initialize();
        final permissionGranted = await NotificationService().requestPermission();
        
        // Debug logs cho iOS
        if (Platform.isIOS) {
          debugPrint('🍎 iOS Notification Permission: $permissionGranted');
          
          // Kiểm tra pending notifications
          final pending = await NotificationService()
              .flutterLocalNotificationsPlugin
              .pendingNotificationRequests();
          debugPrint('📱 iOS Pending Notifications: ${pending.length}');
          
          for (var i = 0; i < pending.length && i < 5; i++) {
            debugPrint('   [${i + 1}] ID: ${pending[i].id}, Title: ${pending[i].title}');
          }
          
          if (pending.isEmpty) {
            debugPrint('⚠️ WARNING: No pending notifications on iOS!');
          }
        }
      } catch (e) {
        debugPrint('NotificationService init error: $e');
      }
    }
    
    runApp(const BetterMEApp());
  }
}
