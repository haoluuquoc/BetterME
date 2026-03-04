import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app/app.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  bool isAlarmLaunch = false;
  bool isSnoozeLaunch = false;
  
  if (!kIsWeb) {
    // Kiểm tra nhanh: app có được launch từ alarm notification không?
    // Chỉ init plugin + check launch details, KHÔNG cần Firebase
    isAlarmLaunch = await NotificationService().checkAlarmLaunch();
    
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
    // Thoát app ngay lập tức
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    }
    return;
  } else if (isAlarmLaunch) {
    // ALARM LAUNCH: hiện alarm screen NGAY LẬP TỨC, không đợi Firebase
    runApp(const BetterMEApp());
    
    // Init Firebase + NotificationService NGẦM sau khi UI đã hiện
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await NotificationService().initialize();
  } else {
    // Flow bình thường
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    if (!kIsWeb) {
      await NotificationService().initialize();
      await NotificationService().requestPermission();
    }
    
    runApp(const BetterMEApp());
  }
}
