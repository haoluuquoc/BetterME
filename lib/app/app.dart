import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'theme/app_theme.dart';
import 'routes/app_routes.dart';
import '../services/notification_service.dart';

/// Main App Widget
class BetterMEApp extends StatelessWidget {
  const BetterMEApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Nếu app được launch từ notification alarm → vào thẳng WaterAlarmScreen
    // Không qua splash/home để user thấy alarm ngay lập tức
    String initialRoute = Routes.splash;
    if (!kIsWeb && NotificationService.pendingPayload == 'water_alarm_screen') {
      initialRoute = Routes.waterAlarm;
      NotificationService.pendingPayload = null;
    }

    return MaterialApp(
      title: 'BetterME',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      initialRoute: initialRoute,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
