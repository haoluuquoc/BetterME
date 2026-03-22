import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Các màu có sẵn - Premium watercolor palette
class ThemeColors {
  // Ocean Blue (default - watercolor blue)
  static const Color oceanBlue = Color(0xFF3A9BD5);
  static const Color oceanBlueDark = Color(0xFF1A6FA0);
  static const Color oceanBlueLight = Color(0xFF5BB5E8);
  
  // Coral Sunset
  static const Color coral = Color(0xFFFF6B6B);
  static const Color coralDark = Color(0xFFD94848);
  static const Color coralLight = Color(0xFFFF8E8E);
  
  // Emerald Green 
  static const Color emerald = Color(0xFF00B894);
  static const Color emeraldDark = Color(0xFF00896E);
  static const Color emeraldLight = Color(0xFF55EEBB);
  
  // Royal Purple
  static const Color royal = Color(0xFF6C5CE7);
  static const Color royalDark = Color(0xFF4834D4);
  static const Color royalLight = Color(0xFFA29BFE);
  
  // Sunset Orange
  static const Color sunset = Color(0xFFFF9F43);
  static const Color sunsetDark = Color(0xFFE17B1A);
  static const Color sunsetLight = Color(0xFFFECA72);
  
  // Rose Pink
  static const Color rose = Color(0xFFE84393);
  static const Color roseDark = Color(0xFFB8256E);
  static const Color roseLight = Color(0xFFF78CB6);
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

/// Danh sách các theme màu có sẵn - Premium palette
const List<AppColorTheme> availableColorThemes = [
  AppColorTheme(
    id: 'blue',
    name: 'Ocean Blue',
    primary: ThemeColors.oceanBlue,
    primaryDark: ThemeColors.oceanBlueDark,
    primaryLight: ThemeColors.oceanBlueLight,
    accent: ThemeColors.oceanBlueLight,
  ),
  AppColorTheme(
    id: 'coral',
    name: 'Coral',
    primary: ThemeColors.coral,
    primaryDark: ThemeColors.coralDark,
    primaryLight: ThemeColors.coralLight,
    accent: ThemeColors.coralLight,
  ),
  AppColorTheme(
    id: 'green',
    name: 'Emerald',
    primary: ThemeColors.emerald,
    primaryDark: ThemeColors.emeraldDark,
    primaryLight: ThemeColors.emeraldLight,
    accent: ThemeColors.emeraldLight,
  ),
  AppColorTheme(
    id: 'purple',
    name: 'Royal',
    primary: ThemeColors.royal,
    primaryDark: ThemeColors.royalDark,
    primaryLight: ThemeColors.royalLight,
    accent: ThemeColors.royalLight,
  ),
  AppColorTheme(
    id: 'orange',
    name: 'Sunset',
    primary: ThemeColors.sunset,
    primaryDark: ThemeColors.sunsetDark,
    primaryLight: ThemeColors.sunsetLight,
    accent: ThemeColors.sunsetLight,
  ),
  AppColorTheme(
    id: 'pink',
    name: 'Rose',
    primary: ThemeColors.rose,
    primaryDark: ThemeColors.roseDark,
    primaryLight: ThemeColors.roseLight,
    accent: ThemeColors.roseLight,
  ),
];

/// Provider quản lý theme (màu sắc + light/dark mode)
class ThemeProvider extends ChangeNotifier {
  static const String _colorThemeKey = 'selected_color_theme';
  static const String _themeModeKey = 'theme_mode';
  
  AppColorTheme _currentColorTheme = availableColorThemes[0]; // Mặc định: Ocean Blue
  ThemeMode _themeMode = ThemeMode.dark; // Mặc định là Dark mode
  
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
      orElse: () => availableColorThemes[0],
    );
    
    // Load theme mode
    final modeStr = prefs.getString(_themeModeKey) ?? 'dark';
    _themeMode = modeStr == 'light' ? ThemeMode.light : ThemeMode.dark;
    
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
