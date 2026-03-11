import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pedometer/pedometer.dart';
import 'firestore_service.dart';

/// Service quản lý sức khỏe: bước chân, giấc ngủ, cân nặng, sinh nhật
class HealthService {
  static final HealthService _instance = HealthService._();
  HealthService._();
  factory HealthService() => _instance;

  StreamSubscription<StepCount>? _stepSubscription;
  final _stepsController = StreamController<int>.broadcast();
  Stream<int> get stepsStream => _stepsController.stream;

  int _todaySteps = 0;
  int get todaySteps => _todaySteps;

  DateTime? _lastSaveTime;

  bool _initialized = false;

  /// Reset state khi đăng xuất — để re-sync Firestore cho user mới
  void resetForLogout() {
    _todaySteps = 0;
    _lastSaveTime = null;
    _initialized = false; // Cho phép init() chạy lại
    _stepsController.add(0);
  }

  /// Khởi tạo step counter
  Future<void> init() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;
    await _loadTodaySteps();
    // Xin quyền ACTIVITY_RECOGNITION trên Android 10+
    if (!kIsWeb && Platform.isAndroid) {
      await _requestActivityRecognition();
    }
    _startListening();
    // Sync dữ liệu từ Firestore nếu local trống (sau cài lại app)
    await _syncFromFirestore();
  }

  /// Đồng bộ TẤT CẢ dữ liệu sức khỏe từ Firestore nếu local trống (sau cài lại app / đổi tài khoản)
  Future<void> _syncFromFirestore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fs = FirestoreService();

      // Sync chiều cao
      if (!prefs.containsKey('user_height_cm')) {
        final height = await fs.loadHeight();
        if (height != null) {
          await prefs.setDouble('user_height_cm', height);
        }
      }

      // Sync sinh nhật
      if ((prefs.getStringList('birthdays') ?? []).isEmpty) {
        final birthdays = await fs.loadBirthdays();
        if (birthdays.isNotEmpty) {
          final list = birthdays.map((b) => '${b['name']}|${b['date']}').toList();
          await prefs.setStringList('birthdays', list);
        }
      }

      // Sync lịch sử sức khỏe (steps, sleep, weight) — 30 ngày
      final needSteps = (prefs.getStringList('steps_history') ?? []).isEmpty;
      final needSleep = (prefs.getStringList('sleep_history') ?? []).isEmpty;
      final needWeight = (prefs.getStringList('weight_history') ?? []).isEmpty;

      if (needSteps || needSleep || needWeight) {
        final history = await fs.loadHealthHistory(30);
        if (history.isNotEmpty) {
          final stepsList = <String>[];
          final sleepList = <String>[];
          final weightList = <String>[];

          for (final day in history) {
            final date = day['date'] as String;
            
            // Steps
            if (needSteps && day['steps'] != null) {
              final steps = (day['steps'] as num).toInt();
              if (steps > 0) stepsList.add('$date|$steps');
            }
            
            // Sleep
            if (needSleep && day['sleepHours'] != null) {
              final hours = (day['sleepHours'] as num).toDouble();
              if (hours > 0) sleepList.add('$date|${hours.toStringAsFixed(1)}');
            }
            
            // Weight
            if (needWeight && day['weightKg'] != null) {
              final kg = (day['weightKg'] as num).toDouble();
              if (kg > 0) weightList.add('$date|${kg.toStringAsFixed(1)}');
            }
          }

          if (stepsList.isNotEmpty) {
            // Sắp xếp theo ngày tăng dần
            stepsList.sort();
            await prefs.setStringList('steps_history', stepsList);
          }
          if (sleepList.isNotEmpty) {
            sleepList.sort();
            await prefs.setStringList('sleep_history', sleepList);
          }
          if (weightList.isNotEmpty) {
            weightList.sort();
            await prefs.setStringList('weight_history', weightList);
          }
        }
      }
    } catch (e) {
      debugPrint('Sync from Firestore error: $e');
    }
  }

  /// Xin quyền ACTIVITY_RECOGNITION trên Android 10+
  Future<void> _requestActivityRecognition() async {
    try {
      const channel = MethodChannel('com.betterme.betterme/app');
      await channel.invokeMethod('requestActivityRecognition');
    } catch (e) {
      debugPrint('Activity recognition permission request error: $e');
    }
  }

  void _startListening() {
    try {
      _stepSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepCountError,
      );
    } catch (e) {
      debugPrint('Pedometer init error: $e');
    }
  }

  void _onStepCount(StepCount event) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final savedDate = prefs.getString('steps_date') ?? '';

    if (savedDate != todayKey) {
      // Ngày mới → lưu lại steps ngày hôm qua trước khi reset
      if (savedDate.isNotEmpty && _todaySteps > 0) {
        await saveTodayStepsToHistory();
      }
      // Reset baseline cho ngày mới
      await prefs.setString('steps_date', todayKey);
      await prefs.setInt('steps_baseline', event.steps);
      _todaySteps = 0;
    } else {
      final baseline = prefs.getInt('steps_baseline') ?? event.steps;
      _todaySteps = event.steps - baseline;
      if (_todaySteps < 0) _todaySteps = 0;
    }

    await prefs.setInt('steps_today', _todaySteps);
    _stepsController.add(_todaySteps);

    // Lưu lịch sử + sync Firestore (debounce mỗi 30 giây)
    await _debouncedSave();
  }

  void _onStepCountError(dynamic error) {
    debugPrint('Step count error: $error');
  }

  /// Debounce: chỉ lưu history + Firestore mỗi 30 giây để tránh ghi quá nhiều
  Future<void> _debouncedSave() async {
    final now = DateTime.now();
    if (_lastSaveTime != null && now.difference(_lastSaveTime!).inSeconds < 30) {
      return;
    }
    _lastSaveTime = now;
    await saveTodayStepsToHistory();
  }

  Future<void> _loadTodaySteps() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('steps_date') ?? '';
    if (savedDate == _todayKey()) {
      _todaySteps = prefs.getInt('steps_today') ?? 0;
    } else {
      _todaySteps = 0;
    }
    _stepsController.add(_todaySteps);
  }

  /// Khoảng cách (km) từ số bước chân (avg stride 0.762m)
  double getDistanceKm(int steps) => steps * 0.000762;

  /// Khoảng cách (m) từ số bước chân
  double getDistanceM(int steps) => steps * 0.762;

  /// Format khoảng cách: dưới 1km → hiện m, từ 1km → hiện km
  String formatDistance(int steps) {
    final meters = getDistanceM(steps);
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} m';
    }
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  /// Calories từ số bước chân (avg 0.04 kcal/step)
  double getCalories(int steps) => steps * 0.04;

  // ===== STEP HISTORY =====

  Future<List<Map<String, dynamic>>> getStepHistory({int days = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('steps_history') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final entry in history.reversed) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        result.add({'date': parts[0], 'steps': int.tryParse(parts[1]) ?? 0});
      }
      if (result.length >= days) break;
    }
    return result;
  }

  /// Lưu steps cuối ngày vào history (gọi khi app resume hoặc midnight)
  Future<void> saveTodayStepsToHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final history = prefs.getStringList('steps_history') ?? [];

    // Xóa entry cũ của hôm nay (nếu có)
    history.removeWhere((e) => e.startsWith('$todayKey|'));
    history.add('$todayKey|$_todaySteps');

    // Giữ 365 ngày
    while (history.length > 365) {
      history.removeAt(0);
    }
    await prefs.setStringList('steps_history', history);

    // Sync to Firestore
    FirestoreService().saveHealthDaily(dateKey: todayKey, steps: _todaySteps);
  }

  // ===== HEIGHT & BMI =====

  Future<void> saveHeight(double cm) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('user_height_cm', cm);

    // Sync to Firestore
    FirestoreService().saveHealthDaily(dateKey: _todayKey(), heightCm: cm);
  }

  Future<double?> getHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('user_height_cm')
        ? prefs.getDouble('user_height_cm')
        : null;
  }

  /// Tính BMI = weight(kg) / height(m)²
  double? calculateBMI(double? weightKg, double? heightCm) {
    if (weightKg == null || heightCm == null || heightCm <= 0) return null;
    final heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }

  /// Phân loại BMI
  String bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Thiếu cân';
    if (bmi < 24.9) return 'Bình thường';
    if (bmi < 30) return 'Thừa cân';
    return 'Béo phì';
  }

  /// Màu cho BMI
  String bmiStatus(double bmi) {
    if (bmi < 18.5) return 'warning';
    if (bmi < 24.9) return 'good';
    if (bmi < 30) return 'warning';
    return 'bad';
  }

  // ===== SLEEP ASSESSMENT =====

  /// Đánh giá giấc ngủ (người lớn 7-9h)
  String sleepAssessment(double? hours) {
    if (hours == null) return '';
    if (hours >= 7 && hours <= 9) return 'good';
    if (hours >= 6 && hours < 7) return 'warning';
    return 'bad';
  }

  String sleepLabel(double? hours) {
    if (hours == null) return '';
    if (hours >= 7 && hours <= 9) return 'Tốt ✅';
    if (hours >= 6 && hours < 7) return 'Hơi thiếu ⚠️';
    if (hours > 9) return 'Ngủ quá nhiều ⚠️';
    return 'Thiếu ngủ ❌';
  }

  // ===== HEALTH RECOMMENDATIONS =====

  List<String> getRecommendations({
    double? sleepHours,
    double? weightKg,
    double? heightCm,
    int steps = 0,
  }) {
    final tips = <String>[];
    final bmi = calculateBMI(weightKg, heightCm);

    // Sleep advice
    if (sleepHours != null) {
      if (sleepHours < 6) {
        tips.add('😴 Bạn ngủ quá ít! Nên ngủ ít nhất 7 giờ mỗi đêm. Hãy cố đi ngủ sớm hơn ${(7 - sleepHours).toStringAsFixed(1)} giờ.');
      } else if (sleepHours < 7) {
        tips.add('😴 Bạn cần ngủ thêm ${(7 - sleepHours).toStringAsFixed(1)} giờ nữa để đạt mức khuyến nghị (7-9 giờ).');
      } else if (sleepHours > 9) {
        tips.add('😴 Ngủ quá 9 giờ có thể gây mệt mỏi. Hãy thử ngủ 7-8 giờ và dậy sớm tập thể dục.');
      }
    }

    // BMI advice
    if (bmi != null) {
      if (bmi < 18.5) {
        final idealWeight = 18.5 * (heightCm! / 100) * (heightCm / 100);
        final needKg = idealWeight - weightKg!;
        tips.add('🍎 BMI ${bmi.toStringAsFixed(1)} - Thiếu cân. Nên tăng ~${needKg.toStringAsFixed(1)} kg. Ăn thêm protein, carb và chất béo lành mạnh.');
        tips.add('🥛 Nên ăn 5-6 bữa nhỏ/ngày, bổ sung sữa, trứng, thịt, cơm, và bơ đậu phộng.');
      } else if (bmi >= 25 && bmi < 30) {
        final idealWeight = 24.9 * (heightCm! / 100) * (heightCm / 100);
        final loseKg = weightKg! - idealWeight;
        tips.add('🏃 BMI ${bmi.toStringAsFixed(1)} - Thừa cân. Nên giảm ~${loseKg.toStringAsFixed(1)} kg.');
        final dailyKm = (loseKg * 0.5).clamp(2.0, 8.0);
        tips.add('🏃 Nên chạy/đi bộ nhanh ${dailyKm.toStringAsFixed(1)} km/ngày và giảm đồ ngọt, đồ chiên.');
      } else if (bmi >= 30) {
        final idealWeight = 24.9 * (heightCm! / 100) * (heightCm / 100);
        final loseKg = weightKg! - idealWeight;
        tips.add('⚠️ BMI ${bmi.toStringAsFixed(1)} - Béo phì. Cần giảm ~${loseKg.toStringAsFixed(1)} kg. Hãy tham khảo ý kiến bác sĩ.');
        tips.add('🏃 Bắt đầu đi bộ nhanh 3-5 km/ngày, tránh nước ngọt và thức ăn nhanh.');
      }
    }

    // Steps advice
    if (steps < 5000) {
      tips.add('👟 Mới đi $steps bước. Mục tiêu 10,000 bước/ngày — hãy đi bộ thêm!');
    } else if (steps < 10000) {
      final remaining = 10000 - steps;
      tips.add('👟 Tốt lắm! Đi thêm ${NumberFormat('#,###').format(remaining)} bước nữa để đạt mục tiêu 10,000 bước.');
    }

    if (tips.isEmpty) {
      tips.add('🎉 Tuyệt vời! Sức khỏe của bạn đang ở mức tốt. Hãy duy trì nhé!');
    }

    return tips;
  }

  // ===== SLEEP TRACKING =====

  Future<void> saveSleepHours(double hours) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final history = prefs.getStringList('sleep_history') ?? [];

    history.removeWhere((e) => e.startsWith('$todayKey|'));
    history.add('$todayKey|${hours.toStringAsFixed(1)}');

    while (history.length > 30) {
      history.removeAt(0);
    }
    await prefs.setStringList('sleep_history', history);

    // Sync to Firestore
    FirestoreService().saveHealthDaily(dateKey: todayKey, sleepHours: hours);
  }

  Future<double?> getTodaySleep() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('sleep_history') ?? [];
    final todayKey = _todayKey();
    for (final entry in history.reversed) {
      if (entry.startsWith('$todayKey|')) {
        return double.tryParse(entry.split('|')[1]);
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getSleepHistory({int days = 7}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('sleep_history') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final entry in history.reversed) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        result.add({
          'date': parts[0],
          'hours': double.tryParse(parts[1]) ?? 0,
        });
      }
      if (result.length >= days) break;
    }
    return result;
  }

  // ===== WEIGHT TRACKING =====

  Future<void> saveWeight(double kg) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _todayKey();
    final history = prefs.getStringList('weight_history') ?? [];

    history.removeWhere((e) => e.startsWith('$todayKey|'));
    history.add('$todayKey|${kg.toStringAsFixed(1)}');

    while (history.length > 90) {
      history.removeAt(0);
    }
    await prefs.setStringList('weight_history', history);

    // Sync to Firestore
    FirestoreService().saveHealthDaily(dateKey: todayKey, weightKg: kg);
  }

  Future<double?> getLatestWeight() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('weight_history') ?? [];
    if (history.isEmpty) return null;
    final parts = history.last.split('|');
    return parts.length == 2 ? double.tryParse(parts[1]) : null;
  }

  Future<List<Map<String, dynamic>>> getWeightHistory({int days = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('weight_history') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final entry in history.reversed) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        result.add({
          'date': parts[0],
          'weight': double.tryParse(parts[1]) ?? 0,
        });
      }
      if (result.length >= days) break;
    }
    return result;
  }

  // ===== BIRTHDAY =====

  Future<List<Map<String, String>>> getBirthdays() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('birthdays') ?? [];
    return list.map((e) {
      final parts = e.split('|');
      return {
        'name': parts[0],
        'date': parts.length > 1 ? parts[1] : '',
      };
    }).toList();
  }

  Future<void> addBirthday(String name, String date) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('birthdays') ?? [];
    list.add('$name|$date');
    await prefs.setStringList('birthdays', list);

    // Sync to Firestore
    final allBirthdays = await getBirthdays();
    FirestoreService().saveBirthdays(allBirthdays);
  }

  Future<void> removeBirthday(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('birthdays') ?? [];
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await prefs.setStringList('birthdays', list);

      // Sync to Firestore
      final allBirthdays = await getBirthdays();
      FirestoreService().saveBirthdays(allBirthdays);
    }
  }

  /// Lấy danh sách tên sinh nhật hôm nay (dd/MM)
  Future<List<String>> getTodayBirthdays() async {
    final now = DateTime.now();
    final today =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}';
    final birthdays = await getBirthdays();
    return birthdays
        .where((b) => b['date'] == today)
        .map((b) => b['name']!)
        .toList();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void dispose() {
    _stepSubscription?.cancel();
    _stepsController.close();
  }
}
