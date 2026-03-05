import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Các màu có sẵn để chọn (giống hình - 3 chấm màu)
class ThemeColors {
  // Màu Đỏ (Red theme)
  static const Color red = Color(0xFFE53935);
  static const Color redDark = Color(0xFFB71C1C);
  static const Color redLight = Color(0xFFEF5350);
  
  // Màu Xanh lá (Green theme)
  static const Color green = Color(0xFF43A047);
  static const Color greenDark = Color(0xFF1B5E20);
  static const Color greenLight = Color(0xFF66BB6A);
  
  // Màu Xanh dương (Blue theme)
  static const Color blue = Color(0xFF1E88E5);
  static const Color blueDark = Color(0xFF0D47A1);
  static const Color blueLight = Color(0xFF42A5F5);
  
  // Màu Tím (Purple theme - giống hình gốc)
  static const Color purple = Color(0xFF7B1FA2);
  static const Color purpleDark = Color(0xFF4A148C);
  static const Color purpleLight = Color(0xFFAB47BC);
  
  // Màu Cam (Orange theme)
  static const Color orange = Color(0xFFFF7043);
  static const Color orangeDark = Color(0xFFE64A19);
  static const Color orangeLight = Color(0xFFFF8A65);
  
  // Màu Hồng (Pink theme)
  static const Color pink = Color(0xFFEC407A);
  static const Color pinkDark = Color(0xFFC2185B);
  static const Color pinkLight = Color(0xFFF48FB1);
}

/// Định nghĩa một theme màu
class AppColorTheme {
  final String id;
  final String name;
  final Color primary;
  final Color primaryDark;
  final Color primaryLight;
  final Color accent;

  const AppColorTheme({
    required this.id,
    required this.name,
    required this.primary,
    required this.primaryDark,
    required this.primaryLight,
    required this.accent,
  });
}

/// Danh sách các theme màu có sẵn
const List<AppColorTheme> availableColorThemes = [
  AppColorTheme(
    id: 'red',
    name: 'Đỏ',
    primary: ThemeColors.red,
    primaryDark: ThemeColors.redDark,
    primaryLight: ThemeColors.redLight,
    accent: ThemeColors.redLight,
  ),
  AppColorTheme(
    id: 'green',
    name: 'Xanh lá',
    primary: ThemeColors.green,
    primaryDark: ThemeColors.greenDark,
    primaryLight: ThemeColors.greenLight,
    accent: ThemeColors.greenLight,
  ),
  AppColorTheme(
    id: 'blue',
    name: 'Xanh dương',
    primary: ThemeColors.blue,
    primaryDark: ThemeColors.blueDark,
    primaryLight: ThemeColors.blueLight,
    accent: ThemeColors.blueLight,
  ),
  AppColorTheme(
    id: 'purple',
    name: 'Tím',
    primary: ThemeColors.purple,
    primaryDark: ThemeColors.purpleDark,
    primaryLight: ThemeColors.purpleLight,
    accent: ThemeColors.purpleLight,
  ),
  AppColorTheme(
    id: 'orange',
    name: 'Cam',
    primary: ThemeColors.orange,
    primaryDark: ThemeColors.orangeDark,
    primaryLight: ThemeColors.orangeLight,
    accent: ThemeColors.orangeLight,
  ),
  AppColorTheme(
    id: 'pink',
    name: 'Hồng',
    primary: ThemeColors.pink,
    primaryDark: ThemeColors.pinkDark,
    primaryLight: ThemeColors.pinkLight,
    accent: ThemeColors.pinkLight,
  ),
];

/// Provider quản lý theme (màu sắc + light/dark mode)
class ThemeProvider extends ChangeNotifier {
  static const String _colorThemeKey = 'selected_color_theme';
  static const String _themeModeKey = 'theme_mode';
  
  AppColorTheme _currentColorTheme = availableColorThemes[2]; // Mặc định: Blue
  ThemeMode _themeMode = ThemeMode.light;
  
  AppColorTheme get currentColorTheme => _currentColorTheme;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  
  ThemeProvider() {
    _loadPreferences();
  }
  
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load color theme
    final colorId = prefs.getString(_colorThemeKey) ?? 'blue';
    _currentColorTheme = availableColorThemes.firstWhere(
      (t) => t.id == colorId,
      orElse: () => availableColorThemes[2],
    );
    
    // Load theme mode
    final modeStr = prefs.getString(_themeModeKey) ?? 'light';
    _themeMode = modeStr == 'dark' ? ThemeMode.dark : ThemeMode.light;
    
    notifyListeners();
  }
  
  Future<void> setColorTheme(AppColorTheme theme) async {
    _currentColorTheme = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_colorThemeKey, theme.id);
    notifyListeners();
  }
  
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }
  
  Future<void> toggleThemeMode() async {
    await setThemeMode(_themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light);
  }
}
