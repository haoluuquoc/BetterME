import 'package:flutter/material.dart';
import '../../frontend/screens/splash_screen.dart';
import '../../frontend/screens/login_screen.dart';
import '../../frontend/screens/register_screen.dart';
import '../../frontend/screens/home_screen.dart';
import '../../frontend/screens/habits_screen.dart';
import '../../frontend/screens/statistics_screen.dart';
import '../../frontend/screens/settings_screen.dart';
import '../../frontend/screens/water_alarm_screen.dart';
import '../../frontend/screens/update_alarm_screen.dart';
import '../../frontend/screens/health_screen.dart';

/// Route names
class Routes {
  Routes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String habits = '/habits';
  static const String addHabit = '/habits/add';
  static const String habitDetail = '/habits/detail';
  static const String statistics = '/statistics';
  static const String register = '/register';
  static const String settings = '/settings';
  static const String profile = '/profile';
  static const String waterAlarm = '/water_alarm';
  static const String updateAlarm = '/update_alarm';
  static const String health = '/health';
}

/// Route generator
class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      
      case Routes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      
      case Routes.register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      
      case Routes.home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      
      case Routes.habits:
        return MaterialPageRoute(builder: (_) => const HabitsScreen());
      
      case Routes.statistics:
        return MaterialPageRoute(builder: (_) => const StatisticsScreen());
      
      case Routes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsContent());
      
      case Routes.waterAlarm:
        return MaterialPageRoute(builder: (_) => const WaterAlarmScreen());
      
      case Routes.updateAlarm:
        return MaterialPageRoute(builder: (_) => const UpdateAlarmScreen());
      
      case Routes.health:
        return MaterialPageRoute(builder: (_) => const HealthScreen());
      
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
