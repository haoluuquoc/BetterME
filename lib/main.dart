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
    // SNOOZE LAUNCH: xử lý snooze trong background rồi thoát app ngay
    // Không hiện UI, không load Firebase
    await NotificationService().handleSnoozeLaunchAndExit();
    // Thoát app ngay lập tức (chỉ Android)
    if (!kIsWeb && Platform.isAndroid) {
      SystemNavigator.pop();
    }
    return;
  } else if (isAlarmLaunch) {
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
        await NotificationService().requestPermission();
      } catch (e) {
        debugPrint('NotificationService init error: $e');
      }
    }
    
    runApp(const BetterMEApp());
  }
}
