import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'routes/app_routes.dart';
import '../services/notification_service.dart';

/// Main App Widget
class BetterMEApp extends StatelessWidget {
  const BetterMEApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Nếu app được launch từ notification alarm → vào thẳng WaterAlarmScreen
    // CHỈ áp dụng cho Android — iOS không dùng full-screen alarm
    String initialRoute = Routes.splash;
    if (!kIsWeb && NotificationService.pendingPayload == 'water_alarm_screen') {
      if (defaultTargetPlatform == TargetPlatform.android) {
        initialRoute = Routes.waterAlarm;
        NotificationService.pendingPayload = null;
      } else {
        // iOS: chuyển payload thành water_drink_tab để mở tab uống nước thay vì alarm screen
        NotificationService.pendingPayload = 'water_drink_tab';
      }
    } else if (!kIsWeb && NotificationService.pendingPayload == 'update_alarm_screen') {
      initialRoute = Routes.updateAlarm;
      NotificationService.pendingPayload = null;
    }

    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'BetterME',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightThemeWithColor(themeProvider.currentColorTheme),
            darkTheme: AppTheme.darkThemeWithColor(themeProvider.currentColorTheme),
            themeMode: themeProvider.themeMode,
            initialRoute: initialRoute,
            onGenerateRoute: AppRouter.generateRoute,
          );
        },
      ),
    );
  }
}
